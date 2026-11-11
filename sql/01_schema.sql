-- =====================================================================
-- Housing.com Property Search Database Architecture
-- Checkpoint 1 (CP1): Production Relational Schema Definition
-- 
-- Team Number: 19 | Section: C | Team Name: EchoVault
-- Group Lead: Yash Gupta (2501010523)
-- Target RDBMS: PostgreSQL 18.6 (Homebrew / macOS Apple Silicon)
-- 
-- DESIGN & NORMALIZATION PRINCIPLES:
-- 1. Third Normal Form (3NF) relational model with explicit, controlled
--    denormalization for standalone vs. project listings.
-- 2. Declarative domain integrity: PRIMARY KEY, FOREIGN KEY, COMPOSITE
--    FOREIGN KEY with PostgreSQL 18 column-specific ON DELETE SET NULL,
--    UNIQUE, NOT NULL, and domain CHECK constraints.
-- 3. Cross-entity role integrity via specialized before-triggers.
-- 4. Strict preservation of all 12 seed CSV attributes and relationships.
-- 5. NO artificial/secondary tuning indexes in CP1 (preserving a pristine
--    baseline for CP2/CP3 comparative benchmarking). PostgreSQL creates
--    underlying B-tree indexes only for PRIMARY KEY and UNIQUE constraints.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS housing;
SET search_path TO housing;

-- ---------------------------------------------------------------------
-- 1. CITIES
-- Master geographic dimension defining tier-1 metropolitan clusters.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cities (
    city_id         INT PRIMARY KEY,
    city_name       VARCHAR(100) NOT NULL UNIQUE,
    state           VARCHAR(100) NOT NULL
);

COMMENT ON TABLE cities IS 'Metropolitan cities covered by the Housing.com platform.';
COMMENT ON COLUMN cities.city_id IS 'Unique integer surrogate identifier for each city.';
COMMENT ON COLUMN cities.city_name IS 'Official name of the city (e.g., Bengaluru, Mumbai).';
COMMENT ON COLUMN cities.state IS 'State jurisdiction where the city is located.';

-- ---------------------------------------------------------------------
-- 2. LOCALITIES
-- Sub-market neighborhood zones within each city.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS localities (
    locality_id     INT PRIMARY KEY,
    city_id         INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    locality_name   VARCHAR(150) NOT NULL,
    pincode         CHAR(6) NOT NULL CHECK (pincode ~ '^[0-9]{6}$'),
    center_lat      NUMERIC(9, 6) NOT NULL CHECK (center_lat BETWEEN -90.0 AND 90.0),
    center_lng      NUMERIC(9, 6) NOT NULL CHECK (center_lng BETWEEN -180.0 AND 180.0),
    CONSTRAINT uq_localities_city_locality UNIQUE (city_id, locality_name)
);

COMMENT ON TABLE localities IS 'Sub-market neighborhood zones and pin codes within cities.';
COMMENT ON COLUMN localities.city_id IS 'Foreign key referencing the parent city.';
COMMENT ON COLUMN localities.pincode IS '6-digit Indian postal code.';
COMMENT ON COLUMN localities.center_lat IS 'Centroid latitude for proximity/distance computations.';
COMMENT ON COLUMN localities.center_lng IS 'Centroid longitude for proximity/distance computations.';

-- ---------------------------------------------------------------------
-- 3. BUILDERS
-- Corporate and regional real estate developers.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS builders (
    builder_id      INT PRIMARY KEY,
    builder_name    VARCHAR(200) NOT NULL UNIQUE,
    founded_year    SMALLINT NOT NULL CHECK (founded_year BETWEEN 1800 AND 2100)
);

COMMENT ON TABLE builders IS 'Real estate development companies and construction firms.';
COMMENT ON COLUMN builders.builder_name IS 'Corporate or brand name of the developer.';
COMMENT ON COLUMN builders.founded_year IS 'Four-digit founding year of the developer.';

-- ---------------------------------------------------------------------
-- 4. PROJECTS
-- Multi-unit gated societies, integrated townships, and complexes.
-- Note: UNIQUE (project_id, locality_id) allows properties to enforce
-- project-locality consistency via a composite foreign key.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
    project_id          INT PRIMARY KEY,
    builder_id          INT NOT NULL REFERENCES builders(builder_id) ON DELETE RESTRICT,
    locality_id         INT NOT NULL REFERENCES localities(locality_id) ON DELETE RESTRICT,
    project_name        VARCHAR(200) NOT NULL,
    rera_id             VARCHAR(50) UNIQUE CHECK (rera_id IS NULL OR rera_id ~ '^[A-Z]{2}-RERA-PR-[0-9]+$'),
    possession_status   VARCHAR(20) NOT NULL CHECK (possession_status IN ('READY_TO_MOVE', 'UNDER_CONSTRUCTION')),
    possession_date     DATE NOT NULL,
    total_units         INT NOT NULL CHECK (total_units > 0),
    CONSTRAINT uq_projects_project_locality UNIQUE (project_id, locality_id)
);

COMMENT ON TABLE projects IS 'Housing projects and gated complexes developed by builders.';
COMMENT ON COLUMN projects.rera_id IS 'State Real Estate Regulatory Authority project registration number.';
COMMENT ON COLUMN projects.possession_status IS 'Delivery readiness: READY_TO_MOVE or UNDER_CONSTRUCTION.';
COMMENT ON COLUMN projects.total_units IS 'Total planned/constructed residential inventory in the project.';

-- ---------------------------------------------------------------------
-- 5. AMENITIES
-- Standardized catalog of facilities offered by housing projects.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS amenities (
    amenity_id      INT PRIMARY KEY,
    amenity_name    VARCHAR(100) NOT NULL UNIQUE
);

COMMENT ON TABLE amenities IS 'Master catalog of physical and recreational amenities.';
COMMENT ON COLUMN amenities.amenity_name IS 'Standardized amenity title (e.g., Gym, Swimming Pool, Power Backup).';

-- ---------------------------------------------------------------------
-- 6. PROJECT_AMENITIES
-- Junction table mapping M:N relationships between projects and amenities.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS project_amenities (
    project_id      INT NOT NULL REFERENCES projects(project_id) ON DELETE CASCADE,
    amenity_id      INT NOT NULL REFERENCES amenities(amenity_id) ON DELETE RESTRICT,
    PRIMARY KEY (project_id, amenity_id)
);

COMMENT ON TABLE project_amenities IS 'Junction table linking projects with their available amenities.';

-- ---------------------------------------------------------------------
-- 7. USERS
-- Unified user directory supporting seekers, owners, and agents.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    user_id         INT PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    phone           CHAR(10) NOT NULL UNIQUE CHECK (phone ~ '^[0-9]{10}$'),
    email           VARCHAR(255) UNIQUE CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    user_type       VARCHAR(10) NOT NULL CHECK (user_type IN ('SEEKER', 'OWNER', 'AGENT')),
    agent_rera_id   VARCHAR(50) UNIQUE CHECK (agent_rera_id IS NULL OR agent_rera_id ~ '^AG-RERA-[0-9]+$'),
    created_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_users_agent_rera CHECK (
        (user_type = 'AGENT' AND agent_rera_id IS NOT NULL) OR
        (user_type <> 'AGENT' AND agent_rera_id IS NULL)
    )
);

COMMENT ON TABLE users IS 'User registry supporting home seekers, property owners, and certified agents.';
COMMENT ON COLUMN users.phone IS '10-digit Indian mobile number utilized for authentication.';
COMMENT ON COLUMN users.email IS 'Electronic mail address (nullable, unique when present).';
COMMENT ON COLUMN users.agent_rera_id IS 'Regulatory broker license ID mandatory for AGENT users.';

-- Prevent changing an OWNER or AGENT to SEEKER if they have active or past listings
CREATE OR REPLACE FUNCTION housing.fn_validate_user_type_update()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_type IN ('OWNER', 'AGENT') AND NEW.user_type = 'SEEKER' THEN
        IF EXISTS (SELECT 1 FROM housing.properties WHERE listed_by = OLD.user_id) THEN
            RAISE EXCEPTION 'Constraint Violation: Cannot change user_type to SEEKER for user % who has existing property listings', OLD.user_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_user_type_update ON housing.users;
CREATE TRIGGER trg_validate_user_type_update
BEFORE UPDATE OF user_type ON housing.users
FOR EACH ROW EXECUTE FUNCTION housing.fn_validate_user_type_update();

-- ---------------------------------------------------------------------
-- 8. PROPERTIES
-- Central residential listing entity for rent and sale.
-- Enforces project-locality consistency via composite FK.
-- When a project is deleted, PostgreSQL 18's column-specific action
-- ON DELETE SET NULL (project_id) zeroes project_id while preserving
-- locality_id.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS properties (
    property_id         INT PRIMARY KEY,
    listed_by           INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    project_id          INT,
    locality_id         INT NOT NULL REFERENCES localities(locality_id) ON DELETE RESTRICT,
    listing_type        VARCHAR(10) NOT NULL CHECK (listing_type IN ('RENT', 'SALE')),
    property_type       VARCHAR(20) NOT NULL CHECK (property_type IN ('APARTMENT', 'INDEPENDENT_HOUSE', 'VILLA', 'PLOT')),
    bhk                 SMALLINT CHECK (bhk IS NULL OR (bhk BETWEEN 1 AND 10)),
    carpet_area_sqft    NUMERIC(10, 2) NOT NULL CHECK (carpet_area_sqft > 0),
    floor_no            SMALLINT CHECK (floor_no IS NULL OR floor_no >= 0),
    total_floors        SMALLINT CHECK (total_floors IS NULL OR total_floors >= 0),
    furnishing          VARCHAR(20) CHECK (furnishing IS NULL OR furnishing IN ('UNFURNISHED', 'SEMI_FURNISHED', 'FULLY_FURNISHED')),
    facing              VARCHAR(15) NOT NULL CHECK (facing IN ('NORTH', 'SOUTH', 'EAST', 'WEST', 'NORTH_EAST', 'NORTH_WEST', 'SOUTH_EAST', 'SOUTH_WEST')),
    price               NUMERIC(12, 2) NOT NULL CHECK (price > 0),
    maintenance_monthly NUMERIC(10, 2) CHECK (maintenance_monthly IS NULL OR maintenance_monthly >= 0),
    security_deposit    NUMERIC(12, 2) CHECK (security_deposit IS NULL OR security_deposit >= 0),
    available_from      DATE NOT NULL,
    latitude            NUMERIC(9, 6) NOT NULL CHECK (latitude BETWEEN -90.0 AND 90.0),
    longitude           NUMERIC(9, 6) NOT NULL CHECK (longitude BETWEEN -180.0 AND 180.0),
    is_verified         BOOLEAN NOT NULL DEFAULT FALSE,
    status              VARCHAR(15) NOT NULL CHECK (status IN ('ACTIVE', 'INACTIVE', 'RENTED', 'SOLD')),
    posted_at           TIMESTAMPTZ NOT NULL,
    
    -- Composite FK: Guarantees that when project_id is non-null, locality_id must match the project's locality.
    -- PostgreSQL 18 column-specific ON DELETE SET NULL (project_id) preserves locality_id upon project removal.
    CONSTRAINT fk_properties_project_locality FOREIGN KEY (project_id, locality_id)
        REFERENCES projects(project_id, locality_id) ON DELETE SET NULL (project_id),
    
    -- Status lifecycle alignment
    CONSTRAINT chk_properties_status_lifecycle CHECK (
        (status <> 'RENTED' OR listing_type = 'RENT') AND
        (status <> 'SOLD' OR listing_type = 'SALE')
    ),
    
    -- Security deposit rules (mandatory for rentals, strictly null for outright sales)
    CONSTRAINT chk_properties_security_deposit CHECK (
        (listing_type = 'RENT' AND security_deposit IS NOT NULL) OR
        (listing_type = 'SALE' AND security_deposit IS NULL)
    ),
    
    -- Vertical building physics (floor_no cannot exceed total_floors)
    CONSTRAINT chk_properties_floor_order CHECK (
        floor_no IS NULL OR total_floors IS NULL OR floor_no <= total_floors
    ),
    
    -- Structural dimensions by property typology
    CONSTRAINT chk_properties_structural_dimensions CHECK (
        (property_type = 'PLOT' AND bhk IS NULL AND floor_no IS NULL AND total_floors IS NULL AND furnishing IS NULL) OR
        (property_type IN ('INDEPENDENT_HOUSE', 'VILLA') AND bhk IS NOT NULL AND floor_no IS NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL) OR
        (property_type = 'APARTMENT' AND bhk IS NOT NULL AND floor_no IS NOT NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL)
    )
);

COMMENT ON TABLE properties IS 'Individual residential listings for rent and sale.';
COMMENT ON COLUMN properties.carpet_area_sqft IS 'Usable floor area measured within inner walls in square feet.';
COMMENT ON COLUMN properties.price IS 'Monthly rent for RENT listings or total asking price for SALE listings in INR.';
COMMENT ON COLUMN properties.security_deposit IS 'Security deposit required for lease execution (RENT only).';
COMMENT ON COLUMN properties.maintenance_monthly IS 'Monthly society maintenance fee (nullable, non-negative; present for project listings).';

-- Enforce that only registered OWNER or AGENT accounts can list properties
CREATE OR REPLACE FUNCTION housing.fn_validate_property_lister()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM housing.users
        WHERE user_id = NEW.listed_by AND user_type IN ('OWNER', 'AGENT')
    ) THEN
        RAISE EXCEPTION 'Constraint Violation: Property listed_by user % must have user_type OWNER or AGENT', NEW.listed_by;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_property_lister ON housing.properties;
CREATE TRIGGER trg_validate_property_lister
BEFORE INSERT OR UPDATE OF listed_by ON housing.properties
FOR EACH ROW EXECUTE FUNCTION housing.fn_validate_property_lister();

-- ---------------------------------------------------------------------
-- 9. PRICE_CHANGES
-- Historical audit trail of listing price revisions.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS price_changes (
    change_id       INT PRIMARY KEY,
    property_id     INT NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,
    old_price       NUMERIC(12, 2) NOT NULL CHECK (old_price > 0),
    new_price       NUMERIC(12, 2) NOT NULL CHECK (new_price > 0),
    changed_at      TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_price_changes_differential CHECK (old_price <> new_price)
);

COMMENT ON TABLE price_changes IS 'Historical price revision audit log for properties.';

-- ---------------------------------------------------------------------
-- 10. ENQUIRIES
-- Inbound seeker interest submissions and communication logs.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enquiries (
    enquiry_id      INT PRIMARY KEY,
    property_id     INT NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,
    user_id         INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    channel         VARCHAR(20) NOT NULL CHECK (channel IN ('CALL', 'WHATSAPP', 'FORM')),
    message         TEXT,
    created_at      TIMESTAMPTZ NOT NULL
);

COMMENT ON TABLE enquiries IS 'Prospective seeker leads submitted to property listers.';
COMMENT ON COLUMN enquiries.channel IS 'Communication origin: CALL, WHATSAPP, or web FORM.';

-- ---------------------------------------------------------------------
-- 11. SITE_VISITS
-- Physical walkthrough appointments and visitor feedback evaluations.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS site_visits (
    visit_id        INT PRIMARY KEY,
    property_id     INT NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,
    user_id         INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    scheduled_at    TIMESTAMPTZ NOT NULL,
    status          VARCHAR(20) NOT NULL CHECK (status IN ('SCHEDULED', 'COMPLETED', 'CANCELLED', 'NO_SHOW')),
    feedback_rating SMALLINT CHECK (feedback_rating IS NULL OR feedback_rating BETWEEN 1 AND 5),
    CONSTRAINT chk_site_visits_feedback CHECK (
        (feedback_rating IS NULL AND status IN ('SCHEDULED', 'CANCELLED', 'NO_SHOW')) OR
        (status = 'COMPLETED')
    )
);

COMMENT ON TABLE site_visits IS 'On-site property inspection appointments and post-visit ratings.';
COMMENT ON COLUMN site_visits.status IS 'Appointment status: SCHEDULED, COMPLETED, CANCELLED, NO_SHOW.';
COMMENT ON COLUMN site_visits.feedback_rating IS 'Post-visit visitor satisfaction rating (1 to 5, only on COMPLETED).';

-- ---------------------------------------------------------------------
-- 12. SHORTLISTS
-- Seeker property curation and bookmarking junction table.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shortlists (
    user_id         INT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    property_id     INT NOT NULL REFERENCES properties(property_id) ON DELETE CASCADE,
    added_at        TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, property_id)
);

COMMENT ON TABLE shortlists IS 'Properties bookmarked/shortlisted by prospective seekers.';
