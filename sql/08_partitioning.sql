-- =====================================================================
-- Housing.com Property Search Database Architecture
-- Phase 5 / Checkpoint 4 (CP4): Declarative Table Partitioning Architecture
-- 
-- Team Number: 19 | Section: C | Team Name: EchoVault
-- Group Lead: Yash Gupta (2501010523)
-- Target RDBMS: PostgreSQL 18.6 (Homebrew / macOS Apple Silicon)
-- 
-- PARTITIONING STRATEGY & ARCHITECTURAL JUSTIFICATION:
-- 1. Candidate Table: `housing.properties`
--    - In the 20x large dataset, `properties` contains 2,401,264 rows (358 MB table,
--      >800 MB with indexes), accounting for over 50% of database storage and
--      powering 21 out of 30 workload queries.
-- 2. Partition Key: `RANGE (posted_at)` (Quarterly Intervals)
--    - Workload Alignment: Temporal filters occur heavily across the workload:
--        * R04: Filters by year 2026 (prunes all 2025 data, 50% of table pruned)
--        * R14: Filters 2026 deals (prunes 2025 partitions)
--        * R17: Filters listings older than 90 days (prunes recent partitions)
--        * R20: June 2026 platform growth (prunes down to a single quarter)
--        * W04: Nightly stale listing deactivation (prunes newer partitions)
--    - Empirical Data Distribution:
--        * 2025 Q1: 395,703 rows
--        * 2025 Q2: 400,113 rows
--        * 2025 Q3: 404,490 rows
--        * 2025 Q4: 404,497 rows
--        * 2026 Q1: 395,839 rows
--        * 2026 Q2: 400,566 rows
--        * 2026 Q3: 56 rows
--      Each quarterly partition holds ~400,000 rows (~60 MB), perfectly sized
--      to fit within CPU L3 cache and fit comfortably in PostgreSQL shared_buffers.
-- 3. The PostgreSQL Primary Key Partitioning Rule:
--    - PostgreSQL declarative partitioning mandates that any PRIMARY KEY or UNIQUE
--      constraint on a partitioned table MUST include all partition key columns.
--    - Therefore, the composite primary key must be:
--        PRIMARY KEY (property_id, posted_at)
--    - Foreign key implication: External child tables (enquiries, site_visits)
--      referencing a partitioned table in PostgreSQL must reference the composite PK
--      (property_id, posted_at). In an enterprise architecture where child tables only
--      hold property_id, this constraint is typically enforced via application logic
--      or surrogate lookup tables.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS housing_partitioned;
SET search_path TO housing_partitioned, housing, public;

\echo '===================================================='
\echo 'Creating Partitioned Properties Table (RANGE posted_at)'
\echo '===================================================='

-- Drop existing partitioned table if re-running
DROP TABLE IF EXISTS housing_partitioned.properties CASCADE;

CREATE TABLE housing_partitioned.properties (
    property_id         INT NOT NULL,
    listed_by           INT NOT NULL REFERENCES housing.users(user_id) ON DELETE RESTRICT,
    project_id          INT,
    locality_id         INT NOT NULL REFERENCES housing.localities(locality_id) ON DELETE RESTRICT,
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
    
    -- Mandatory PostgreSQL Partitioning Rule: Partition key must be part of Primary Key
    CONSTRAINT pk_properties_partitioned PRIMARY KEY (property_id, posted_at),
    
    -- Composite FK to housing.projects
    CONSTRAINT fk_part_properties_project_locality FOREIGN KEY (project_id, locality_id)
        REFERENCES housing.projects(project_id, locality_id) ON DELETE SET NULL (project_id),
        
    -- Business Domain CHECK Constraints
    CONSTRAINT chk_part_properties_status_lifecycle CHECK (
        (status <> 'RENTED' OR listing_type = 'RENT') AND
        (status <> 'SOLD' OR listing_type = 'SALE')
    ),
    CONSTRAINT chk_part_properties_security_deposit CHECK (
        (listing_type = 'RENT' AND security_deposit IS NOT NULL) OR
        (listing_type = 'SALE' AND security_deposit IS NULL)
    ),
    CONSTRAINT chk_part_properties_floor_order CHECK (
        floor_no IS NULL OR total_floors IS NULL OR floor_no <= total_floors
    ),
    CONSTRAINT chk_part_properties_structural_dimensions CHECK (
        (property_type = 'PLOT' AND bhk IS NULL AND floor_no IS NULL AND total_floors IS NULL AND furnishing IS NULL) OR
        (property_type IN ('INDEPENDENT_HOUSE', 'VILLA') AND bhk IS NOT NULL AND floor_no IS NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL) OR
        (property_type = 'APARTMENT' AND bhk IS NOT NULL AND floor_no IS NOT NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL)
    )
) PARTITION BY RANGE (posted_at);

-- ---------------------------------------------------------------------
-- Range Partitions by Quarter
-- ---------------------------------------------------------------------
\echo '--> Creating quarterly partitions (2025 Q1 to 2026 Q3 + DEFAULT)...'

CREATE TABLE housing_partitioned.properties_2025_q1 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2025_q2 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2025_q3 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2025_q4 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2026_q1 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2026_q2 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_2026_q3 PARTITION OF housing_partitioned.properties
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

CREATE TABLE housing_partitioned.properties_default PARTITION OF housing_partitioned.properties
    DEFAULT;

-- ---------------------------------------------------------------------
-- Partitioned Table Secondary Indexes
-- (PostgreSQL 18 automatically cascades partition indexes to all child partitions)
-- ---------------------------------------------------------------------
\echo '--> Creating secondary indexes on partitioned table...'

CREATE INDEX idx_part_properties_rent_search
    ON housing_partitioned.properties (locality_id, bhk, price)
    WHERE listing_type = 'RENT' AND status = 'ACTIVE';

CREATE INDEX idx_part_properties_sale_search
    ON housing_partitioned.properties (locality_id, bhk, price)
    WHERE listing_type = 'SALE' AND status = 'ACTIVE' AND property_type = 'APARTMENT';

CREATE INDEX idx_part_properties_active_map
    ON housing_partitioned.properties (latitude, longitude)
    INCLUDE (property_id, price, bhk)
    WHERE listing_type = 'RENT' AND status = 'ACTIVE';

CREATE INDEX idx_part_properties_lister_status
    ON housing_partitioned.properties (listed_by, status, listing_type, property_id);

CREATE INDEX idx_part_properties_project_status
    ON housing_partitioned.properties (project_id, status, bhk, listing_type)
    INCLUDE (price);

CREATE INDEX idx_part_properties_project_id
    ON housing_partitioned.properties (project_id);

CREATE INDEX idx_part_properties_status_posted
    ON housing_partitioned.properties (status, posted_at);

CREATE INDEX idx_part_properties_active_posted
    ON housing_partitioned.properties (posted_at)
    WHERE status = 'ACTIVE';

CREATE INDEX idx_part_properties_posted_desc
    ON housing_partitioned.properties (posted_at DESC);

-- ---------------------------------------------------------------------
-- Zero-Loss Data Migration Pipeline from Non-Partitioned Table
-- ---------------------------------------------------------------------
\echo '--> Migrating data from housing.properties into partitioned structure...'

INSERT INTO housing_partitioned.properties
SELECT * FROM housing.properties;

\echo '--> Gathering optimizer statistics on all partitions...'
ANALYZE housing_partitioned.properties;

-- ---------------------------------------------------------------------
-- Automated Migration Audit & Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_orig_count BIGINT;
    v_part_count BIGINT;
BEGIN
    SELECT count(*) INTO v_orig_count FROM housing.properties;
    SELECT count(*) INTO v_part_count FROM housing_partitioned.properties;
    
    RAISE NOTICE 'Partition Migration Audit: Original = %, Partitioned = %', v_orig_count, v_part_count;
    
    IF v_orig_count <> v_part_count THEN
        RAISE EXCEPTION 'Partition Row Count Mismatch: Original has % rows, Partitioned has % rows', v_orig_count, v_part_count;
    END IF;
    
    RAISE NOTICE 'SUCCESS: 100%% Lossless Migration to Partitioned Table Completed.';
END $$;

-- ---------------------------------------------------------------------
-- Proof of Partition Pruning Verification
-- Query R20 Test: Scanning June 2026 should prune all partitions except properties_2026_q2
-- ---------------------------------------------------------------------
\echo '===================================================='
\echo 'Partition Pruning Verification Plan (Query R20 Test)'
\echo 'Expected: Reads ONLY properties_2026_q2 partition'
\echo '===================================================='
EXPLAIN (ANALYZE, BUFFERS)
SELECT day, listings, sum(listings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT posted_at::date AS day, count(*) AS listings
    FROM housing_partitioned.properties
    WHERE posted_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
      AND posted_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

\echo '===================================================='
\echo 'Declarative Partitioning DDL & Migration Completed.'
\echo '===================================================='
