-- =====================================================================
-- Housing.com Property Search Database Architecture
-- Phase 5 / Checkpoint 4 (CP4): Production Large Dataset Ingestion Pipeline
-- 
-- Team Number: 19 | Section: C | Team Name: EchoVault
-- Group Lead: Yash Gupta (2501010523)
-- Target RDBMS: PostgreSQL 18.6 (Homebrew / macOS Apple Silicon)
-- 
-- PREREQUISITES & EXECUTION INSTRUCTIONS:
-- 1. Ensure large_data/ directory exists in repository root with 12 CSV files.
-- 2. This script expects a clean, empty destination database (e.g. housing_large_db)
--    with the schema created via:
--      psql -d housing_large_db -v ON_ERROR_STOP=1 -f sql/01_schema.sql
-- 3. Execute this script using psql from the project repository root:
--      psql -d housing_large_db -v ON_ERROR_STOP=1 -f sql/02_load_large_data.sql
-- 
-- INGESTION FEATURES:
-- - Pre-load empty table verification guard to prevent accidental duplicate appends.
-- - Atomic transaction block (BEGIN ... COMMIT) with ON_ERROR_STOP active.
-- - Explicit target column lists on all 12 \copy statements, strictly matching
--   the source CSV header specifications in exact column sequence.
-- - Strict Foreign Key dependency ordering (parents before children).
-- - Post-load automated row-count assertion block for all 7,930,894 large records (BIGINT).
-- - Post-load foreign-key relational integrity assertion block (project-locality consistency).
-- - Schema-targeted ANALYZE statements on all 12 housing tables.
-- =====================================================================

\set ON_ERROR_STOP on
SET search_path TO housing;

\echo '===================================================='
\echo 'Starting Housing.com Large Data Ingestion (Atomic)'
\echo 'Expected Total: 7,930,894 records across 12 tables'
\echo '===================================================='

-- Pre-load guard: Ensure destination tables are empty
DO $$
DECLARE
    v_existing_rows BIGINT;
BEGIN
    SELECT count(*) INTO v_existing_rows FROM housing.properties;
    IF v_existing_rows > 0 THEN
        RAISE EXCEPTION 'Destination database is not empty (found % rows in housing.properties). Aborting to prevent duplicate ingestion.', v_existing_rows;
    END IF;
END $$;

BEGIN;

-- 1. CITIES (Expected: 10 rows)
\echo '--> [1/12] Ingesting cities (10 rows)...'
\copy housing.cities(city_id, city_name, state) FROM 'large_data/cities.csv' WITH (FORMAT csv, HEADER true);

-- 2. LOCALITIES (Expected: 100 rows)
\echo '--> [2/12] Ingesting localities (locality_id, city_id, locality_name, pincode, center_lat, center_lng)...'
\copy housing.localities(locality_id, city_id, locality_name, pincode, center_lat, center_lng) FROM 'large_data/localities.csv' WITH (FORMAT csv, HEADER true);

-- 3. BUILDERS (Expected: 150 rows)
\echo '--> [3/12] Ingesting builders (builder_id, builder_name, founded_year)...'
\copy housing.builders(builder_id, builder_name, founded_year) FROM 'large_data/builders.csv' WITH (FORMAT csv, HEADER true);

-- 4. PROJECTS (Expected: 24,000 rows)
\echo '--> [4/12] Ingesting projects (project_id, builder_id, locality_id, project_name, rera_id, possession_status, possession_date, total_units)...'
\copy housing.projects(project_id, builder_id, locality_id, project_name, rera_id, possession_status, possession_date, total_units) FROM 'large_data/projects.csv' WITH (FORMAT csv, HEADER true);

-- 5. AMENITIES (Expected: 15 rows)
\echo '--> [5/12] Ingesting amenities (amenity_id, amenity_name)...'
\copy housing.amenities(amenity_id, amenity_name) FROM 'large_data/amenities.csv' WITH (FORMAT csv, HEADER true);

-- 6. PROJECT_AMENITIES (Expected: 135,921 rows)
\echo '--> [6/12] Ingesting project_amenities (project_id, amenity_id)...'
\copy housing.project_amenities(project_id, amenity_id) FROM 'large_data/project_amenities.csv' WITH (FORMAT csv, HEADER true);

-- 7. USERS (Expected: 800,000 rows)
\echo '--> [7/12] Ingesting users (user_id, full_name, phone, email, user_type, agent_rera_id, created_at)...'
\copy housing.users(user_id, full_name, phone, email, user_type, agent_rera_id, created_at) FROM 'large_data/users.csv' WITH (FORMAT csv, HEADER true);

-- 8. PROPERTIES (Expected: 2,401,264 rows)
\echo '--> [8/12] Ingesting properties (21 attributes, 2.4M records)...'
\copy housing.properties(property_id, listed_by, project_id, locality_id, listing_type, property_type, bhk, carpet_area_sqft, floor_no, total_floors, furnishing, facing, price, maintenance_monthly, security_deposit, available_from, latitude, longitude, is_verified, status, posted_at) FROM 'large_data/properties.csv' WITH (FORMAT csv, HEADER true);

-- 9. PRICE_CHANGES (Expected: 470,019 rows)
\echo '--> [9/12] Ingesting price_changes (change_id, property_id, old_price, new_price, changed_at)...'
\copy housing.price_changes(change_id, property_id, old_price, new_price, changed_at) FROM 'large_data/price_changes.csv' WITH (FORMAT csv, HEADER true);

-- 10. ENQUIRIES (Expected: 2,000,000 rows)
\echo '--> [10/12] Ingesting enquiries (enquiry_id, property_id, user_id, channel, message, created_at)...'
\copy housing.enquiries(enquiry_id, property_id, user_id, channel, message, created_at) FROM 'large_data/enquiries.csv' WITH (FORMAT csv, HEADER true);

-- 11. SITE_VISITS (Expected: 699,415 rows)
\echo '--> [11/12] Ingesting site_visits (visit_id, property_id, user_id, scheduled_at, status, feedback_rating)...'
\copy housing.site_visits(visit_id, property_id, user_id, scheduled_at, status, feedback_rating) FROM 'large_data/site_visits.csv' WITH (FORMAT csv, HEADER true);

-- 12. SHORTLISTS (Expected: 1,400,000 rows)
\echo '--> [12/12] Ingesting shortlists (user_id, property_id, added_at)...'
\copy housing.shortlists(user_id, property_id, added_at) FROM 'large_data/shortlists.csv' WITH (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------
-- Automated Post-Load Reconciliation & Validation Block (Large Dataset)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_cities BIGINT;
    v_localities BIGINT;
    v_builders BIGINT;
    v_projects BIGINT;
    v_amenities BIGINT;
    v_project_amenities BIGINT;
    v_users BIGINT;
    v_properties BIGINT;
    v_price_changes BIGINT;
    v_enquiries BIGINT;
    v_site_visits BIGINT;
    v_shortlists BIGINT;
    v_total BIGINT;
    v_mismatches BIGINT;
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
    
    RAISE NOTICE 'Reconciliation Audit: Total Ingested Records = % (Expected: 7930894)', v_total;
    
    IF v_cities <> 10 THEN RAISE EXCEPTION 'Row count mismatch on cities: % (expected 10)', v_cities; END IF;
    IF v_localities <> 100 THEN RAISE EXCEPTION 'Row count mismatch on localities: % (expected 100)', v_localities; END IF;
    IF v_builders <> 150 THEN RAISE EXCEPTION 'Row count mismatch on builders: % (expected 150)', v_builders; END IF;
    IF v_projects <> 24000 THEN RAISE EXCEPTION 'Row count mismatch on projects: % (expected 24000)', v_projects; END IF;
    IF v_amenities <> 15 THEN RAISE EXCEPTION 'Row count mismatch on amenities: % (expected 15)', v_amenities; END IF;
    IF v_project_amenities <> 135921 THEN RAISE EXCEPTION 'Row count mismatch on project_amenities: % (expected 135921)', v_project_amenities; END IF;
    IF v_users <> 800000 THEN RAISE EXCEPTION 'Row count mismatch on users: % (expected 800000)', v_users; END IF;
    IF v_properties <> 2401264 THEN RAISE EXCEPTION 'Row count mismatch on properties: % (expected 2401264)', v_properties; END IF;
    IF v_price_changes <> 470019 THEN RAISE EXCEPTION 'Row count mismatch on price_changes: % (expected 470019)', v_price_changes; END IF;
    IF v_enquiries <> 2000000 THEN RAISE EXCEPTION 'Row count mismatch on enquiries: % (expected 2000000)', v_enquiries; END IF;
    IF v_site_visits <> 699415 THEN RAISE EXCEPTION 'Row count mismatch on site_visits: % (expected 699415)', v_site_visits; END IF;
    IF v_shortlists <> 1400000 THEN RAISE EXCEPTION 'Row count mismatch on shortlists: % (expected 1400000)', v_shortlists; END IF;
    IF v_total <> 7930894 THEN RAISE EXCEPTION 'Total row count mismatch: % (expected 7930894)', v_total; END IF;

    -- Validate Project-Locality consistency across all properties
    SELECT count(*) INTO v_mismatches
    FROM housing.properties p
    JOIN housing.projects pj ON pj.project_id = p.project_id
    WHERE p.locality_id <> pj.locality_id;
    
    IF v_mismatches > 0 THEN
        RAISE EXCEPTION 'Integrity Failure: % properties have locality_id differing from project locality_id', v_mismatches;
    END IF;

    RAISE NOTICE 'All 12 tables passed exact row-count and relational integrity validation for large dataset.';
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
\echo 'Large Dataset Ingestion & Statistical Analysis Completed.'
\echo 'Total Ingested Records: 7,930,894 across 12 tables.'
\echo '===================================================='
