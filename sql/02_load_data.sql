-- =====================================================================
-- Housing.com Property Search Database Architecture
-- Checkpoint 1 (CP1): Production Seed Dataset Ingestion Pipeline
-- 
-- Team Number: 19 | Section: C | Team Name: EchoVault
-- Group Lead: Yash Gupta (2501010523)
-- Target RDBMS: PostgreSQL 18.6 (Homebrew / macOS Apple Silicon)
-- 
-- PREREQUISITES & EXECUTION INSTRUCTIONS:
-- 1. Ensure seed_data.zip is extracted locally into the seed_data/ directory.
-- 2. This script expects clean, empty destination tables created via:
--      psql -d <database_name> -f sql/01_schema.sql
--    It intentionally avoids destructive TRUNCATE CASCADE commands to ensure
--    safe, non-destructive execution in multi-user database environments.
-- 3. Execute this script using psql from the project repository root:
--      psql -d <database_name> -f sql/02_load_data.sql
-- 
-- INGESTION FEATURES:
-- - Atomic transaction block (BEGIN ... COMMIT) with ON_ERROR_STOP active.
-- - Explicit target column lists on all 12 \copy statements, strictly matching
--   the source CSV header specifications in exact column sequence.
-- - Strict Foreign Key dependency ordering (parents before children).
-- - Post-load automated row-count assertion block (396,885 total records).
-- - Post-load foreign-key relational integrity assertion block.
-- - Schema-targeted ANALYZE statements on all 12 housing tables.
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO housing;

\echo '===================================================='
\echo 'Starting Housing.com Seed Data Ingestion (Atomic)'
\echo '===================================================='

BEGIN;

-- 1. CITIES (Expected: 10 rows)
\echo '--> [1/12] Ingesting cities (10 rows)...'
\copy housing.cities(city_id, city_name, state) FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true);

-- 2. LOCALITIES (Expected: 100 rows)
\echo '--> [2/12] Ingesting localities (locality_id, city_id, locality_name, pincode, center_lat, center_lng)...'
\copy housing.localities(locality_id, city_id, locality_name, pincode, center_lat, center_lng) FROM 'seed_data/localities.csv' WITH (FORMAT csv, HEADER true);

-- 3. BUILDERS (Expected: 150 rows)
\echo '--> [3/12] Ingesting builders (builder_id, builder_name, founded_year)...'
\copy housing.builders(builder_id, builder_name, founded_year) FROM 'seed_data/builders.csv' WITH (FORMAT csv, HEADER true);

-- 4. PROJECTS (Expected: 1,200 rows)
\echo '--> [4/12] Ingesting projects (project_id, builder_id, locality_id, project_name, rera_id, possession_status, possession_date, total_units)...'
\copy housing.projects(project_id, builder_id, locality_id, project_name, rera_id, possession_status, possession_date, total_units) FROM 'seed_data/projects.csv' WITH (FORMAT csv, HEADER true);

-- 5. AMENITIES (Expected: 15 rows)
\echo '--> [5/12] Ingesting amenities (amenity_id, amenity_name)...'
\copy housing.amenities(amenity_id, amenity_name) FROM 'seed_data/amenities.csv' WITH (FORMAT csv, HEADER true);

-- 6. PROJECT_AMENITIES (Expected: 6,806 rows)
\echo '--> [6/12] Ingesting project_amenities (project_id, amenity_id)...'
\copy housing.project_amenities(project_id, amenity_id) FROM 'seed_data/project_amenities.csv' WITH (FORMAT csv, HEADER true);

-- 7. USERS (Expected: 40,000 rows)
\echo '--> [7/12] Ingesting users (user_id, full_name, phone, email, user_type, agent_rera_id, created_at)...'
\copy housing.users(user_id, full_name, phone, email, user_type, agent_rera_id, created_at) FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

-- 8. PROPERTIES (Expected: 120,060 rows)
\echo '--> [8/12] Ingesting properties (21 attributes)...'
\copy housing.properties(property_id, listed_by, project_id, locality_id, listing_type, property_type, bhk, carpet_area_sqft, floor_no, total_floors, furnishing, facing, price, maintenance_monthly, security_deposit, available_from, latitude, longitude, is_verified, status, posted_at) FROM 'seed_data/properties.csv' WITH (FORMAT csv, HEADER true);

-- 9. PRICE_CHANGES (Expected: 23,425 rows)
\echo '--> [9/12] Ingesting price_changes (change_id, property_id, old_price, new_price, changed_at)...'
\copy housing.price_changes(change_id, property_id, old_price, new_price, changed_at) FROM 'seed_data/price_changes.csv' WITH (FORMAT csv, HEADER true);

-- 10. ENQUIRIES (Expected: 100,000 rows)
\echo '--> [10/12] Ingesting enquiries (enquiry_id, property_id, user_id, channel, message, created_at)...'
\copy housing.enquiries(enquiry_id, property_id, user_id, channel, message, created_at) FROM 'seed_data/enquiries.csv' WITH (FORMAT csv, HEADER true);

-- 11. SITE_VISITS (Expected: 35,120 rows)
\echo '--> [11/12] Ingesting site_visits (visit_id, property_id, user_id, scheduled_at, status, feedback_rating)...'
\copy housing.site_visits(visit_id, property_id, user_id, scheduled_at, status, feedback_rating) FROM 'seed_data/site_visits.csv' WITH (FORMAT csv, HEADER true);

-- 12. SHORTLISTS (Expected: 69,999 rows)
\echo '--> [12/12] Ingesting shortlists (user_id, property_id, added_at)...'
\copy housing.shortlists(user_id, property_id, added_at) FROM 'seed_data/shortlists.csv' WITH (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------
-- Automated Post-Load Reconciliation & Validation Block
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cities INT;
    v_localities INT;
    v_builders INT;
    v_projects INT;
    v_amenities INT;
    v_project_amenities INT;
    v_users INT;
    v_properties INT;
    v_price_changes INT;
    v_enquiries INT;
    v_site_visits INT;
    v_shortlists INT;
    v_total BIGINT;
    v_mismatches INT;
BEGIN
    SELECT count(*) INTO v_cities FROM housing.cities;
    SELECT count(*) INTO v_localities FROM housing.localities;
    SELECT count(*) INTO v_builders FROM housing.builders;
    SELECT count(*) INTO v_projects FROM housing.projects;
    SELECT count(*) INTO v_amenities FROM housing.amenities;
    SELECT count(*) INTO v_project_amenities FROM housing.project_amenities;
    SELECT count(*) INTO v_users FROM housing.users;
    SELECT count(*) INTO v_properties FROM housing.properties;
    SELECT count(*) INTO v_price_changes FROM housing.price_changes;
    SELECT count(*) INTO v_enquiries FROM housing.enquiries;
    SELECT count(*) INTO v_site_visits FROM housing.site_visits;
    SELECT count(*) INTO v_shortlists FROM housing.shortlists;
    
    v_total := v_cities + v_localities + v_builders + v_projects + v_amenities +
               v_project_amenities + v_users + v_properties + v_price_changes +
               v_enquiries + v_site_visits + v_shortlists;
    
    RAISE NOTICE 'Reconciliation Audit: Total Ingested Records = % (Expected: 396885)', v_total;
    
    IF v_cities <> 10 THEN RAISE EXCEPTION 'Row count mismatch on cities: %', v_cities; END IF;
    IF v_localities <> 100 THEN RAISE EXCEPTION 'Row count mismatch on localities: %', v_localities; END IF;
    IF v_builders <> 150 THEN RAISE EXCEPTION 'Row count mismatch on builders: %', v_builders; END IF;
    IF v_projects <> 1200 THEN RAISE EXCEPTION 'Row count mismatch on projects: %', v_projects; END IF;
    IF v_amenities <> 15 THEN RAISE EXCEPTION 'Row count mismatch on amenities: %', v_amenities; END IF;
    IF v_project_amenities <> 6806 THEN RAISE EXCEPTION 'Row count mismatch on project_amenities: %', v_project_amenities; END IF;
    IF v_users <> 40000 THEN RAISE EXCEPTION 'Row count mismatch on users: %', v_users; END IF;
    IF v_properties <> 120060 THEN RAISE EXCEPTION 'Row count mismatch on properties: %', v_properties; END IF;
    IF v_price_changes <> 23425 THEN RAISE EXCEPTION 'Row count mismatch on price_changes: %', v_price_changes; END IF;
    IF v_enquiries <> 100000 THEN RAISE EXCEPTION 'Row count mismatch on enquiries: %', v_enquiries; END IF;
    IF v_site_visits <> 35120 THEN RAISE EXCEPTION 'Row count mismatch on site_visits: %', v_site_visits; END IF;
    IF v_shortlists <> 69999 THEN RAISE EXCEPTION 'Row count mismatch on shortlists: %', v_shortlists; END IF;
    IF v_total <> 396885 THEN RAISE EXCEPTION 'Total row count mismatch: %', v_total; END IF;

    -- Validate Project-Locality consistency across all properties
    SELECT count(*) INTO v_mismatches
    FROM housing.properties p
    JOIN housing.projects pj ON pj.project_id = p.project_id
    WHERE p.locality_id <> pj.locality_id;
    
    IF v_mismatches > 0 THEN
        RAISE EXCEPTION 'Integrity Failure: % properties have locality_id differing from project locality_id', v_mismatches;
    END IF;

    RAISE NOTICE 'All 12 tables passed exact row-count and relational integrity validation.';
END $$;

COMMIT;

\echo '----------------------------------------------------'
\echo 'Ingestion committed. Collecting optimizer statistics...'
ANALYZE housing.cities;
ANALYZE housing.localities;
ANALYZE housing.builders;
ANALYZE housing.projects;
ANALYZE housing.amenities;
ANALYZE housing.project_amenities;
ANALYZE housing.users;
ANALYZE housing.properties;
ANALYZE housing.price_changes;
ANALYZE housing.enquiries;
ANALYZE housing.site_visits;
ANALYZE housing.shortlists;

\echo '===================================================='
\echo 'Seed Data Ingestion & Statistical Analysis Completed.'
\echo 'Total Ingested Records: 396,885 across 12 tables.'
\echo '===================================================='
