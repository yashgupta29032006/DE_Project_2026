# Housing.com Property Search Database: Problem Understanding
**Document Version:** 1.1.0 (Audited Second & Third Pass)  
**Project:** Housing.com Property Search Database Architecture & Optimization  
**Team:** 19 (EchoVault) | **Section:** C  
**Authors:** Yash Gupta (Lead), Sneha Bayan, Harshita, Deveshi Sahu  
**Academic Session:** Data Engineering Project 2026  
**Target RDBMS:** PostgreSQL 18.6 (Homebrew, Apple Silicon M4)  

---

## 1. Project Overview & Business Context

Housing.com is one of India's premier online real-estate search portals, connecting prospective home seekers (tenants and buyers), individual property owners, licensed real-estate agents, and commercial builders/developers across 10 major metropolitan cities (Bengaluru, Mumbai, Delhi, Pune, Kolkata, Hyderabad, Chennai, Ahmedabad, Thane, and Gurugram).

The platform serves two primary commercial models:
1. **Rental Marketplace (`RENT`):** High-velocity residential leases where tenants search for apartments, independent houses, or villas with flexible lease terms, mandatory security deposits, and immediate move-in availability.
2. **Resale and Primary Sales (`SALE`):** Capital-intensive transactions encompassing under-construction builder projects, newly completed complexes, secondary-market standalone homes, and vacant residential plots.

The platform coordinates a multi-stage user journey:
- **Discovery:** Multi-attribute filtering (BHK, price per sq ft, furnishing), geo-bounding box map exploration, and project-level amenity filtering.
- **Due Diligence:** Verification badges, builder credentials, delivery timelines, and statutory Real Estate (Regulation and Development) Act (RERA) registration lookups.
- **Lead Generation:** Seeker-to-lister communication across phone calls, WhatsApp, and web inquiry forms.
- **Physical Inspection:** Walkthrough appointment booking and post-visit satisfaction evaluations.
- **Market Engagement:** Property shortlisting, dynamic price-drop tracking, and inventory deactivation upon transaction completion.

---

## 2. Problem Statement & Legacy Architecture Deficiencies

The operational database inherited by the Housing.com Data Engineering team was provisioned without formal schema DDL documentation, foreign key constraints, check constraints, or appropriate database indexes. Only raw comma-separated value (CSV) exports across 12 operational datasets survived.

Due to the lack of strict relational constraints and tailored access paths, internal product engineering teams logged seven major performance and functional bottlenecks (labeled **P1 through P7**). These issues impair customer conversion, degrade partner satisfaction, and threaten platform scalability as listing volume approaches a 20× expansion next year.

---

## 3. Detailed Problem Analysis (P1 – P7)

The table below provides a taxonomy of the reported problems, linking business operational requirements, affected stakeholders, classification, and targeted latency budgets.

| Problem ID | Problem Description | Reporting Team | Primary Stakeholders Affected | Query Classification | Target Latency (Seed / 20× Scale) | Related Workload Queries |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **P1** | **Rent & Buy Search Latency:** Multi-attribute filtering (BHK, price per sq ft, furnishing), geo-bounding box map queries, and project amenity lookups suffer noticeable latency. | Search & Discovery | Home Seekers, Tenants, Buyers | **Customer-Facing / Real-Time** | $< 5\text{ ms}$ (at scale) | `R01`, `R02`, `R05`, `R09`, `R16` |
| **P2** | **Listing Detail & Project Due Diligence Lag:** Property landing pages, project profile aggregation, and statutory RERA lookups experience rendering delays. | Listings & Catalog | Buyers, Investors, Legal Due Diligence | **Customer-Facing / Real-Time** | $< 5\text{ ms}$ (at scale) | `R03`, `R10`, `R11`, `R24` |
| **P3** | **Owner & Agent Dashboard Friction:** Real-time metrics (enquiry tallies, scheduled visits), price adjustment updates, and status transitions encounter write locking and slow aggregation. | Supply & Partner Operations | Property Owners, Verified Brokers/Agents | **Customer-Facing / Real-Time** | $< 5\text{ ms}$ (at scale) | `R06`, `R07`, `W01`, `W02`, `W03`, `W05` |
| **P4** | **Automated Alerts & Lead Engagement Timeouts:** Hourly batch scans evaluating 10% price drops, uncontacted leads, and stale listings run out of execution windows. | User Engagement & CRM | Home Seekers, Active Lister Leads | **Interactive Tools / Scheduled Cron** | $< 250\text{ ms}$ (at scale) | `R08`, `R12`, `R17` |
| **P5** | **Builder Partnership Funnel Bug:** The administrative report identifying registered developer projects with zero listed properties consistently returns an empty result set. | Builder Partnerships & B2B Growth | Commercial Builders, Business Development | **Interactive Tools / Catalog Audit** | $< 250\text{ ms}$ (at scale) | `R13` |
| **P6** | **Heavy Analytics & Strategic Insights Timeouts:** Multi-table analytical aggregations (rental yield across localities, agent deal leaderboards, visit ratings, conversion funnels) trigger gateway timeouts. | Data Insights & Executive Strategy | Real Estate Investors, Platform Analysts, City Heads | **Reporting / Analytical OLAP** | $< 5,000\text{ ms}$ (at scale) | `R04`, `R14`, `R15`, `R21`, `R25` |
| **P7** | **Trust, Safety & Moderation Bottlenecks:** Duplicate listing detection (fraud mitigation), deep offset pagination, phone number logins, and listing deactivations stall under scale. | Trust & Safety / Core Platform | Trust & Safety Officers, Compliance, Infrastructure | **Reporting & Platform Batch** | Moderation: $< 5,000\text{ ms}$<br>Batch: $< 1,000\text{ ms}$ | `R18`, `R19`, `R20`, `R22`, `R23`, `W04` |

### Root Cause Analysis of Problem P5 (The "Empty Report" Anomaly)
A SQL audit of Query `R13` identified a textbook three-valued logic flaw:
```sql
SELECT pj.project_id, pj.project_name, pj.possession_status
FROM projects pj
WHERE pj.project_id NOT IN (SELECT p.project_id FROM properties p);
```
In the verified dataset, standalone properties (such as independent houses, villas, plots, and non-gated flats) have `properties.project_id IS NULL` (accounting for 54,009 rows, or 45.0% of all listings). Under ANSI SQL standards, `x NOT IN (..., NULL, ...)` evaluates to `UNKNOWN` whenever `x` is not in the non-null set. Consequently, the `WHERE` clause never evaluates to `TRUE`, causing `R13` to return zero rows. In Phase 4, this query will be optimized to use `NOT EXISTS` or filter out NULLs.

---

## 4. Distinction of Requirements, Observations, and Engineering Decisions

To maintain academic rigor and transparency, the project distinguishes four tiers of domain context:

1. **Faculty-Provided Requirements (Fixed Specifications):**
   - Repository structure, checkpoint schedule, and evaluation criteria (`CHECKPOINTS.md`).
   - The 30 queries in `queries/workload_30.sql` (`R01`–`R25`, `W01`–`W05`) which must run unmodified against the schema.
   - Database engine specification: PostgreSQL 15+ (tested on PostgreSQL 18.6 Homebrew).
   - Dedicated schema namespace: `CREATE SCHEMA housing; SET search_path TO housing;`.
   - Baseline purity: strictly no custom secondary indexes in CP1.
2. **Direct Observations from Seed CSV Datasets:**
   - Total volume: exactly **396,885** records across 12 CSV files.
   - Phone numbers: exactly 40,000 unique 10-digit numbers starting with `960`.
   - Email addresses: exactly 24,010 populated unique emails; 15,990 nulls (40.0% null).
   - Agent licensing: exactly 2,049 users with `user_type = 'AGENT'`, each holding a unique `agent_rera_id`. Non-agents never hold an `agent_rera_id`.
   - Listing supply: all 120,060 listings were posted by `OWNER` (99,674 listings) or `AGENT` (20,386 listings); zero listings from `SEEKER`.
   - Security deposits: all 66,000 `RENT` properties have non-null security deposits; all 54,060 `SALE` properties have null security deposits.
   - Typology physics: all 3,616 `PLOT` properties have null `bhk`, `floor_no`, `total_floors`, and `furnishing`. All 13,434 `INDEPENDENT_HOUSE` and 5,315 `VILLA` properties have non-null `bhk`, `total_floors`, and `furnishing`, but null `floor_no`. All 97,695 `APARTMENT` listings have all four structural attributes populated.
   - Maintenance fees: populated if and only if `project_id IS NOT NULL` (66,051 rows).
   - Project-locality consistency: in all 66,051 project listings, `properties.locality_id` exactly matches `projects.locality_id` with 0 mismatches.
3. **Engineering Assumptions:**
   - Pre-2016 RERA Nullability: 171 projects (14.25%) lack `rera_id` because they were completed before the statutory enactment of the Real Estate (Regulation and Development) Act, 2016.
   - Price Changes as Temporal Log: `properties.price` stores current operational price for low-latency searches, while `price_changes` stores historical audit logs.
4. **Proposed Database Constraints (Implemented in `sql/01_schema.sql`):**
   - Composite Unique Key `projects(project_id, locality_id)` paired with Composite Foreign Key `properties(project_id, locality_id) REFERENCES projects(project_id, locality_id) ON DELETE SET NULL`.
   - Lister Role Trigger (`trg_validate_property_lister`) enforcing `users.user_type IN ('OWNER', 'AGENT')`.
   - Domain CHECK constraints for coordinates, phone format, email regex, RERA regex, structural typology, and post-visit ratings.

---

## 5. Main Entities and Their Responsibilities

The database architecture is centered on 12 distinct relational entities:

```
[cities] ──< [localities] ──< [projects] ──o< [properties] ──< [price_changes]
                 │                 │              │
                 │                 │              ├──< [enquiries]
                 │                 │              ├──< [site_visits]
                 │                 └──< [project_amenities] >── [amenities]
                 │                                │
                 └────────────────────────────────┼──< [shortlists]
                                                  │
                                              [users] 
                                          (Seeker/Owner/Agent)
```

1. **`cities`:** Master geographic dimension (`city_id`, `city_name`, `state`).
2. **`localities`:** Neighborhood micro-markets (`locality_id`, `city_id`, `locality_name`, `pincode`, `center_lat`, `center_lng`).
3. **`builders`:** Real estate development firms (`builder_id`, `builder_name`, `founded_year`).
4. **`projects`:** Multi-unit gated societies and complexes (`project_id`, `builder_id`, `locality_id`, `project_name`, `rera_id`, `possession_status`, `possession_date`, `total_units`).
5. **`amenities`:** Master dictionary of physical and recreational facilities (`amenity_id`, `amenity_name`).
6. **`project_amenities`:** Associative junction table resolving the $M:N$ relationship between `projects` and `amenities` (`project_id`, `amenity_id`).
7. **`users`:** Unified user directory (`user_id`, `full_name`, `phone`, `email`, `user_type`, `agent_rera_id`, `created_at`).
8. **`properties`:** Central residential listing entity (`property_id`, `listed_by`, `project_id`, `locality_id`, `listing_type`, `property_type`, `bhk`, `carpet_area_sqft`, `floor_no`, `total_floors`, `furnishing`, `facing`, `price`, `maintenance_monthly`, `security_deposit`, `available_from`, `latitude`, `longitude`, `is_verified`, `status`, `posted_at`).
9. **`price_changes`:** Historical audit log capturing price revisions (`change_id`, `property_id`, `old_price`, `new_price`, `changed_at`).
10. **`enquiries`:** Inbound prospective seeker leads (`enquiry_id`, `property_id`, `user_id`, `channel`, `message`, `created_at`).
11. **`site_visits`:** Walkthrough appointments and post-inspection seeker feedback (`visit_id`, `property_id`, `user_id`, `scheduled_at`, `status`, `feedback_rating`).
12. **`shortlists`:** Seeker curation junction table (`user_id`, `property_id`, `added_at`).

---

## 6. Stakeholders and User Roles

The database supports diverse platform actors:
1. **Home Seekers (Tenants & Buyers):** High-concurrency reads across geo-bounds, budgets, and BHKs. Write operations: shortlisting, sending enquiries, scheduling visits, and rating completed visits.
2. **Individual Property Owners:** Publishing listings, updating prices, managing walkthroughs, marking listings as rented or sold.
3. **Verified Real Estate Agents:** Managing listing portfolios, tracking daily site-visit schedules, and monitoring deal conversion.
4. **Commercial Developers / Builders:** Managing project profiles, tracking inventory absorption, and RERA delivery compliance.
5. **Real Estate Investors & Analysts:** Multi-table aggregations evaluating rental yields, historical price trends, and micromarket capital appreciation.
6. **Trust, Safety & Moderation Officers:** Duplicate listing detection (anti-fraud), stale listing deactivation, and licensing compliance.
7. **Platform Engineering & Growth:** Conversion funnel tracking and system scalability testing.

---

## 7. Data Requirements & Quantitative Reconciliation

The exact record counts across all 12 verified CSV files are tabulated below:

| Entity Name | Source CSV File | Verified Row Count | Nullable Attributes Observed | Distinct Key Domain | Memory Footprint |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `cities` | `seed_data/cities.csv` | 10 | None (0%) | 10 Cities across 9 States | 229 B |
| `localities` | `seed_data/localities.csv` | 100 | None (0%) | 100 Localities, 100 Pincodes | 4.2 KB |
| `builders` | `seed_data/builders.csv` | 150 | None (0%) | 150 Builder firms | 5.0 KB |
| `projects` | `seed_data/projects.csv` | 1,200 | `rera_id` (171 rows / 14.25%) | 1,200 Projects, 1,029 RERA IDs | 92.5 KB |
| `amenities` | `seed_data/amenities.csv` | 15 | None (0%) | 15 Global amenities | 255 B |
| `project_amenities` | `seed_data/project_amenities.csv` | 6,806 | None (0%) | 1,200 Projects linked to 15 Amenities | 44.1 KB |
| `users` | `seed_data/users.csv` | 40,000 | `email` (15,990 / 40.0%), `agent_rera_id` (37,951 / 94.88%) | 40,000 Phones, 2,049 Agents | 3.2 MB |
| `properties` | `seed_data/properties.csv` | 120,060 | `project_id` (45.0%), `bhk` (3.0%), `floor_no` (18.6%), `total_floors` (3.0%), `furnishing` (3.0%), `maintenance_monthly` (45.0%), `security_deposit` (45.0%) | 120,060 Unique Listings | 18.4 MB |
| `price_changes` | `seed_data/price_changes.csv` | 23,425 | None (0%) | 23,425 Audit events | 1.4 MB |
| `enquiries` | `seed_data/enquiries.csv` | 100,000 | `message` (50,057 / 50.06%) | 100,000 Inquiries | 6.2 MB |
| `site_visits` | `seed_data/site_visits.csv` | 35,120 | `feedback_rating` (20,426 / 58.16%) | 35,120 Appointments | 1.9 MB |
| `shortlists` | `seed_data/shortlists.csv` | 69,999 | None (0%) | 69,999 Seeker-property pairs | 2.7 MB |
| **Total System Volume** | **12 Datasets** | **396,885** | — | — | **~34.0 MB** |

*Verification Formula:*  
$$10 + 100 + 150 + 1,200 + 15 + 6,806 + 40,000 + 120,060 + 23,425 + 100,000 + 35,120 + 69,999 = \mathbf{396,885}$$

---

## 8. Entity Relationships and Structural Cardinalities

1. **`cities` to `localities` ($1:N$):** A city contains multiple localities; each locality belongs strictly to one city (`ON DELETE RESTRICT`).
2. **`localities` to `projects` ($1:N$):** A locality hosts multiple projects; each project is physically anchored in one locality.
3. **`builders` to `projects` ($1:N$):** A builder develops multiple projects; each project is developed by one builder.
4. **`projects` to `amenities` ($M:N$ via `project_amenities`):** A project offers multiple amenities; an amenity is offered across multiple projects. Primary key: composite `(project_id, amenity_id)`.
5. **`projects` to `properties` ($0..1:N$, Optional):** A project comprises zero or more properties. A property optionally belongs to zero or one project (54,009 properties are standalone and have `project_id IS NULL`). Enforced via composite foreign key `(project_id, locality_id) REFERENCES projects(project_id, locality_id) ON DELETE SET NULL`.
6. **`localities` to `properties` ($1:N$):** Every property is located in exactly one locality (`ON DELETE RESTRICT`).
7. **`users` to `properties` ($1:N$):** A user (`OWNER` or `AGENT`) lists zero or more properties; each listing has exactly one lister (`listed_by`). Enforced via trigger `trg_validate_property_lister`.
8. **`properties` to `price_changes` ($1:N$):** A property may undergo zero or more historical price adjustments (`ON DELETE CASCADE`).
9. **`properties` to `enquiries` ($1:N$) & `users` to `enquiries` ($1:N$):** Seekers submit enquiries regarding properties (`ON DELETE CASCADE`).
10. **`properties` to `site_visits` ($1:N$) & `users` to `site_visits` ($1:N$):** Seekers book walkthrough appointments for properties (`ON DELETE CASCADE`).
11. **`users` to `properties` ($M:N$ via `shortlists`):** Seekers bookmark multiple properties; properties are shortlisted by multiple seekers. Primary key: composite `(user_id, property_id)`.

---

## 9. Normalization and Functional Dependencies Overview

A comprehensive mathematical decomposition through 1NF, 2NF, 3NF, and BCNF is documented in [`docs/02_schema_design.md`](02_schema_design.md). Key functional dependency highlights include:
- All 12 tables satisfy 1NF (atomic values, no repeating groups) and 2NF (no partial key dependencies).
- Tables `cities`, `localities`, `builders`, `amenities`, `project_amenities`, `price_changes`, `enquiries`, `site_visits`, and `shortlists` strictly satisfy BCNF.
- Table `users` satisfies BCNF with candidate keys $\{user\_id\}$ and $\{phone\}$; nullable unique columns `email` and `agent_rera_id` act as conditional alternate identifiers.
- Table `projects` satisfies BCNF with candidate key $\{project\_id\}$; nullable `rera_id` acts as a conditional alternate identifier.
- Table `properties` satisfies 3NF. It contains a non-key determinant in the conditional dependency $project\_id \rightarrow locality\_id$ (active when $project\_id$ is non-null). This represents a **controlled, justified denormalization** to allow a unified catalog for standalone and project listings, formally safeguarded against anomalies by a composite foreign key on $(project\_id, locality\_id)$.

---

## 10. Scope of Checkpoint 1 (CP1)

**Included in CP1:**
- Problem understanding and business context documentation (`docs/01_problem_understanding.md`).
- Mathematical normalization and schema design documentation (`docs/02_schema_design.md`).
- PostgreSQL 18.6 production DDL script with all constraints (`sql/01_schema.sql`).
- Atomic, verified data loading pipeline (`sql/02_load_data.sql`).
- Entity-Relationship diagrams (`diagrams/er_diagram.svg` and `diagrams/er_diagram.mmd`).
- Live database execution and data reconciliation tests.

**Deferred to Checkpoints 2 through 5:**
- CP2: Baseline query timing and execution plan capture.
- CP3: Secondary indexing (B-tree, partial, expression, GIN) and query rewriting.
- CP4: Scalability evaluation on large datasets (20× volume) and table partitioning.
- CP5: Individual oral defense and analytical evaluation.
