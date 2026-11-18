-- EchoVault / Housing.com CP4 optimized workload
-- These statements preserve the meaning of queries/workload_30.sql.
-- Rewrite and index benefits must be benchmarked with:
-- ./benchmarks/run_benchmark.sh <database> after 3 sql/06_optimized_queries.sql
SET search_path TO housing;
BEGIN;

-- @R01
-- Description: Replaces expression-heavy filtering with index-oriented predicates.
SELECT p.property_id, p.price AS rent, p.carpet_area_sqft, p.furnishing, p.available_from
FROM properties p
JOIN localities l ON l.locality_id = p.locality_id
WHERE l.locality_name = 'Koramangala'
  AND l.city_id = 1
  AND p.listing_type = 'RENT'
  AND p.status = 'ACTIVE'
  AND p.bhk = 2
  AND p.price <= 40000
  AND p.furnishing IN ('SEMI_FURNISHED', 'FULLY_FURNISHED')
ORDER BY p.price;

-- @R02
-- Description: Keeps the original LIMIT semantics and uses direct city/locality filters.
SELECT p.property_id, l.locality_name, p.price, p.carpet_area_sqft,
       round(p.price / p.carpet_area_sqft, 0) AS price_per_sqft
FROM properties p
JOIN localities l ON l.locality_id = p.locality_id
WHERE l.city_id = 6
  AND p.listing_type = 'SALE'
  AND p.status = 'ACTIVE'
  AND p.property_type = 'APARTMENT'
  AND p.bhk = 3
  AND p.price < 12000000
ORDER BY price_per_sqft
LIMIT 30;

-- @R03
-- Description: Pre-aggregates amenities only for the requested project to avoid wide joins.
WITH project_amenity_names AS (
    SELECT pa.project_id,
           string_agg(a.amenity_name, ', ' ORDER BY a.amenity_name) AS amenities
    FROM project_amenities pa
    JOIN amenities a ON a.amenity_id = pa.amenity_id
    WHERE pa.project_id = (SELECT project_id FROM properties WHERE property_id = 6897)
    GROUP BY pa.project_id
)
SELECT p.property_id, p.price, p.bhk, p.carpet_area_sqft,
       pj.project_name, b.builder_name, pa.amenities
FROM properties p
LEFT JOIN projects pj ON pj.project_id = p.project_id
LEFT JOIN builders b ON b.builder_id = pj.builder_id
LEFT JOIN project_amenity_names pa ON pa.project_id = pj.project_id
WHERE p.property_id = 6897;

-- @R04
-- Description: Uses a timestamp range instead of EXTRACT(YEAR FROM ...), enabling range predicates.
SELECT date_trunc('month', p.posted_at) AS month, count(*) AS listings,
       round(avg(p.price / p.carpet_area_sqft), 0) AS avg_price_per_sqft
FROM properties p
JOIN localities l ON l.locality_id = p.locality_id
WHERE l.locality_name = 'Whitefield'
  AND p.listing_type = 'SALE'
  AND p.property_type = 'APARTMENT'
  AND p.posted_at >= TIMESTAMPTZ '2026-01-01 00:00:00+05:30'
  AND p.posted_at < TIMESTAMPTZ '2027-01-01 00:00:00+05:30'
GROUP BY 1
ORDER BY 1;

-- @R05
-- Description: Direct bounding-box predicates remain; partial index narrows active rentals.
SELECT property_id, latitude, longitude, price, bhk
FROM properties
WHERE listing_type = 'RENT'
  AND status = 'ACTIVE'
  AND latitude BETWEEN 12.90 AND 13.00
  AND longitude BETWEEN 77.55 AND 77.65
LIMIT 200;

-- @R06
-- Description: Pre-aggregates enquiries and visits separately, avoiding a high-cardinality cross product.
WITH enquiry_counts AS (
    SELECT property_id, count(*) AS enquiry_count
    FROM enquiries
    GROUP BY property_id
),
visit_counts AS (
    SELECT property_id, count(*) AS visit_count
    FROM site_visits
    GROUP BY property_id
)
SELECT p.property_id, p.listing_type, p.status, p.price,
       COALESCE(e.enquiry_count, 0) AS enquiries,
       COALESCE(v.visit_count, 0) AS visits
FROM properties p
LEFT JOIN enquiry_counts e ON e.property_id = p.property_id
LEFT JOIN visit_counts v ON v.property_id = p.property_id
WHERE p.listed_by = 1033
ORDER BY enquiries DESC;

-- @R07
-- Description: Replaces DATE(scheduled_at) with a half-open timestamp range.
SELECT v.visit_id, v.property_id, v.scheduled_at, u.full_name AS visitor, u.phone
FROM site_visits v
JOIN properties p ON p.property_id = v.property_id
JOIN users u ON u.user_id = v.user_id
WHERE p.listed_by = 4723
  AND v.scheduled_at >= TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
  AND v.scheduled_at < TIMESTAMPTZ '2026-07-02 00:00:00+05:30'
ORDER BY v.scheduled_at;

-- @R08
-- Description: Uses a half-open date range and index-friendly price comparison.
SELECT c.property_id, c.old_price, c.new_price,
       round(100 * (1 - c.new_price / c.old_price), 1) AS drop_pct
FROM price_changes c
JOIN properties p ON p.property_id = c.property_id
WHERE p.status = 'ACTIVE'
  AND c.changed_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND c.changed_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
  AND c.new_price <= c.old_price * 0.9
ORDER BY drop_pct DESC;

-- @R09
-- Description: Replaces IN/subquery with a JOIN and HAVING set count.
SELECT p.property_id, p.price, p.project_id
FROM properties p
JOIN (
    SELECT pa.project_id
    FROM project_amenities pa
    JOIN amenities a ON a.amenity_id = pa.amenity_id
    WHERE a.amenity_name IN ('Gym', 'Swimming Pool', 'Power Backup')
    GROUP BY pa.project_id
    HAVING count(*) = 3
) matching ON matching.project_id = p.project_id
WHERE p.status = 'ACTIVE'
ORDER BY p.price
LIMIT 50;

-- @R10
-- Description: Uses the existing unique RERA index and performs the builder join.
SELECT p.project_id, p.project_name, b.builder_name, p.possession_status, p.possession_date
FROM projects p
JOIN builders b ON b.builder_id = p.builder_id
WHERE p.rera_id = 'TS-RERA-PR-11726342';

-- @R11
-- Description: Keeps the same grouping while narrowing through project/status predicates.
SELECT bhk, listing_type, count(*) AS listings, min(price) AS min_price, max(price) AS max_price
FROM properties
WHERE project_id = 217
  AND status = 'ACTIVE'
GROUP BY bhk, listing_type
ORDER BY bhk, listing_type;

-- @R12
-- Description: Replaces an unbounded lead check with half-open dates and a pair-based NOT EXISTS.
SELECT e.enquiry_id, e.property_id, e.user_id, e.created_at
FROM enquiries e
WHERE e.created_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND e.created_at < TIMESTAMPTZ '2026-06-24 00:00:00+05:30'
  AND NOT EXISTS (
      SELECT 1
      FROM site_visits v
      WHERE v.property_id = e.property_id
        AND v.user_id = e.user_id
  )
ORDER BY e.created_at;

-- @R13
-- Description: NOT EXISTS preserves project-list membership and avoids NOT IN null semantics.
SELECT pj.project_id, pj.project_name, pj.possession_status
FROM projects pj
WHERE NOT EXISTS (
    SELECT 1
    FROM properties p
    WHERE p.project_id = pj.project_id
);

-- @R14
-- Description: Keeps the same agent filter and narrows posted_at with a timestamp range.
SELECT u.user_id, u.full_name, count(*) AS deals
FROM properties p
JOIN users u ON u.user_id = p.listed_by
WHERE u.user_type = 'AGENT'
  AND p.status IN ('SOLD', 'RENTED')
  AND p.posted_at >= TIMESTAMPTZ '2026-01-01 00:00:00+05:30'
GROUP BY u.user_id, u.full_name
ORDER BY deals DESC
LIMIT 20;

-- @R15
-- Description: Uses direct aggregated conditional averages without changing result semantics.
SELECT l.locality_name,
       round(avg(p.price / p.carpet_area_sqft) FILTER (WHERE p.listing_type = 'RENT') * 12, 1) AS yearly_rent_psf,
       round(avg(p.price / p.carpet_area_sqft) FILTER (WHERE p.listing_type = 'SALE'), 0) AS sale_psf,
       round(100 * 12 * avg(p.price / p.carpet_area_sqft) FILTER (WHERE p.listing_type = 'RENT')
                 / avg(p.price / p.carpet_area_sqft) FILTER (WHERE p.listing_type = 'SALE'), 2) AS yield_pct
FROM properties p
JOIN localities l ON l.locality_id = p.locality_id
WHERE l.city_id = 1
  AND p.property_type = 'APARTMENT'
GROUP BY l.locality_name
ORDER BY yield_pct DESC;

-- @R16
-- Description: Preserves leading/trailing wildcard ILIKE semantics; a B-tree name index cannot serve this pattern.
SELECT project_id, project_name, possession_status
FROM projects
WHERE project_name ILIKE '%greens%'
ORDER BY project_name
LIMIT 30;

-- @R17
-- Description: Uses NOT EXISTS and a range-friendly stale-active listing predicate.
SELECT p.property_id, p.listed_by, p.posted_at
FROM properties p
WHERE p.status = 'ACTIVE'
  AND p.posted_at < TIMESTAMPTZ '2026-04-02 00:00:00+05:30'
  AND NOT EXISTS (
      SELECT 1 FROM enquiries e WHERE e.property_id = p.property_id
  )
ORDER BY p.posted_at;

-- @R18
-- Description: Narrows to active listings before grouping duplicate-listing attributes.
SELECT listed_by, locality_id, carpet_area_sqft, floor_no, bhk, count(*) AS copies
FROM properties
WHERE status = 'ACTIVE'
GROUP BY listed_by, locality_id, carpet_area_sqft, floor_no, bhk
HAVING count(*) > 1
ORDER BY copies DESC;

-- @R19
-- Description: Replaces 3,560 correlated full scans with one property-level grouped join.
WITH enquiry_summary AS (
    SELECT property_id,
           count(*) AS enquiries,
           max(created_at) AS last_enquiry_at
    FROM enquiries
    GROUP BY property_id
)
SELECT p.property_id, p.price,
       COALESCE(e.enquiries, 0) AS enquiries,
       e.last_enquiry_at
FROM properties p
JOIN localities l ON l.locality_id = p.locality_id
LEFT JOIN enquiry_summary e ON e.property_id = p.property_id
WHERE l.city_id = 1
  AND p.listing_type = 'SALE'
  AND p.status = 'ACTIVE'
ORDER BY enquiries DESC;

-- @R20
-- Description: Restricts posted_at with an index-friendly range before daily aggregation.
SELECT day, listings, sum(listings) OVER (ORDER BY day) AS running_total
FROM (
    SELECT posted_at::date AS day, count(*) AS listings
    FROM properties
    WHERE posted_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
      AND posted_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
    GROUP BY 1
) d
ORDER BY day;

-- @R21
-- Description: Narrows to rated visits and aggregates once per locality.
SELECT l.locality_name, round(avg(v.feedback_rating), 2) AS avg_rating, count(*) AS rated_visits
FROM site_visits v
JOIN properties p ON p.property_id = v.property_id
JOIN localities l ON l.locality_id = p.locality_id
WHERE v.feedback_rating IS NOT NULL
GROUP BY l.locality_name
HAVING count(*) >= 10
ORDER BY avg_rating DESC;

-- @R22
-- Description: Preserves OFFSET/LIMIT result semantics; posted_at index reduces the deep-page sort cost.
SELECT property_id, listed_by, listing_type, status, price, posted_at
FROM properties
ORDER BY posted_at DESC
OFFSET 50000
LIMIT 25;

-- @R23
-- Description: Uses the existing unique phone index directly.
SELECT user_id, full_name, user_type
FROM users
WHERE phone = '9600001042';

-- @R24
-- Description: Uses a half-open possession-date condition and status predicate.
SELECT pj.project_id, pj.project_name, b.builder_name, pj.possession_date
FROM projects pj
JOIN builders b ON b.builder_id = pj.builder_id
WHERE pj.possession_status = 'UNDER_CONSTRUCTION'
  AND pj.possession_date < DATE '2026-07-01'
ORDER BY pj.possession_date;

-- @R25
-- Description: Keeps the EXISTS conversion test but adds property-first and shortlist indexes.
SELECT l.city_id, count(*) AS shortlists,
       count(*) FILTER (
           WHERE EXISTS (
               SELECT 1
               FROM enquiries e
               WHERE e.property_id = s.property_id
                 AND e.user_id = s.user_id
           )
       ) AS converted
FROM shortlists s
JOIN properties p ON p.property_id = s.property_id
JOIN localities l ON l.locality_id = p.locality_id
GROUP BY l.city_id
ORDER BY l.city_id;

-- @W01
-- Description: Inserts exactly the original property row unchanged.
INSERT INTO properties (property_id, listed_by, locality_id, listing_type, property_type, bhk, carpet_area_sqft, floor_no,
                        total_floors, furnishing, facing, price, security_deposit, available_from, latitude, longitude,
                        status, posted_at)
VALUES (90000001, 1033, 1, 'RENT', 'APARTMENT', 2, 1050, 3, 8, 'SEMI_FURNISHED', 'EAST', 38000, 114000, '2026-07-15',
        12.931200, 77.627000, 'ACTIVE', '2026-07-01 10:00:00+05:30');

-- @W02
-- Description: Reuses the property lookup; the lister/status/type index reduces subquery selection.
UPDATE properties
SET price = round(price * 0.95, -2)
WHERE property_id = (
    SELECT max(property_id)
    FROM properties
    WHERE listed_by = 1033
      AND status = 'ACTIVE'
      AND listing_type = 'RENT'
);

-- @W03
-- Description: Inserts exactly the original site visit unchanged.
INSERT INTO site_visits (visit_id, property_id, user_id, scheduled_at, status)
VALUES (90000001, 6897, 1042, '2026-07-04 11:00:00+05:30', 'SCHEDULED');

-- @W04
-- Description: Uses a range predicate and the active-posted partial index.
UPDATE properties
SET status = 'INACTIVE'
WHERE status = 'ACTIVE'
  AND posted_at < TIMESTAMPTZ '2026-03-03 00:00:00+05:30';

-- @W05
-- Description: Reuses the lister/status/type index to find the oldest matching rental.
UPDATE properties
SET status = 'RENTED'
WHERE property_id = (
    SELECT min(property_id)
    FROM properties
    WHERE listed_by = 1033
      AND status = 'ACTIVE'
      AND listing_type = 'RENT'
);

-- @END
ROLLBACK;
