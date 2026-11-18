-- EchoVault / Housing.com CP4 secondary indexes
-- Run after sql/01_schema.sql and sql/02_load_data.sql.
-- Indexes below are intentionally limited to actual columns and patterns in
-- queries/workload_30.sql. Existing PRIMARY KEY and UNIQUE indexes are not repeated.

SET search_path TO housing;

-- R01: rent, active, 2-BHK listings with a locality and price limit.
CREATE INDEX IF NOT EXISTS idx_properties_rent_search
    ON properties (locality_id, bhk, price)
    WHERE listing_type = 'RENT' AND status = 'ACTIVE';

-- R02: active sale apartments in one city, filtered and ordered by 3 BHK price.
CREATE INDEX IF NOT EXISTS idx_properties_sale_search
    ON properties (locality_id, bhk, price)
    WHERE listing_type = 'SALE' AND status = 'ACTIVE'
      AND property_type = 'APARTMENT';

-- R05: partial-range map search and R18: active duplicate-listing grouping.
CREATE INDEX IF NOT EXISTS idx_properties_active_map
    ON properties (latitude, longitude)
    INCLUDE (property_id, price, bhk)
    WHERE listing_type = 'RENT' AND status = 'ACTIVE';

-- R06 and W02/W05: all owner-listing dashboard and ownership update lookups.
CREATE INDEX IF NOT EXISTS idx_properties_lister_status_type
    ON properties (listed_by, status, listing_type, property_id);

-- R11: project page aggregation for active listings.
CREATE INDEX IF NOT EXISTS idx_properties_project_status
    ON properties (project_id, status, bhk, listing_type)
    INCLUDE (price);

-- R13: anti-join-style detection of projects that have no listing.
CREATE INDEX IF NOT EXISTS idx_properties_project_id
    ON properties (project_id);

-- R14: agent leaderboard statuses and 2026 posting period.
CREATE INDEX IF NOT EXISTS idx_properties_status_posted
    ON properties (status, posted_at);

-- R17 and R18/R20/W04: active-age and date/status filtering.
CREATE INDEX IF NOT EXISTS idx_properties_active_posted
    ON properties (posted_at)
    WHERE status = 'ACTIVE';

-- R22: moderation pagination ordered newest first.
CREATE INDEX IF NOT EXISTS idx_properties_posted_desc
    ON properties (posted_at DESC);

-- R04 and R15: properties grouped by locality and sale/rent analytics.
CREATE INDEX IF NOT EXISTS idx_properties_locality_listing_posted
    ON properties (locality_id, listing_type, property_type, posted_at);

-- R18: duplicate active listings by lister and listing attributes.
CREATE INDEX IF NOT EXISTS idx_properties_active_duplicates
    ON properties (listed_by, locality_id, carpet_area_sqft, floor_no, bhk)
    WHERE status = 'ACTIVE';

-- R08: date-range price-drop audit with property joins.
CREATE INDEX IF NOT EXISTS idx_price_changes_changed_property
    ON price_changes (changed_at, property_id);

-- R19 and R25: grouped/anti-join enquiry lookups by property.
CREATE INDEX IF NOT EXISTS idx_enquiries_property_user_created
    ON enquiries (property_id, user_id, created_at);

-- R12: date-range lead follow-up lookups.
CREATE INDEX IF NOT EXISTS idx_enquiries_created_property_user
    ON enquiries (created_at, property_id, user_id);

-- R07: visits for a property in a scheduled timestamp range.
CREATE INDEX IF NOT EXISTS idx_site_visits_property_scheduled
    ON site_visits (property_id, scheduled_at);

-- R12: pair-based anti-join check for visits booked by the same seeker.
CREATE INDEX IF NOT EXISTS idx_site_visits_property_user
    ON site_visits (property_id, user_id);

-- R21: rated visits grouped by property.
CREATE INDEX IF NOT EXISTS idx_site_visits_property_rating
    ON site_visits (property_id, feedback_rating)
    WHERE feedback_rating IS NOT NULL;

-- R25: property-first conversion checks; complements shortlists' (user_id, property_id) PK.
CREATE INDEX IF NOT EXISTS idx_shortlists_property_user
    ON shortlists (property_id, user_id);

-- R24/R13: possession-status date filtering and project listings.
CREATE INDEX IF NOT EXISTS idx_projects_status_possession
    ON projects (possession_status, possession_date);

-- R03/R09: project-amenity reverse lookup and amenity-set filtering.
CREATE INDEX IF NOT EXISTS idx_project_amenities_amenity_project
    ON project_amenities (amenity_id, project_id);

ANALYZE housing.localities;
ANALYZE housing.properties;
ANALYZE housing.price_changes;
ANALYZE housing.enquiries;
ANALYZE housing.site_visits;
ANALYZE housing.shortlists;
ANALYZE housing.projects;
ANALYZE housing.project_amenities;
