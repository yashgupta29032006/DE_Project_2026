# CP4: Query Optimization and Performance Analysis

**Project:** Housing.com Property Search Database / EchoVault team  
**Team:** 19 (EchoVault) | **Section:** C  
**Baseline engine:** PostgreSQL 18.6, benchmarked on 16 November 2026  
**CP4 status:** SQL optimization and indexes prepared; optimized measurements are pending a runnable PostgreSQL instance

## 1. Overview

CP4 adds secondary indexes and PostgreSQL-compatible rewrites to the established 30-query workload. The goal is to reduce sequential scans and repeated work without changing query results. Customer-facing searches, owner and agent workflows, alerts, and moderation receive more selective access paths; reporting and write workloads are supported by range and foreign-key indexes.

## 2. Existing Query Workload

The repository provides `queries/workload_30.sql` with R01-R25 read queries and W01-W05 write queries. The workload and schema are authoritative. CP4 analyzes all 30 statements:

- Search and listing retrieval: R01-R03, R05, R09-R11, R16
- Ownership and agent workflows: R06-R07, R14, R17, R22
- Engagement: R08, R12
- Analytics: R04, R15, R20-R21, R25
- Trust and moderation: R18-R19, R23-R24
- Write workloads: W01-W05

The baseline `summary.csv` contains 3-run averages. The baseline raw plans are in `benchmarks/results/baseline/*.txt`.

## 3. Performance Bottlenecks

### Confirmed by baseline plans

- **R19:** The raw plan repeats a 100,000-row sequential scan of `enquiries` twice for each of 1,780 result rows. Both subplans report 1,609,120 shared-buffer hits and a 16,875.315 ms average.
- **R25:** The plan performs a 69,999-row shortlist/properties join, materializes it for 100 localities, performs a nested join over 6,929,901 removed join combinations, and a full enquiry scan. Average: 650.680 ms.
- **R22:** The baseline plan uses a sequence scan and external sorting for the 50,000-row offset, averaging 60.715 ms.
- **W04:** Nightly status deactivation of stale listings performs a properties sequential scan and averages 145.394 ms in the baseline rollback benchmark.

### Potential bottlenecks

- R01, R02, R05, R09, R11, R17, R18, R20, R21, R24 and several owner/agent queries have filter, join, grouping, or write predicates that currently lead to sequential scans.
- R16 uses `ILIKE '%greens%'`; a normal B-tree index cannot eliminate a leading wildcard. It remains a theoretical trigram-index candidate requiring `pg_trgm`, which is not established by the current repository.
- R22 can be improved with an index for ORDER BY, but OFFSET 50,000 still reads many rows. A keyset API would be required for deep pagination at large scale.

### Theoretical recommendations

The remaining statements are optimized only through predicates, join restructuring, or appropriate indexes. Actual plan changes and timing improvements have not been measured in this workspace.

## 4. Indexing Strategy

| Index | Table / columns | Type | Supporting workload | Trade-off |
|---|---|---|---|---|
| `idx_properties_rent_search` | `properties(locality_id, bhk, price)` partial to RENT+ACTIVE | Partial B-tree | R01 | Faster rent search; additional write/storage for each active rent row |
| `idx_properties_sale_search` | `properties(locality_id, bhk, price)` partial to sale/apartment/active | Partial B-tree | R02 | Selective but limited to the query shape |
| `idx_properties_active_map` | `(latitude, longitude) INCLUDE (property_id, price, bhk)` partial | B-tree | R05 | Supports the leading latitude bound; modest storage and maintenance cost |
| `idx_properties_lister_status_type` | `(listed_by, status, listing_type, property_id)` | B-tree | R06, W02, W05 | Broad owner/agent support; write overhead |
| `idx_properties_project_status` | `(project_id, status, bhk, listing_type) INCLUDE (price)` | B-tree | R11 | Good for project inventory aggregation |
| `idx_properties_project_id` | `(project_id)` | B-tree | R13 | Foreign-key join and NOT EXISTS support |
| `idx_properties_status_posted` | `(status, posted_at)` | B-tree | R14, time/status filters | Moderate storage; useful only for matching status values |
| `idx_properties_active_posted` | `(posted_at)` partial to ACTIVE | Partial B-tree | R17, R20, W04 | Reduces stale-active maintenance scan |
| `idx_properties_posted_desc` | `(posted_at DESC)` | B-tree | R22 | Avoids sort for newest-page scans; deep OFFSET remains expensive |
| `idx_properties_locality_listing_posted` | `(locality_id, listing_type, property_type, posted_at)` | B-tree | R04, R15 | Supports locality/listing joins and time range |
| `idx_properties_active_duplicates` | `(listed_by, locality_id, carpet_area_sqft, floor_no, bhk)` partial | B-tree | R18 | Grouping support; only a fraud-review workload |
| `idx_price_changes_changed_property` | `(changed_at, property_id)` | B-tree | R08 | Supports June range and property join |
| `idx_enquiries_property_user_created` | `(property_id, user_id, created_at)` | B-tree | R19, R25, R12 | Replaces property-key correlated scans |
| `idx_enquiries_created_property_user` | `(created_at, property_id, user_id)` | B-tree | R12 | Supports date-range lead extraction |
| `idx_site_visits_property_scheduled` | `(property_id, scheduled_at)` | B-tree | R07 | Supports property/date joins |
| `idx_site_visits_property_user` | `(property_id, user_id)` | B-tree | R12 | Supports pair anti-join |
| `idx_site_visits_property_rating` | `(property_id, feedback_rating)` partial | B-tree | R21 | Supports rated-visit joins |
| `idx_shortlists_property_user` | `(property_id, user_id)` | B-tree | R25 | Complements composite PK prefix beginning with `user_id` |
| `idx_projects_status_possession` | `(possession_status, possession_date)` | B-tree | R24 | Direct overdue-project filter |
| `idx_project_amenities_amenity_project` | `(amenity_id, project_id)` | B-tree | R09 | Complements PK `(project_id, amenity_id)` for reverse amenity lookup |

No index was created on `project_name` for R16 because PostgreSQL B-tree indexes do not support a pattern with a leading `%` unless a pattern operator/index is configured. Existing primary-key and unique indexes were not duplicated.

## 5. Query Optimization

- **R01/R02/R05:** Isolate existing search predicates and use partial or composite property indexes. Result columns and ordering remain unchanged.
- **R03:** Pre-aggregates amenity names for the requested project instead of joining amenity rows and grouping the full property detail result.
- **R04:** Replaces `EXTRACT(YEAR...)` with a half-open 2026 timestamp range, preserving the 2026 condition and enabling range predicates.
- **R06:** Separately counts enquiries and visits, preventing duplicate multiplication from joining both child tables.
- **R07:** Replaces `DATE(scheduled_at)` with an indexable two-bound timestamp range.
- **R08:** Replaces a month expression with an exact June half-open range.
- **R09:** Converts `IN (subquery with HAVING)` to an explicit join over project/amenity grouping. Project set and required limit remain the same.
- **R12:** Preserves pairwise `NOT EXISTS` but narrows enquiries by date and uses the matching visit pair index.
- **R13:** Replaces `NOT IN` with `NOT EXISTS`, avoiding null-propagation differences for nullable `project_id` values.
- **R17:** Uses the existing timestamp cut-off and a pair of active-posted/enquiry anti-join access paths.
- **R19:** Replaces two correlated 100,000-row aggregates per result with one property-key aggregate CTE joined once. It preserves `0` count and `NULL` maximum for properties with no enquiry.
- **R20:** Replaces `posted_at::date` range on a function expression with a direct timestamp range, while retaining the daily derivation.
- **R22:** Retains OFFSET/LIMIT semantics and adds descending `posted_at` indexing for the requested newest-first order.
- **R24:** Adds a status/date predicate shape that can use the project status/possession index.
- **R25:** Adds property-first indexes while retaining the exact shortlist count and `EXISTS` conversion filter.
- **W02/W05:** Reformats the maximum/minimum active rental subqueries without changing selected property semantics.
- **W04:** Replaces a 120-day interval expression with the exact same 2026-03-03 cut-off based on the baseline constant.
- **W01/W03:** Preserve inserts unchanged because their single-PK/trigger behavior has no safe semantically equivalent rewrite.

## 6. Benchmark Methodology

The repository benchmark script is `benchmarks/run_benchmark.sh`:

```bash
./benchmarks/run_benchmark.sh <database> baseline 3
./benchmarks/run_benchmark.sh <database> after 3 sql/06_optimized_queries.sql
```

Baseline records come from the completed CP2 run against `housing_cp2` with 396,885 rows, PostgreSQL 18.6, on macOS Apple Silicon M4. The baseline methodology used 3 runs and `EXPLAIN (ANALYZE, BUFFERS)`. Write statements ran in `BEGIN ... ROLLBACK`. The baseline document reports a 16 November 2026 execution date.

No optimized run can be represented as measured here because this workspace has no `psql` executable or reachable PostgreSQL server. Docker is installed, but no Docker daemon is reachable. Seed data can be extracted from `seed_data.zip`, but that alone does not provide a database server or dataset.

## 7. Performance Results

Baseline execution values are copied from `benchmarks/results/baseline/summary.csv`. Optimized values and percentages are intentionally blank and status is `NOT_RUN` in `benchmarks/results/optimized/summary.csv`.

| Query | Baseline avg (ms) | Optimized avg (ms) | Improvement |
|---|---:|---:|---|
| R19 | 16875.315 | NOT_RUN | NOT_RUN |
| R25 | 650.680 | NOT_RUN | NOT_RUN |
| R22 | 60.715 | NOT_RUN | NOT_RUN |
| W04 | 145.394 | NOT_RUN | NOT_RUN |
| Remaining 26 queries | Baseline available | NOT_RUN | NOT_RUN |

No optimized speedup is claimed.

## 8. Execution Plan Analysis

Confirmed baseline observations:

- R19: correlated aggregates executed once per result property and repeatedly sequenced over `enquiries`.
- R25: nested localities/materialized shortlist/property join plus repeated enquiry scan.
- R22: sort-oriented deep offset pagination.
- R17, R18, R04, R11 and several owner queries use sequential property or child-table scans in the baseline plans.

No optimized execution plans exist in this workspace, so replacement with index scans or hash/merge joins cannot yet be claimed.

## 9. Trade-offs

- Every secondary index consumes storage and slows inserts and updates that touch indexed columns.
- Partial indexes reduce storage but are only useful for predicates that match their `WHERE`.
- Composite-column order must match equality filters before range filters.
- B-tree indexes generally help locality, status, date, foreign-key and exact-lookup patterns, but not leading-wildcard text search.
- Planner selectivity can make a sequential scan preferable for broad filters or very small tables.
- Write workloads can regress if indexes are not selective enough. W01/W03 insert additional index entries and should be measured.
- `ANALYZE` is included after index creation so PostgreSQL has up-to-date statistics.

## 10. Conclusion

CP4 prepares 20 targeted index definitions and rewrites for all 30 workload statements. R19 is the clearest confirmed structural issue; R25, R22 and W04 are also confirmed baseline concerns. The baseline 3-run averages are preserved, but no optimized measurement or improvement percent is fabricated.

Before final submission, run:

```bash
unzip -o seed_data.zip
psql -d <database> -f sql/01_schema.sql
psql -d <database> -f sql/02_load_data.sql
psql -d <database> -f sql/05_indexes.sql
./benchmarks/run_benchmark.sh <database> baseline 3
./benchmarks/run_benchmark.sh <database> after 3 sql/06_optimized_queries.sql
```

Do not run baseline benchmarks after loading indexes because baseline and optimized conditions must differ only by the added indexes and optimized workload. Equivalence validation is recommended with result sets or row counts for R01-R25 and transaction rollbacks for W01-W05.
