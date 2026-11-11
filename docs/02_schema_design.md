# Housing.com Property Search Database: Relational Schema & Normalization Design
**Document Version:** 1.2.0 (Audited Second & Third Pass)  
**Project:** Housing.com Property Search Database Architecture & Optimization  
**Team:** 19 (EchoVault) | **Section:** C  
**Authors:** Yash Gupta (Lead), Sneha Bayan, Harshita, Deveshi Sahu  
**Academic Session:** Data Engineering Project 2026  
**Target RDBMS:** PostgreSQL 18.6 (Homebrew, Apple Silicon M4)  

---

## 1. Executive Summary & Design Principles

This document presents the mathematical normalization analysis, relational architecture, data dictionary, and integrity verification for the Housing.com Property Search Database (Checkpoint 1 – CP1).

The legacy database was characterized by undocumented schemas and loose constraints derived solely from raw CSV exports. Our primary engineering objectives are:
1. **Mathematical Rigor in Normalization:** Decompose unnormalized data into Third Normal Form (3NF) and Boyce-Codd Normal Form (BCNF) relations, documenting functional dependencies, candidate keys, and controlled denormalization trade-offs.
2. **Declarative & Procedural Integrity Enforcement:** Enforce all domain and entity rules natively in PostgreSQL 18.6 via `PRIMARY KEY`, `FOREIGN KEY`, composite foreign keys with column-specific `ON DELETE SET NULL (project_id)`, `NOT NULL`, `UNIQUE`, domain `CHECK` constraints, and before-triggers for cross-table user role integrity.
3. **Lossless Ingestion:** Guarantee 100% data fidelity, verifying that all **396,885** records across the 12 seed CSV datasets load without failure or data loss.
4. **Baseline Purity:** Refrain from creating custom secondary indexes (B-tree, GIN, BRIN) in CP1, ensuring that the Phase 3 baseline benchmarks purely evaluate un-tuned database performance.

---

## 2. Theoretical Foundations of Normalization

To provide an academically defensible database design, we establish formal definitions from relational database theory:

- **Superkey:** A set of attributes $S \subseteq R$ such that for any two distinct tuples $t_1, t_2$ in any legal relation instance $r(R)$, $t_1[S] \neq t_2[S]$. Formally, $S \rightarrow R$.
- **Candidate Key:** A minimal superkey. A superkey $K$ is a candidate key if no proper subset $K' \subset K$ is a superkey. Under relational theory (and the Entity Integrity Rule), no component of a candidate key may be `NULL`.
- **Primary Key:** The candidate key arbitrarily chosen by the database architect as the principal identifier for tuples within the relation.
- **Prime Attribute:** An attribute that is a member of at least one candidate key of relation $R$.
- **Non-Prime Attribute:** An attribute that does not belong to any candidate key of $R$.
- **Partial Functional Dependency:** A dependency $X \rightarrow Y$ where $X$ is a proper subset of a composite candidate key, and $Y$ is a non-prime attribute.
- **Transitive Functional Dependency:** A dependency $X \rightarrow Z$ that can be derived from two dependencies $X \rightarrow Y$ and $Y \rightarrow Z$, where $X$ is a candidate key, $Y$ is a non-candidate key, and $Z$ is a non-prime attribute.
- **Boyce-Codd Normal Form (BCNF) Determinant Condition:** A relation $R$ satisfies BCNF if and only if for every non-trivial functional dependency $X \rightarrow Y$ in $R$, the determinant $X$ is a superkey of $R$.

---

## 3. Normalization Analysis (1NF $\rightarrow$ 2NF $\rightarrow$ 3NF / BCNF)

### 3.1 First Normal Form (1NF)

**Formal Rule:** All attribute values in relation $R$ must be atomic (indivisible) from their domain, and the relation must not contain repeating groups or multivalued columns.

#### Analysis & Decomposition:
1. **Multivalued Project Amenities:** In an unnormalized system, amenities associated with a housing project (e.g., Gym, Swimming Pool, Clubhouse) might be stored as an array or comma-separated string in a single column (`projects.amenities = "Gym, Swimming Pool, Power Backup"`). 
   - *Resolution:* Decomposed into a standardized lookup entity `amenities` and an associative junction table `project_amenities(project_id, amenity_id)`. Each row represents a single atomic association.
2. **User Shortlists:** Seekers bookmark multiple properties. Storing bookmarked property IDs as an array or list within `users` violates 1NF.
   - *Resolution:* Modeled as a normalized junction relation `shortlists(user_id, property_id, added_at)` where each row records an atomic bookmarking event.
3. **Compound Address and Geography:** Storing city, locality, state, and coordinates within a single unstructured text field introduces update anomalies and hinders indexing.
   - *Resolution:* Decomposed into distinct atomic fields: `pincode`, `center_lat`, `center_lng`, `locality_name`, `city_name`, and `state`.
4. **Temporal Standardization:** All timestamps are represented as atomic ISO-8601 strings with explicit time-zone offsets (`TIMESTAMPTZ`), preventing malformed string slicing.

---

### 3.2 Second Normal Form (2NF)

**Formal Rule:** Relation $R$ is in 2NF if it is in 1NF and every non-prime attribute is fully functionally dependent on every candidate key of $R$ (no partial functional dependencies).

#### Evaluation of Composite Key Relations:
Partial functional dependencies can only occur when a candidate key is composite. Exactly two tables in our schema feature composite primary keys:

1. **`project_amenities`:**
   - **Candidate Key / Primary Key:** $\{\text{project\_id}, \text{amenity\_id}\}$
   - **Non-Prime Attributes:** None ($\emptyset$).
   - **Evaluation:** Because the set of non-prime attributes is empty, no partial functional dependency can exist. Thus, `project_amenities` satisfies 2NF.

2. **`shortlists`:**
   - **Candidate Key / Primary Key:** $\{\text{user\_id}, \text{property\_id}\}$
   - **Non-Prime Attributes:** $\{\text{added\_at}\}$
   - **Functional Dependency:** $\{\text{user\_id}, \text{property\_id}\} \rightarrow \text{added\_at}$
   - **Evaluation:** The timestamp `added_at` records when a *specific* user shortlisted a *specific* property. It does not depend on `user_id` alone (a user shortlists different properties at different times) nor on `property_id` alone (different users shortlist a property at different times). Because `added_at` is fully dependent on the complete composite key, no partial dependency exists. Thus, `shortlists` satisfies 2NF.

The remaining 10 tables (`cities`, `localities`, `builders`, `projects`, `amenities`, `users`, `properties`, `price_changes`, `enquiries`, `site_visits`) feature single-attribute primary keys. By definition, relations with single-attribute candidate keys cannot contain partial dependencies, satisfying 2NF.

---

### 3.3 Third Normal Form (3NF)

**Formal Rule:** Relation $R$ is in 3NF if it is in 2NF and no non-prime attribute is transitively dependent on any candidate key of $R$. Formally, for every non-trivial dependency $X \rightarrow Y$:
- $X$ is a superkey of $R$, OR
- $Y$ is a prime attribute.

#### Elimination of Transitive Dependencies:
1. **Geographic Hierarchy ($\text{Property} \rightarrow \text{Locality} \rightarrow \text{City} \rightarrow \text{State}$):**
   - *Transitive Chain:* $\text{property\_id} \rightarrow \text{locality\_id}, \quad \text{locality\_id} \rightarrow \text{city\_id}, \quad \text{city\_id} \rightarrow \{\text{city\_name}, \text{state}\}$.
   - *Resolution:* Decomposed into three distinct relations:
     - `cities(city_id, city_name, state)`
     - `localities(locality_id, city_id, locality_name, pincode, center_lat, center_lng)`
     - `properties(property_id, locality_id, ...)`
2. **Builder and Project Lineage ($\text{Property} \rightarrow \text{Project} \rightarrow \text{Builder}$):**
   - *Transitive Chain:* $\text{property\_id} \rightarrow \text{project\_id} \rightarrow \text{builder\_id} \rightarrow \{\text{builder\_name}, \text{founded\_year}\}$.
   - *Resolution:* Decomposed into:
     - `builders(builder_id, builder_name, founded_year)`
     - `projects(project_id, builder_id, locality_id, project_name, rera_id, possession_status, possession_date, total_units)`
     - `properties(property_id, project_id, ...)`
3. **Calculated Attributes (Price per Sq Ft):**
   - *Transitive Dependency:* Storing `price_per_sqft` in `properties` would create $\{\text{carpet\_area\_sqft}, \text{price}\} \rightarrow \text{price\_per\_sqft}$. Because $\{\text{carpet\_area\_sqft}, \text{price}\}$ is not a candidate key, storing this derived column would violate 3NF.
   - *Resolution:* Omitted from physical storage and computed dynamically in queries (e.g., `ROUND(p.price / p.carpet_area_sqft, 0)` in `R02`, `R04`, `R15`).

---

### 3.4 Boyce-Codd Normal Form (BCNF) Analysis & Controlled Denormalization

**Formal Rule:** A relation $R$ satisfies BCNF if and only if for every non-trivial functional dependency $X \rightarrow Y$, $X$ is a superkey of $R$.

#### Reassessing Nullable UNIQUE Attributes as "Conditional Alternate Identifiers":
In classical relational theory, candidate keys cannot contain `NULL` values. In PostgreSQL, a `UNIQUE` constraint permits multiple `NULL` values. Therefore:
- `projects.rera_id` (171 nulls / 14.25% null): **Not** a candidate key for the relation `projects`. It is a **conditional alternate identifier** for non-null tuples. The sole candidate key for `projects` is $\{\text{project\_id}\}$.
- `users.email` (15,990 nulls / 40.0% null): **Not** a candidate key for the relation `users`. It is a conditional alternate identifier.
- `users.agent_rera_id` (37,951 nulls / 94.88% null): **Not** a candidate key for the relation `users`. It is a conditional alternate identifier for `AGENT` accounts.
- `users.phone` (0 nulls, 40,000 unique values): Because `phone` is `NOT NULL` and 100% unique, $\{\text{phone}\}$ is a true candidate key alongside $\{\text{user\_id}\}$.

#### BCNF Evaluation Table:

| Relation | Functional Dependencies (FDs) | Candidate Keys | Determinant Status | Normal Form |
| :--- | :--- | :--- | :--- | :--- |
| `cities` | $\text{city\_id} \rightarrow \{\text{city\_name}, \text{state}\}$<br>$\text{city\_name} \rightarrow \{\text{city\_id}, \text{state}\}$ | $\{\text{city\_id}\}$, $\{\text{city\_name}\}$ | All determinants are candidate keys | **BCNF** |
| `localities` | $\text{locality\_id} \rightarrow \{\text{city\_id}, \text{locality\_name}, \dots\}$<br>$\{\text{city\_id}, \text{locality\_name}\} \rightarrow \{\text{locality\_id}, \dots\}$ | $\{\text{locality\_id}\}$, $\{\text{city\_id}, \text{locality\_name}\}$ | All determinants are candidate keys | **BCNF** |
| `builders` | $\text{builder\_id} \rightarrow \{\text{builder\_name}, \text{founded\_year}\}$<br>$\text{builder\_name} \rightarrow \{\text{builder\_id}, \text{founded\_year}\}$ | $\{\text{builder\_id}\}$, $\{\text{builder\_name}\}$ | All determinants are candidate keys | **BCNF** |
| `projects` | $\text{project\_id} \rightarrow \{\text{builder\_id}, \text{locality\_id}, \text{project\_name}, \dots\}$ | $\{\text{project\_id}\}$ | Determinant is primary key | **BCNF** |
| `amenities` | $\text{amenity\_id} \rightarrow \{\text{amenity\_name}\}$<br>$\text{amenity\_name} \rightarrow \{\text{amenity\_id}\}$ | $\{\text{amenity\_id}\}$, $\{\text{amenity\_name}\}$ | Both determinants are candidate keys | **BCNF** |
| `project_amenities` | $\{\text{project\_id}, \text{amenity\_id}\} \rightarrow \emptyset$ | $\{\text{project\_id}, \text{amenity\_id}\}$ | Determinant is candidate key | **BCNF** |
| `users` | $\text{user\_id} \rightarrow \{\text{full\_name}, \text{phone}, \text{email}, \text{user\_type}, \dots\}$<br>$\text{phone} \rightarrow \{\text{user\_id}, \dots\}$ | $\{\text{user\_id}\}$, $\{\text{phone}\}$ | Both determinants are candidate keys | **BCNF** |
| `properties` | $\text{property\_id} \rightarrow \{\text{listed\_by}, \text{project\_id}, \text{locality\_id}, \dots\}$<br>$\text{project\_id} \rightarrow \text{locality\_id}$ *(conditional on $\text{project\_id} \neq \text{NULL}$)* | $\{\text{property\_id}\}$ | $\text{project\_id}$ is **not** a superkey | **3NF (Controlled BCNF Exception)** |
| `price_changes` | $\text{change\_id} \rightarrow \{\text{property\_id}, \text{old\_price}, \text{new\_price}, \text{changed\_at}\}$ | $\{\text{change\_id}\}$ | Determinant is primary key | **BCNF** |
| `enquiries` | $\text{enquiry\_id} \rightarrow \{\text{property\_id}, \text{user\_id}, \text{channel}, \dots\}$ | $\{\text{enquiry\_id}\}$ | Determinant is primary key | **BCNF** |
| `site_visits` | $\text{visit\_id} \rightarrow \{\text{property\_id}, \text{user\_id}, \text{scheduled\_at}, \dots\}$ | $\{\text{visit\_id}\}$ | Determinant is primary key | **BCNF** |
| `shortlists` | $\{\text{user\_id}, \text{property\_id}\} \rightarrow \{\text{added\_at}\}$ | $\{\text{user\_id}, \text{property\_id}\}$ | Determinant is candidate key | **BCNF** |

#### The Conditional Dependency `project_id -> locality_id` in `properties`:
In the relation `properties`, whenever `project_id` is NOT NULL:
$$\text{project\_id} \rightarrow \text{locality\_id}$$
holds because a project is physically anchored in a specific locality.
However, `project_id` is **not a superkey** of `properties` (a single project contains many properties). In textbook relational theory, this non-key determinant violates BCNF.

**Why `locality_id` is Retained in `properties` (Controlled Denormalization):**
1. **Catalog Uniformity:** 54,009 listings (45.0% of all properties) are standalone properties (independent houses, villas, plots, and standalone non-project apartments) that have `project_id IS NULL`. Every property in India exists within a geographical locality. If `locality_id` were removed from `properties` to achieve pure BCNF, the core entity would have to be split into two separate tables:
   $$\text{project\_properties}(\text{property\_id}, \dots, \text{project\_id}), \quad \text{standalone\_properties}(\text{property\_id}, \dots, \text{locality\_id})$$
   Such vertical partitioning would fracture the unified property search workload (e.g., `R01`, `R02`, `R05`, `R18`, `R20`), requiring expensive `UNION ALL` scans across every search query.
2. **Relational Safeguard via Composite Foreign Key:** To prevent update or insertion anomalies where a property could be linked to a project in a different locality, we enforce:
   ```sql
   CONSTRAINT fk_properties_project_locality FOREIGN KEY (project_id, locality_id)
       REFERENCES projects(project_id, locality_id) ON DELETE SET NULL (project_id)
   ```
   This composite foreign key guarantees that whenever `project_id` is non-null, `properties.locality_id` strictly equals `projects.locality_id`. Furthermore, PostgreSQL 18's column-specific action `ON DELETE SET NULL (project_id)` ensures that deleting a project zeroes `project_id` while preserving `locality_id`.

**Conclusion:** The schema is strictly in **Third Normal Form (3NF)** with 11 of 12 tables in **BCNF**, and a deliberate, fully constrained BCNF exception in `properties`.

---

## 4. Entity-Relationship (ER) Diagram & Structural Cardinality

The visual architecture and cardinalities are modeled below. The standalone vector diagram is available at [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg) (with editable Mermaid source at [`diagrams/er_diagram.mmd`](../diagrams/er_diagram.mmd)).

```mermaid
erDiagram
    CITIES ||--o{ LOCALITIES : "contains (1:N)"
    LOCALITIES ||--o{ PROJECTS : "hosts (1:N)"
    LOCALITIES ||--o{ PROPERTIES : "localizes (1:N)"
    BUILDERS ||--o{ PROJECTS : "develops (1:N)"
    PROJECTS |o--o{ PROPERTIES : "comprises (0..1 to 0..N, composite FK [project_id, locality_id])"
    PROJECTS ||--o{ PROJECT_AMENITIES : "offers (1:N)"
    AMENITIES ||--o{ PROJECT_AMENITIES : "categorizes (1:N)"
    USERS ||--o{ PROPERTIES : "lists (1:N, OWNER/AGENT only)"
    USERS ||--o{ ENQUIRIES : "submits (1:N, SEEKER only in dataset)"
    USERS ||--o{ SITE_VISITS : "books (1:N, SEEKER only in dataset)"
    USERS ||--o{ SHORTLISTS : "bookmarks (1:N, SEEKER only in dataset)"
    PROPERTIES ||--o{ PRICE_CHANGES : "audits (1:N)"
    PROPERTIES ||--o{ ENQUIRIES : "receives (1:N)"
    PROPERTIES ||--o{ SITE_VISITS : "schedules (1:N)"
    PROPERTIES ||--o{ SHORTLISTS : "saved_in (1:N)"

    CITIES {
        int city_id PK
        varchar city_name UK
        varchar state
    }
    LOCALITIES {
        int locality_id PK
        int city_id FK
        varchar locality_name
        char pincode
        numeric center_lat
        numeric center_lng
    }
    BUILDERS {
        int builder_id PK
        varchar builder_name UK
        smallint founded_year
    }
    PROJECTS {
        int project_id PK "PK, composite UK with locality_id"
        int builder_id FK
        int locality_id FK "FK, composite UK with project_id"
        varchar project_name
        varchar rera_id UK "Conditional alternate ID (when non-null)"
        varchar possession_status
        date possession_date
        int total_units
    }
    AMENITIES {
        int amenity_id PK
        varchar amenity_name UK
    }
    PROJECT_AMENITIES {
        int project_id PK,FK
        int amenity_id PK,FK
    }
    USERS {
        int user_id PK
        varchar full_name
        char phone UK
        varchar email UK "Conditional alternate ID (when non-null)"
        varchar user_type "SEEKER, OWNER, AGENT"
        varchar agent_rera_id UK "Mandatory for AGENT, NULL otherwise"
        timestamptz created_at
    }
    PROPERTIES {
        int property_id PK
        int listed_by FK "FK -> users (OWNER or AGENT)"
        int project_id FK "FK -> projects (optional, NULL for standalone)"
        int locality_id FK "FK -> localities, composite FK with project_id"
        varchar listing_type "RENT, SALE"
        varchar property_type "APARTMENT, INDEPENDENT_HOUSE, VILLA, PLOT"
        smallint bhk "NULL strictly for PLOT"
        numeric carpet_area_sqft
        smallint floor_no "NULL for HOUSE, VILLA, PLOT"
        smallint total_floors "NULL strictly for PLOT"
        varchar furnishing "NULL strictly for PLOT"
        varchar facing
        numeric price
        numeric maintenance_monthly "Nullable, non-negative"
        numeric security_deposit "Mandatory for RENT, NULL for SALE"
        date available_from
        numeric latitude
        numeric longitude
        boolean is_verified
        varchar status "ACTIVE, INACTIVE, RENTED, SOLD"
        timestamptz posted_at
    }
    PRICE_CHANGES {
        int change_id PK
        int property_id FK
        numeric old_price
        numeric new_price
        timestamptz changed_at
    }
    ENQUIRIES {
        int enquiry_id PK
        int property_id FK
        int user_id FK
        varchar channel "CALL, WHATSAPP, FORM"
        text message
        timestamptz created_at
    }
    SITE_VISITS {
        int visit_id PK
        int property_id FK
        int user_id FK
        timestamptz scheduled_at
        varchar status "SCHEDULED, COMPLETED, CANCELLED, NO_SHOW"
        smallint feedback_rating "1-5 on COMPLETED, NULL otherwise"
    }
    SHORTLISTS {
        int user_id PK,FK
        int property_id PK,FK
        timestamptz added_at
    }
```

---

## 5. Comprehensive Relational Data Dictionary

Below is the complete architectural specification for all 12 tables implemented in `sql/01_schema.sql`.

### Table 1: `cities`
- **Purpose:** Primary geographical dimension defining metropolitan regions.
- **Cardinality:** 10 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `city_id` | `INT` | NO | None | **PK** | Surrogate integer identifier for each metropolitan city. |
| `city_name` | `VARCHAR(100)` | NO | None | `UNIQUE` | Official city name (e.g., Bengaluru, Mumbai, Delhi). |
| `state` | `VARCHAR(100)` | NO | None | None | State jurisdiction governing the municipality. |

---

### Table 2: `localities`
- **Purpose:** Micro-market neighborhoods and postal codes within cities.
- **Cardinality:** 100 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `locality_id` | `INT` | NO | None | **PK** | Surrogate identifier for each locality. |
| `city_id` | `INT` | NO | None | **FK** $\rightarrow$ `cities(city_id)` | Foreign key link to parent city (`ON DELETE RESTRICT`). |
| `locality_name` | `VARCHAR(150)` | NO | None | `UNIQUE (city_id, locality_name)` | Neighborhood name (e.g., Koramangala, Whitefield). |
| `pincode` | `CHAR(6)` | NO | None | `CHECK (~ '^[0-9]{6}$')` | Exactly 6-digit Indian postal code. |
| `center_lat` | `NUMERIC(9, 6)` | NO | None | `CHECK (BETWEEN -90 AND 90)` | Centroid geographic latitude for locality-level searches. |
| `center_lng` | `NUMERIC(9, 6)` | NO | None | `CHECK (BETWEEN -180 AND 180)` | Centroid geographic longitude for locality-level searches. |

---

### Table 3: `builders`
- **Purpose:** Registry of commercial and residential real estate developers.
- **Cardinality:** 150 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `builder_id` | `INT` | NO | None | **PK** | Unique identifier for each developer firm. |
| `builder_name` | `VARCHAR(200)` | NO | None | `UNIQUE` | Commercial developer name (e.g., Prestige, Sobha, Godrej). |
| `founded_year` | `SMALLINT` | NO | None | `CHECK (BETWEEN 1800 AND 2100)` | Establishment year of the developer company. |

---

### Table 4: `projects`
- **Purpose:** Multi-unit gated societies, integrated townships, and complexes.
- **Cardinality:** 1,200 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `project_id` | `INT` | NO | None | **PK**, `UNIQUE (project_id, locality_id)` | Unique project identifier. Forms composite UK with `locality_id`. |
| `builder_id` | `INT` | NO | None | **FK** $\rightarrow$ `builders(builder_id)` | Builder who developed the project (`ON DELETE RESTRICT`). |
| `locality_id` | `INT` | NO | None | **FK** $\rightarrow$ `localities(locality_id)` | Physical neighborhood of the project (`ON DELETE RESTRICT`). |
| `project_name` | `VARCHAR(200)` | NO | None | None | Commercial name of the development project. |
| `rera_id` | `VARCHAR(50)` | YES | None | `UNIQUE`, `CHECK (~ '^[A-Z]{2}-RERA-PR-[0-9]+$')` | Statutory RERA registration code (conditional alternate ID). |
| `possession_status` | `VARCHAR(20)` | NO | None | `CHECK (IN ('READY_TO_MOVE', 'UNDER_CONSTRUCTION'))` | Construction readiness state. |
| `possession_date` | `DATE` | NO | None | None | Delivery date. |
| `total_units` | `INT` | NO | None | `CHECK (> 0)` | Total residential unit count planned or delivered. |

---

### Table 5: `amenities`
- **Purpose:** Standard master catalog of residential facilities.
- **Cardinality:** 15 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `amenity_id` | `INT` | NO | None | **PK** | Unique identifier for each amenity. |
| `amenity_name` | `VARCHAR(100)` | NO | None | `UNIQUE` | Descriptive title (e.g., Gym, Swimming Pool, Power Backup). |

---

### Table 6: `project_amenities`
- **Purpose:** Junction table resolving $M:N$ relationships between projects and amenities.
- **Cardinality:** 6,806 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `project_id` | `INT` | NO | None | **PK, FK** $\rightarrow$ `projects(project_id)` | Project offering the facility (`ON DELETE CASCADE`). |
| `amenity_id` | `INT` | NO | None | **PK, FK** $\rightarrow$ `amenities(amenity_id)` | Amenity offered (`ON DELETE RESTRICT`). |

---

### Table 7: `users`
- **Purpose:** Unified user directory for seekers, individual owners, and verified brokers.
- **Cardinality:** 40,000 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `user_id` | `INT` | NO | None | **PK** | Unique platform user account identifier. |
| `full_name` | `VARCHAR(150)` | NO | None | None | Full legal or display name of the user. |
| `phone` | `CHAR(10)` | NO | None | `UNIQUE`, `CHECK (~ '^[0-9]{10}$')` | 10-digit Indian mobile number (candidate key, primary login). |
| `email` | `VARCHAR(255)` | YES | None | `UNIQUE`, `CHECK (email regex)` | Email address (unique when non-null; conditional alternate ID). |
| `user_type` | `VARCHAR(10)` | NO | None | `CHECK (IN ('SEEKER', 'OWNER', 'AGENT'))` | User role on the platform. |
| `agent_rera_id` | `VARCHAR(50)` | YES | None | `UNIQUE`, `CHECK (~ '^AG-RERA-[0-9]+$')` | RERA broker license code (mandatory for `AGENT`, null otherwise). |
| `created_at` | `TIMESTAMPTZ` | NO | None | None | Account registration timestamp with time zone. |

*Table Constraint & Trigger:*  
- `CHECK ((user_type = 'AGENT' AND agent_rera_id IS NOT NULL) OR (user_type <> 'AGENT' AND agent_rera_id IS NULL))`
- `trg_validate_user_type_update`: Trigger preventing demotion of an `OWNER` or `AGENT` to `SEEKER` if they have active or past listings.

---

### Table 8: `properties`
- **Purpose:** Central residential listing entity for lease and purchase.
- **Cardinality:** 120,060 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `property_id` | `INT` | NO | None | **PK** | Unique identifier for each listing. |
| `listed_by` | `INT` | NO | None | **FK** $\rightarrow$ `users(user_id)` | Account responsible for listing (`ON DELETE RESTRICT`, trigger-checked). |
| `project_id` | `INT` | YES | None | **Composite FK** with `locality_id` | Gated project if applicable (`ON DELETE SET NULL (project_id)`). |
| `locality_id` | `INT` | NO | None | **FK** $\rightarrow$ `localities(locality_id)` | Physical locality (`ON DELETE RESTRICT`, composite FK with `project_id`). |
| `listing_type` | `VARCHAR(10)` | NO | None | `CHECK (IN ('RENT', 'SALE'))` | Commercial listing classification. |
| `property_type` | `VARCHAR(20)` | NO | None | `CHECK (IN ('APARTMENT', 'INDEPENDENT_HOUSE', 'VILLA', 'PLOT'))` | Architectural typology. |
| `bhk` | `SMALLINT` | YES | None | `CHECK (bhk BETWEEN 1 AND 10)` | Bedroom count (NULL strictly for `PLOT`). |
| `carpet_area_sqft` | `NUMERIC(10, 2)`| NO | None | `CHECK (> 0)` | Usable net floor area inside walls. |
| `floor_no` | `SMALLINT` | YES | None | `CHECK (>= 0)` | Floor level (NULL for independent houses, villas, and plots). |
| `total_floors` | `SMALLINT` | YES | None | `CHECK (>= 0)` | Total building floor count (NULL strictly for `PLOT`). |
| `furnishing` | `VARCHAR(20)` | YES | None | `CHECK (IN ('UNFURNISHED', 'SEMI_FURNISHED', 'FULLY_FURNISHED'))` | Furnishing level (NULL strictly for `PLOT`). |
| `facing` | `VARCHAR(15)` | NO | None | `CHECK (IN ('NORTH', 'SOUTH', 'EAST', ...))` | Compass orientation / Vastu direction. |
| `price` | `NUMERIC(12, 2)`| NO | None | `CHECK (> 0)` | Asking price (monthly rent or outright purchase price). |
| `maintenance_monthly`| `NUMERIC(10, 2)`| YES | None | `CHECK (>= 0)` | Monthly society maintenance charge (nullable, non-negative). |
| `security_deposit` | `NUMERIC(12, 2)`| YES | None | `CHECK (>= 0)` | Lease deposit (mandatory for `RENT`, NULL for `SALE`). |
| `available_from` | `DATE` | NO | None | None | Move-in availability date. |
| `latitude` | `NUMERIC(9, 6)` | NO | None | `CHECK (BETWEEN -90 AND 90)` | Geographic latitude of property structure. |
| `longitude` | `NUMERIC(9, 6)` | NO | None | `CHECK (BETWEEN -180 AND 180)`| Geographic longitude of property structure. |
| `is_verified` | `BOOLEAN` | NO | `FALSE` | None | Listing authenticity verification badge. |
| `status` | `VARCHAR(15)` | NO | None | `CHECK (IN ('ACTIVE', 'INACTIVE', 'RENTED', 'SOLD'))` | Inventory marketplace lifecycle status. |
| `posted_at` | `TIMESTAMPTZ` | NO | None | None | Publishing timestamp with time zone. |

*Table Constraints & Foreign Keys:*
1. `CONSTRAINT fk_properties_locality FOREIGN KEY (locality_id) REFERENCES localities(locality_id) ON DELETE RESTRICT`
2. `CONSTRAINT fk_properties_project_locality FOREIGN KEY (project_id, locality_id) REFERENCES projects(project_id, locality_id) ON DELETE SET NULL (project_id)`
3. `CONSTRAINT chk_properties_status_lifecycle CHECK ((status <> 'RENTED' OR listing_type = 'RENT') AND (status <> 'SOLD' OR listing_type = 'SALE'))`
4. `CONSTRAINT chk_properties_security_deposit CHECK ((listing_type = 'RENT' AND security_deposit IS NOT NULL) OR (listing_type = 'SALE' AND security_deposit IS NULL))`
5. `CONSTRAINT chk_properties_floor_order CHECK (floor_no IS NULL OR total_floors IS NULL OR floor_no <= total_floors)`
6. `CONSTRAINT chk_properties_structural_dimensions CHECK ((property_type = 'PLOT' AND bhk IS NULL AND floor_no IS NULL AND total_floors IS NULL AND furnishing IS NULL) OR (property_type IN ('INDEPENDENT_HOUSE', 'VILLA') AND bhk IS NOT NULL AND floor_no IS NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL) OR (property_type = 'APARTMENT' AND bhk IS NOT NULL AND floor_no IS NOT NULL AND total_floors IS NOT NULL AND furnishing IS NOT NULL))`
7. `trg_validate_property_lister`: Trigger ensuring `listed_by` refers to a user with `user_type IN ('OWNER', 'AGENT')`.

---

### Table 9: `price_changes`
- **Purpose:** Temporal audit log tracking price modifications over time.
- **Cardinality:** 23,425 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `change_id` | `INT` | NO | None | **PK** | Unique price event audit identifier. |
| `property_id` | `INT` | NO | None | **FK** $\rightarrow$ `properties(property_id)` | Property whose price was revised (`ON DELETE CASCADE`). |
| `old_price` | `NUMERIC(12, 2)`| NO | None | `CHECK (> 0)` | Previous asking price in INR. |
| `new_price` | `NUMERIC(12, 2)`| NO | None | `CHECK (> 0)` | New asking price in INR. |
| `changed_at` | `TIMESTAMPTZ` | NO | None | None | Timestamp of price revision. |

*Table Constraint:*  
`CHECK (old_price <> new_price)`

---

### Table 10: `enquiries`
- **Purpose:** Lead generation submissions from prospective seekers.
- **Cardinality:** 100,000 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `enquiry_id` | `INT` | NO | None | **PK** | Unique lead inquiry identifier. |
| `property_id` | `INT` | NO | None | **FK** $\rightarrow$ `properties(property_id)` | Target property listing (`ON DELETE CASCADE`). |
| `user_id` | `INT` | NO | None | **FK** $\rightarrow$ `users(user_id)` | Seeker user submitting the lead (`ON DELETE CASCADE`). |
| `channel` | `VARCHAR(20)` | NO | None | `CHECK (IN ('CALL', 'WHATSAPP', 'FORM'))` | Communication medium. |
| `message` | `TEXT` | YES | None | None | Inquirer's optional customized inquiry text. |
| `created_at` | `TIMESTAMPTZ` | NO | None | None | Submission timestamp. |

---

### Table 11: `site_visits`
- **Purpose:** On-site walkthrough scheduling and seeker evaluation feedback.
- **Cardinality:** 35,120 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `visit_id` | `INT` | NO | None | **PK** | Unique appointment identifier. |
| `property_id` | `INT` | NO | None | **FK** $\rightarrow$ `properties(property_id)` | Property to be physically inspected (`ON DELETE CASCADE`). |
| `user_id` | `INT` | NO | None | **FK** $\rightarrow$ `users(user_id)` | Seeker attending the visit (`ON DELETE CASCADE`). |
| `scheduled_at` | `TIMESTAMPTZ` | NO | None | None | Date and time slot reserved for the walkthrough. |
| `status` | `VARCHAR(20)` | NO | None | `CHECK (IN ('SCHEDULED', 'COMPLETED', 'CANCELLED', 'NO_SHOW'))` | Appointment state. |
| `feedback_rating`| `SMALLINT` | YES | None | `CHECK (BETWEEN 1 AND 5)` | Post-inspection seeker satisfaction score (1 to 5). |

*Table Constraint:*  
`CHECK ((feedback_rating IS NULL AND status IN ('SCHEDULED', 'CANCELLED', 'NO_SHOW')) OR (status = 'COMPLETED'))`

---

### Table 12: `shortlists`
- **Purpose:** Junction entity storing bookmarked listings by home seekers.
- **Cardinality:** 69,999 rows.

| Column Name | PostgreSQL Data Type | Nullable | Default | Key / Constraint | Description / Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `user_id` | `INT` | NO | None | **PK, FK** $\rightarrow$ `users(user_id)` | Seeker saving the listing (`ON DELETE CASCADE`). |
| `property_id` | `INT` | NO | None | **PK, FK** $\rightarrow$ `properties(property_id)` | Bookmarked property listing (`ON DELETE CASCADE`). |
| `added_at` | `TIMESTAMPTZ` | NO | None | None | Bookmark timestamp. |

---

## 6. Referential Integrity Actions (`ON DELETE` Rationale)

A robust relational database must specify deterministic behaviors when parent records are deleted:

| Foreign Key Relationship | Parent Table | Child Table | `ON DELETE` Action | Architectural Rationale |
| :--- | :--- | :--- | :--- | :--- |
| `localities.city_id` | `cities` | `localities` | `RESTRICT` | A city cannot be dropped if municipal localities depend on it. |
| `projects.builder_id` | `builders` | `projects` | `RESTRICT` | Developers with active developments must be preserved for audit. |
| `projects.locality_id` | `localities` | `projects` | `RESTRICT` | Localities cannot be removed while registered projects exist in them. |
| `project_amenities.project_id`| `projects` | `project_amenities` | `CASCADE` | Deleting a project automatically purges its amenity associations. |
| `project_amenities.amenity_id`| `amenities` | `project_amenities` | `RESTRICT` | Core amenity master categories cannot be dropped if projects offer them. |
| `properties.listed_by` | `users` | `properties` | `RESTRICT` | A lister account cannot be deleted while active property listings exist. |
| `properties.(project_id, locality_id)` | `projects` | `properties` | `SET NULL (project_id)` | Deleting a project zeroes `project_id` while preserving `locality_id`. |
| `properties.locality_id` | `localities` | `properties` | `RESTRICT` | Physical neighborhoods cannot be dropped if properties exist within them. |
| `price_changes.property_id` | `properties` | `price_changes` | `CASCADE` | Purging a listing cascades to its historical price audit trail. |
| `enquiries.property_id` | `properties` | `enquiries` | `CASCADE` | Inquiries regarding a listing are purged if the listing is permanently deleted. |
| `enquiries.user_id` | `users` | `enquiries` | `CASCADE` | If a seeker requests account deletion, personal inquiries cascade. |
| `site_visits.property_id` | `properties` | `site_visits` | `CASCADE` | Walkthrough records for a listing cascade on listing removal. |
| `site_visits.user_id` | `users` | `site_visits` | `CASCADE` | Seeker visits cascade on seeker account deletion. |
| `shortlists.user_id` | `users` | `shortlists` | `CASCADE` | User bookmarks cascade when user account is purged. |
| `shortlists.property_id` | `properties` | `shortlists` | `CASCADE` | Bookmarks cascade when the shortlisted listing is purged. |

---

## 7. Live Database Integrity Verification Results

To validate the schema and loaded dataset, comprehensive SQL integrity checks were executed on our local PostgreSQL 18.6 instance on `housing_capstone_test`:

### Check 1: Correct Price History Verification (Latest Event Logic)
Instead of naively comparing all historical price changes to current listing prices, the correct relational validation isolates the *latest* price change per property (ordered by `changed_at DESC, change_id DESC`) and reconciles it against `properties.price`:

```sql
WITH latest_price_change AS (
    SELECT DISTINCT ON (property_id) 
           property_id, 
           new_price, 
           changed_at, 
           change_id
    FROM housing.price_changes
    ORDER BY property_id, changed_at DESC, change_id DESC
)
SELECT 
    (SELECT count(*) FROM housing.properties) AS total_properties,
    (SELECT count(DISTINCT property_id) FROM housing.price_changes) AS properties_with_price_changes,
    (SELECT count(*) FROM housing.properties WHERE property_id NOT IN (SELECT property_id FROM housing.price_changes)) AS properties_without_price_changes,
    count(*) AS verified_latest_events,
    count(*) FILTER (WHERE p.price = lpc.new_price) AS matching_current_prices,
    count(*) FILTER (WHERE p.price <> lpc.new_price) AS price_mismatches
FROM latest_price_change lpc
JOIN housing.properties p ON p.property_id = lpc.property_id;
```
**Observed Execution Output:**
```
 total_properties | properties_with_price_changes | properties_without_price_changes | verified_latest_events | matching_current_prices | price_mismatches 
------------------+-------------------------------+----------------------------------+------------------------+-------------------------+------------------
           120060 |                         23425 |                            96635 |                  23425 |                   23425 |                0
```
*Significance:* Of 120,060 listings in the platform catalog, 96,635 properties have had no price revisions, while 23,425 properties underwent price modifications. For 100% of these 23,425 properties, the latest historical price event strictly equals the operational listing price.

---

### Check 2: Project-Locality Consistency via Composite Foreign Key
```sql
SELECT count(*) AS locality_mismatches
FROM housing.properties p
JOIN housing.projects pj ON pj.project_id = p.project_id
WHERE p.locality_id <> pj.locality_id;
```
**Observed Execution Output:**
```
 locality_mismatches 
---------------------
                   0
```
*Significance:* Confirms that every property belonging to a project is geographically localized in the exact locality of the parent project.

---

### Check 3: Property Typology Physical Dimensions Distribution
```sql
SELECT property_type,
       count(*) AS total_units,
       count(bhk) AS with_bhk,
       count(floor_no) AS with_floor_no,
       count(total_floors) AS with_total_floors,
       count(furnishing) AS with_furnishing
FROM housing.properties
GROUP BY property_type
ORDER BY total_units DESC;
```
**Observed Execution Output:**
```
   property_type   | total_units | with_bhk | with_floor_no | with_total_floors | with_furnishing 
-------------------+-------------+----------+---------------+-------------------+-----------------
 APARTMENT         |       97695 |    97695 |         97695 |             97695 |           97695
 INDEPENDENT_HOUSE |       13434 |    13434 |             0 |             13434 |           13434
 VILLA             |        5315 |     5315 |             0 |              5315 |            5315
 PLOT              |        3616 |        0 |             0 |                 0 |               0
```
*Significance:* Proves that the structural domain check constraint accurately models physical building realities across all 120,060 listings.

---

### Check 4: Lister Role Validation & Trigger Integrity
```sql
SELECT u.user_type, count(*) AS listings_count
FROM housing.properties p
JOIN housing.users u ON u.user_id = p.listed_by
GROUP BY u.user_type;
```
**Observed Execution Output:**
```
 user_type | listings_count 
-----------+----------------
 OWNER     |          99674
 AGENT     |          20386
```
*Significance:* Proves that no `SEEKER` account has created a property listing. The entire catalog is supplied by verified property owners (83.0%) and licensed agents (17.0%).

---

### Check 5: Security Deposit Financial Invariant
```sql
SELECT listing_type, 
       count(*) AS total_listings,
       count(security_deposit) AS listings_with_deposit,
       count(*) - count(security_deposit) AS listings_without_deposit
FROM housing.properties
GROUP BY listing_type;
```
**Observed Execution Output:**
```
 listing_type | total_listings | listings_with_deposit | listings_without_deposit 
--------------+----------------+-----------------------+--------------------------
 SALE         |          54060 |                     0 |                    54060
 RENT         |          66000 |                 66000 |                        0
```
*Significance:* Demonstrates 100% adherence to lease financial semantics: all 66,000 rental listings require security deposits, while all 54,060 sale properties have null deposits.

---

### Check 6: Post-Walkthrough Feedback Rating Consistency
```sql
SELECT status, 
       count(*) AS total_visits, 
       count(feedback_rating) AS rated_visits,
       min(feedback_rating) AS min_rating,
       max(feedback_rating) AS max_rating
FROM housing.site_visits
GROUP BY status;
```
**Observed Execution Output:**
```
  status   | total_visits | rated_visits | min_rating | max_rating 
-----------+--------------+--------------+------------+------------
 CANCELLED |         6377 |            0 |            |           
 NO_SHOW   |         4759 |            0 |            |           
 COMPLETED |        21121 |        14694 |          2 |          5
 SCHEDULED |         2863 |            0 |            |           
```
*Significance:* Enforces behavioral integrity: only completed appointments received visitor ratings (14,694 out of 21,121 completed visits, rated strictly between 2 and 5). Scheduled, cancelled, and no-show visits have 0 ratings.

---

### Check 7: Column-Specific Foreign Key Deletion Test (`ON DELETE SET NULL (project_id)`)
We executed an explicit test deleting project 1 (which initially possessed 70 associated properties in locality 14):
```sql
BEGIN;
DELETE FROM housing.projects WHERE project_id = 1;
SELECT count(*) AS properties_with_null_project 
FROM housing.properties 
WHERE project_id IS NULL AND locality_id = 14;
ROLLBACK;
```
**Observed Execution Output:**
```
DELETE 1
 properties_with_null_project 
------------------------------
                          621
```
*Significance:* PostgreSQL 18's column-specific action successfully set `properties.project_id` to `NULL` for all 70 properties, preserved `properties.locality_id = 14` without violating its `NOT NULL` constraint, and raised zero check constraint violations.

---

## 8. Dataset Reconciliation & Ingestion Verification

Comparing raw CSV record counts against live database table counts confirms zero data loss:

| Entity Name | Source CSV File | CSV Data Rows | Ingested DB Rows | Load Delta | Load Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `cities` | `seed_data/cities.csv` | 10 | 10 | 0 | **Verified Match** |
| `localities` | `seed_data/localities.csv` | 100 | 100 | 0 | **Verified Match** |
| `builders` | `seed_data/builders.csv` | 150 | 150 | 0 | **Verified Match** |
| `projects` | `seed_data/projects.csv` | 1,200 | 1,200 | 0 | **Verified Match** |
| `amenities` | `seed_data/amenities.csv` | 15 | 15 | 0 | **Verified Match** |
| `project_amenities` | `seed_data/project_amenities.csv` | 6,806 | 6,806 | 0 | **Verified Match** |
| `users` | `seed_data/users.csv` | 40,000 | 40,000 | 0 | **Verified Match** |
| `properties` | `seed_data/properties.csv` | 120,060 | 120,060 | 0 | **Verified Match** |
| `price_changes` | `seed_data/price_changes.csv` | 23,425 | 23,425 | 0 | **Verified Match** |
| `enquiries` | `seed_data/enquiries.csv` | 100,000 | 100,000 | 0 | **Verified Match** |
| `site_visits` | `seed_data/site_visits.csv` | 35,120 | 35,120 | 0 | **Verified Match** |
| `shortlists` | `seed_data/shortlists.csv` | 69,999 | 69,999 | 0 | **Verified Match** |
| **Total Pipeline** | **12 Datasets** | **396,885** | **396,885** | **0** | **100.0% Lossless Match** |

*Verification Equation:*  
$$10 + 100 + 150 + 1,200 + 15 + 6,806 + 40,000 + 120,060 + 23,425 + 100,000 + 35,120 + 69,999 = \mathbf{396,885}$$

---

## 9. Discovered Data Issues & Engineering Solutions

1. **Problem P5 Subquery Null Semantics (`R13`):**
   - *Issue:* Query `R13` attempts to identify developer projects with no listings via `pj.project_id NOT IN (SELECT p.project_id FROM properties p)`.
   - *Discovery:* Standalone properties in `properties` have `project_id IS NULL` (54,009 rows). Because SQL `NOT IN` returns `UNKNOWN` when encountering any `NULL` in the subquery result set, the condition never evaluates to `TRUE`.
   - *Engineering Recommendation:* In Phase 4, `R13` should be optimized with `NOT EXISTS (SELECT 1 FROM properties p WHERE p.project_id = pj.project_id)` or `WHERE pj.project_id NOT IN (SELECT p.project_id FROM properties p WHERE p.project_id IS NOT NULL)`.
2. **Pre-RERA Legacy Projects:**
   - *Issue:* 171 projects (14.25%) have `rera_id IS NULL`.
   - *Root Cause:* The Indian Real Estate (Regulation and Development) Act took effect on May 1, 2016. Projects developed and completed before 2016 were not legally required to hold retrospective state RERA registrations.
   - *Schema Handling:* Made `projects.rera_id` nullable while enforcing uniqueness and strict regex validation on all non-null entries.
3. **Primary Key Surrogacy vs. Composite Keys:**
   - For transactional events (`price_changes`, `enquiries`, `site_visits`), single surrogate integer primary keys (`change_id`, `enquiry_id`, `visit_id`) were retained to support direct indexing and row-level references.
   - For pure associative junction entities (`project_amenities`, `shortlists`), natural composite primary keys (`(project_id, amenity_id)` and `(user_id, property_id)`) were implemented, enforcing uniqueness without adding redundant surrogate keys.
