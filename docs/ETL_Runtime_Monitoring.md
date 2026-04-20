---
title: "ETL Runtime Monitoring"
description:
  "SQL queries and patterns to observe ETL progress, long-running phases, and data freshness versus
  ingestion."
version: "1.0.0"
last_updated: "2026-04-14"
author: "AngocA"
tags:
  - "operations"
  - "etl"
  - "postgresql"
audience:
  - "system-admins"
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# ETL Runtime Monitoring

This document complements [Execution_Guide.md](Execution_Guide.md) (log tail) and
[Troubleshooting_Guide.md](Troubleshooting_Guide.md) (`pg_stat_activity` by `application_name`). It
focuses on **SQL you can run while `bin/dwh/ETL.sh` is executing**: how far the DWH is behind the
ingestion database, whether the database is busy on the slow steps, and how to map
`pg_stat_activity.query` to an approximate **phase**.

All queries assume a session on **`DBNAME_DWH`** (e.g. `notes_dwh`).

## Coverage vs a full `ETL.sh` run

**Not every orchestration step has a stable `pg_stat_activity` signature.** Short DDL checks, `-f`
on a temp file (often shown as a path under `/tmp/`), and some `psql` calls appear generically as
`application_name = ETL` with little detail in `query`. For those, use **`ETL.log`** (see §5).

What **is** covered well:

| Block (incremental path, typical order in `bin/dwh/ETL.sh`)                                                         | Observable via                                                         |
| ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| FDW + staging load + triggers + many SQL files in `__processNotesETL`                                               | Often `ETL` + `query` preview, or log                                  |
| **`CALL staging.process_notes_actions_into_dwh()`** (usually slowest)                                               | §2, §3 (`process_notes_…`)                                             |
| Inner **`process_notes_at_date`**                                                                                   | §3                                                                     |
| Unify facts (`Staging_50_unify.sql`), hashtag SQL, other `-f` steps                                                 | Often **§3** as `ETL: other SQL` — inspect preview / log               |
| Automation / experience **batched `CALL`s**                                                                         | §3                                                                     |
| **`VACUUM ANALYZE dwh.facts`** / **`ANALYZE`** dimensions (`__perform_database_maintenance`)                        | §3 (if enabled via `ETL_VACUUM_AFTER_LOAD` / `ETL_ANALYZE_AFTER_LOAD`) |
| **Datamarts:** `datamartCountries.sh`, `datamartUsers.sh`, `datamartGlobal.sh` (also invoked after incremental ETL) | §3 (`datamart*` names), **§4** (datamart-only list)                    |
| Parallel **initial** load by year                                                                                   | `application_name` `ETL-year-*` (§3)                                   |
| ETL report / integrity scripts at end                                                                               | Usually quick; log                                                     |

So: **yes, datamart generation is included** when you use §3 or §4 (`PGAPPNAME` defaults to each
script basename, e.g. `datamartCountries`). **No**, the doc does not map **every** sub-step inside
each datamart procedure to a unique label—only session-level activity.

## Runnable script

The same queries are collected in:

`sql/monitoring/etl_runtime_queries.sql`

Example:

```bash
psql -d notes_dwh -U notes -f sql/monitoring/etl_runtime_queries.sql
```

## 1. Freshness vs source (calendar days behind)

When ingestion and analytics use **separate databases**, `public.note_comments` (and related tables)
on the DWH are **foreign tables** to the ingestion DB—the same objects the ETL reads.

```sql
SELECT
  dwh.last_day AS last_day_in_dwh,
  src.last_day AS last_day_at_source,
  CASE
    WHEN dwh.last_day IS NULL THEN NULL
    WHEN src.last_day IS NULL THEN NULL
    ELSE GREATEST(0, (src.last_day - dwh.last_day))
  END AS calendar_days_behind
FROM (
  SELECT MAX(d.date_id) AS last_day
  FROM dwh.facts f
  JOIN dwh.dimension_days d ON d.dimension_day_id = f.action_dimension_id_date
) AS dwh,
(
  SELECT MAX((nc.created_at AT TIME ZONE 'UTC')::date) AS last_day
  FROM public.note_comments nc
) AS src;
```

**Interpretation:**

- `calendar_days_behind` is a **calendar-day gap** between the latest comment date at source and
  the latest fact date in the DWH (not “wall-clock ETA”).
- While `CALL staging.process_notes_actions_into_dwh()` is running a large catch-up, this gap should
  **trend down** after each successful run (or toward zero on a steady incremental).

**Caveats:**

- Fact rows are not 1:1 with `note_comments`; the gap is a **coarse** progress signal.
- Time zones: `created_at` is interpreted as **UTC** for the date boundary; adjust if your pipeline
  uses a different convention.

## 2. Is the incremental facts step running?

`ETL.sh` sets `PGAPPNAME` to **`ETL`** (script basename) for most `psql` invocations. The longest
incremental phase is usually:

`CALL staging.process_notes_actions_into_dwh();`

```sql
SELECT
  pid,
  application_name,
  clock_timestamp() - query_start AS duration,
  state,
  wait_event_type,
  wait_event,
  query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state = 'active'
  AND query ~* 'process_notes_actions_into_dwh';
```

If this returns **no rows**, the ETL is either in another step, between statements, or not running.

## 3. Map activity to an approximate phase (slow steps)

There is **no first-class “current ETL step” table** inside PostgreSQL for every sub-step; fine
grained progress is mostly **`RAISE NOTICE`** messages in `ETL.log`. For a **session-level** view,
inspect `query` and `application_name`:

| Pattern                                                                     | Typical phase                           | Notes                                         |
| --------------------------------------------------------------------------- | --------------------------------------- | --------------------------------------------- |
| `process_notes_actions_into_dwh`                                            | Incremental / main facts load           | Often **dominates** runtime                   |
| `process_notes_at_date`                                                     | Inner loop of facts load                | Nested `CALL`                                 |
| `application_name` like `ETL-year-%`                                        | Parallel **initial** load by year       | See `ETL.sh` / staging SQL                    |
| `update_automation_levels_for_modified_users`                               | Post-facts automation batches           | Batched `CALL`                                |
| `update_experience_levels_for_modified_users`                               | Post-facts experience batches           | Batched `CALL`                                |
| `VACUUM ANALYZE` on `dwh.facts`                                             | Post-ETL maintenance (optional)         | `ETL_VACUUM_AFTER_LOAD`                       |
| `ANALYZE` … `dimension_`                                                    | Post-ETL maintenance (optional)         | `ETL_ANALYZE_AFTER_LOAD`                      |
| `application_name` `datamartCountries` / `datamartUsers` / `datamartGlobal` | Datamart **generation** (shell scripts) | After `__processNotesETL` in incremental flow |
| `application_name` like `datamartUsers-%`                                   | Datamart **worker** sessions            | Parallel user processing                      |

Example “guess” query: see **query 3** in `sql/monitoring/etl_runtime_queries.sql` (includes
datamart `application_name` branches and maintenance `ANALYZE`).

**Orchestration reference:** incremental facts and related SQL live in `__processNotesETL`; datamart
scripts run **after** that (and after optional `__perform_database_maintenance`) in the same
`ETL.sh` invocation—see `bin/dwh/ETL.sh` around “Executing datamart scripts…”.

## 4. Datamart-only activity

Query **4** in `sql/monitoring/etl_runtime_queries.sql` lists only `datamart*` sessions (main + `%`
workers). Use it when the ETL is in the datamart phase and you want less noise than query 3.

## 5. Logs and metadata

- **Session detail:** `tail -f` the newest `ETL.log` under `/tmp/ETL_*` (see header comment in
  `bin/dwh/ETL.sh`).
- **Flags:** `SELECT * FROM dwh.properties;` (e.g. `initial load`, other keys used by scripts).

## Future improvement (optional)

To persist per-step progress in SQL (e.g. last processed date or row counts), the project would need
small changes inside `staging.process_notes_actions_into_dwh` (or helpers) to `INSERT`/`UPDATE` a
monitoring table or `dwh.properties` keys; that is **not** implemented today.
