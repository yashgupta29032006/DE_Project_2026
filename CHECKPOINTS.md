# Checkpoints: Housing.com Property Search Database

**Final submission: Monday 23 November 2026, 11:59 PM.** **Individual analysis (CP5): Wed 25 and Thu 26 November 2026, in class time.** Evaluation runs 25 Nov – 2 Dec 2026.

Progress is checked automatically from GitHub every few hours. A checkpoint counts as done when its files
exist in your repository **on the default branch**, with real content, by the due date. Every member must
have commits; the tracker shows commit counts per author.

## Your two repositories

| Repo | What goes in it | Where it lives |
|------|-----------------|----------------|
| **DE repo** | This project, cloned from `edusatyaki/DBMS-Housing-Property-Search` and done phase by phase (`README.md`) | The DE repo your team already submitted in the form (usually `DE_Project_2026`) |
| **AP repo** | Normalization, ER diagram, tables and query timings for the app you are building in AP | The `*_AP_2026` repo your team already submitted |

### Set up the DE repo (CP0)
Clone this project and push it into **your team's own DE repo** (the DE repo link your team submitted in the
form, usually named `DE_Project_2026`). The tracker reads that repo, so do not create a new one, and do not fork.

```bash
git clone https://github.com/edusatyaki/DBMS-Housing-Property-Search.git
cd DBMS-Housing-Property-Search
git remote rename origin project
git remote add origin <your team's DE repo URL from the form>
git push -u origin main
```

If the push is rejected because your DE repo already has a README or other commits, run
`git pull origin main --allow-unrelated-histories`, keep both sets of files, commit, and push again.

Then:
1. Add the other members as collaborators on your DE repo (Settings → Collaborators). Every member must commit.
2. Commit `team.json` (format in `README.md`, *Repository structure*) and fill the team table in `README.md`.
3. Unzip `seed_data.zip` locally and never commit the CSV files (`.gitignore` already excludes them).
4. If faculty update this project repo, get the changes with `git pull project main`.

## Checkpoint dates

| # | Due | Checkpoint | DE repo must contain | AP repo must contain |
|---|-----|------------|----------------------------------|----------------------|
| **CP0** | Tue 3 Nov 2026 | Setup | `queries/workload_30.sql`<br>`benchmarks/run_benchmark.sh`<br>`team.json` | — |
| **CP1** | Mon 16 Nov 2026 | Schema & normalization | `docs/01_problem_understanding.md`<br>`docs/02_schema_design.md`<br>`sql/01_schema.sql`<br>`sql/02_load_data.sql`<br>`diagrams/er_diagram.*` | `dbms/01_normalization.md` |
| **CP2** | Tue 17 Nov 2026 | Baseline timings | `docs/03_baseline_timings.md`<br>`benchmarks/results/baseline/summary.csv` | `dbms/02_er_diagram.*`<br>`dbms/03_schema.sql` |
| **CP3** | Thu 19 Nov 2026 | Optimization | `sql/05_indexes.sql`<br>`sql/06_optimized_queries.sql`<br>`docs/04_optimization_report.md`<br>`benchmarks/results/optimized/summary.csv` | `dbms/04_queries.sql` |
| **CP4** | Mon 23 Nov 2026 | Final submission | `docs/05_scalability_report.md`<br>`sql/08_partitioning.sql`<br>`benchmarks/results/large/summary.csv` | `dbms/05_query_timings.md`<br>`dbms/plans/` |
| **CP5** | Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | — | — |

`*` means any image or PDF (`.png`, `.jpg`, `.svg`, `.pdf`). A folder entry means at least one file inside it.

## How to time queries (both repos)

- Run every query with `EXPLAIN (ANALYZE, BUFFERS)` in PostgreSQL and read the `Execution Time` line.
- Run each query **3 times** and report the **average** of the three times.
- Run write queries inside `BEGIN; … ROLLBACK;` so the data does not change.
- In the DE repo, `./benchmarks/run_benchmark.sh <database> baseline` does this for you and writes
  `summary.csv` with `avg_ms` for every query, plus the raw plans of all 3 runs.

## AP repo: what to submit (folder `dbms/`)

| File | Content |
|------|---------|
| `dbms/01_normalization.md` | The data of your AP app taken through **1NF → 2NF → 3NF**, and **BCNF** where possible (BCNF is optional). Show the tables and the functional dependencies at each step. |
| `dbms/02_er_diagram.png` | ER diagram: entities, attributes, primary and foreign keys, cardinality. |
| `dbms/03_schema.sql` | `CREATE TABLE` statements for the final tables, with keys and constraints. It must run on PostgreSQL. |
| `dbms/04_queries.sql` | Every SQL query your app uses, using JOINs where possible. Mark each one `-- READ` or `-- WRITE` and give it an id (`R1`, `R2`, … `W1`, …). |
| `dbms/05_query_timings.md` | The timing table below, one row per query. |
| `dbms/plans/` | The `EXPLAIN (ANALYZE, BUFFERS)` output of each run, one file per query. |

Timing table format for `dbms/05_query_timings.md`:

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|-----------|
| R1 | READ | Login by email | | | | | Index Scan |
| W1 | WRITE | Create order | | | | | — |

## Marks (evaluation matrix, 100)

| Category | Criteria | Marks |
|----------|----------|------:|
| AP Projects | Normalization 5 · ER diagram 5 · All SQL queries used 5 · Query analysis 5 | 20 |
| DE Projects | Query execution 10 · Code optimization 30 · Individual analysis 40 | 80 |

---

## Team 19 (EchoVault) Checkpoint Completion & Audit Matrix

**Team No.:** 19 · **Section:** C · **Institution:** Rishihood University  
**Target RDBMS:** PostgreSQL 18.6 (Homebrew / Apple Silicon M4)  
**Database Schemas:** `housing` (Seed ~396k rows & Large ~7.93M rows), `housing_partitioned` (Large Range-Partitioned)  
**Default Branch Status:** Default branch `main` verified and all deliverables present.

### Checkpoint Deliverables Status

| Checkpoint | Due Date | Status | Required Deliverables | Repository Paths Verified | Key Evidence / Highlights |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **CP0** | Tue 3 Nov 2026 | **COMPLETED** | `queries/workload_30.sql`<br>`benchmarks/run_benchmark.sh`<br>`team.json` | [`queries/workload_30.sql`](queries/workload_30.sql)<br>[`benchmarks/run_benchmark.sh`](benchmarks/run_benchmark.sh)<br>[`team.json`](team.json) | Team details configured (`T0039`), benchmarking harness verified. |
| **CP1** | Mon 16 Nov 2026 | **COMPLETED** | `docs/01_problem_understanding.md`<br>`docs/02_schema_design.md`<br>`sql/01_schema.sql`<br>`sql/02_load_data.sql`<br>`diagrams/er_diagram.*` | [`docs/01_problem_understanding.md`](docs/01_problem_understanding.md)<br>[`docs/02_schema_design.md`](docs/02_schema_design.md)<br>[`sql/01_schema.sql`](sql/01_schema.sql)<br>[`sql/02_load_data.sql`](sql/02_load_data.sql)<br>[`diagrams/er_diagram.svg`](diagrams/er_diagram.svg)<br>[`diagrams/er_diagram.mmd`](diagrams/er_diagram.mmd) | 12 tables in 3NF, composite FKs, domain CHECK constraints, 396,885 seed records loaded cleanly with zero errors. |
| **CP2** | Tue 17 Nov 2026 | **COMPLETED** | `docs/03_baseline_timings.md`<br>`benchmarks/results/baseline/summary.csv` | [`docs/03_baseline_timings.md`](docs/03_baseline_timings.md)<br>[`benchmarks/results/baseline/summary.csv`](benchmarks/results/baseline/summary.csv)<br>[`benchmarks/results/baseline/`](benchmarks/results/baseline/) | Total baseline latency: **18,112.713 ms**. Outlier `R19` clocked at **16,875.315 ms** due to $O(N \cdot M)$ correlated subqueries. |
| **CP3** | Thu 19 Nov 2026 | **COMPLETED** | `sql/05_indexes.sql`<br>`sql/06_optimized_queries.sql`<br>`docs/04_optimization_report.md`<br>`benchmarks/results/optimized/summary.csv` | [`sql/05_indexes.sql`](sql/05_indexes.sql)<br>[`sql/06_optimized_queries.sql`](sql/06_optimized_queries.sql)<br>[`docs/04_optimization_report.md`](docs/04_optimization_report.md)<br>[`benchmarks/results/optimized/summary.csv`](benchmarks/results/optimized/summary.csv)<br>[`benchmarks/results/optimized/`](benchmarks/results/optimized/) | Workload latency reduced from **18,112 ms to 640 ms** (**96.47% reduction, 28.3× speedup**). `R19` reduced from **16,875 ms to 27.4 ms** (614.9× speedup). Fixed ANSI 3-valued logic bug in `R13`. 20 secondary indexes (36.3 MB) created and analyzed. |
| **CP4** | Mon 23 Nov 2026 | **COMPLETED** | `docs/05_scalability_report.md`<br>`sql/08_partitioning.sql`<br>`benchmarks/results/large/summary.csv` | [`docs/05_scalability_report.md`](docs/05_scalability_report.md)<br>[`sql/02_load_large_data.sql`](sql/02_load_large_data.sql)<br>[`sql/08_partitioning.sql`](sql/08_partitioning.sql)<br>[`benchmarks/results/large/summary.csv`](benchmarks/results/large/summary.csv)<br>[`benchmarks/results/large/partitioned/summary.csv`](benchmarks/results/large/partitioned/summary.csv)<br>[`benchmarks/results/large/`](benchmarks/results/large/) | Ingested **7,930,894** rows (20× scale) with `BIGINT` safety. Executed declarative range partitioning by `RANGE (posted_at)` (7 quarterly partitions + default). Demonstrated partition pruning; reduced `W04` from **17,876 ms to 8,565 ms** (52.1% speedup). 100× enterprise architecture documented. |
| **CP5** | Wed 25 – Thu 26 Nov 2026 | **READY** | Individual oral analysis defense | All architectural documentation, execution plans, and query proofs prepared for in-class defense. | Defense scripts, index selection rationales, subquery unnesting mathematical proofs, and partitioning trade-offs ready. |
