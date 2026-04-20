-- Runtime monitoring queries for ETL (incremental and maintenance).
-- Connect to the DWH database (e.g. psql -d notes_dwh -U notes -f etl_runtime_queries.sql).
--
-- When ingestion and analytics use separate databases, public.notes / public.note_comments
-- in the DWH are foreign tables pointing at the ingestion DB (same as the ETL).

-- 1) Data freshness: last action day in DWH vs last comment day at source, and calendar gap.
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

-- 2) Is the ETL doing work right now? (typical incremental bottleneck: CALL process_notes_actions_into_dwh)
-- Default PGAPPNAME for bin/dwh/ETL.sh is "ETL" (script basename).
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

-- 3) Broader view: guess phase (facts, post-facts batches, maintenance, parallel initial, datamarts).
-- Datamarts run inside a full ETL.sh incremental run after __processNotesETL (see bin/dwh/ETL.sh).
SELECT
  pid,
  application_name,
  clock_timestamp() - query_start AS duration,
  state,
  wait_event_type,
  wait_event,
  CASE
    WHEN application_name = 'datamartCountries' THEN 'datamart: countries (main script)'
    WHEN application_name = 'datamartUsers' THEN 'datamart: users (main script)'
    WHEN application_name = 'datamartGlobal' THEN 'datamart: global (main script)'
    WHEN application_name LIKE 'datamartCountries-%' THEN 'datamart: countries (worker)'
    WHEN application_name LIKE 'datamartUsers-%' THEN 'datamart: users (worker)'
    WHEN query ~* 'process_notes_actions_into_dwh' THEN 'facts: process_notes_actions_into_dwh'
    WHEN query ~* 'process_notes_at_date' THEN 'facts: process_notes_at_date (inner)'
    WHEN query ~* 'update_automation_levels_for_modified_users' THEN 'post-facts: automation levels (batch)'
    WHEN query ~* 'update_experience_levels_for_modified_users' THEN 'post-facts: experience levels (batch)'
    WHEN query ~* 'VACUUM\s+ANALYZE' AND query ~* 'facts' THEN 'maintenance: VACUUM ANALYZE dwh.facts'
    WHEN query ~* 'ANALYZE' AND query ~* 'dimension_' THEN 'maintenance: ANALYZE dimension tables'
    WHEN application_name ~ '^ETL-year-' THEN 'parallel: initial load by year'
    WHEN application_name = 'ETL' AND query !~* 'process_notes|update_' THEN 'ETL: other SQL (unify, DDL, -f temp, … — check preview)'
    ELSE 'unknown / other'
  END AS estimated_phase,
  LEFT(query, 160) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state = 'active'
  AND (
    application_name = 'ETL'
    OR application_name LIKE 'ETL-year-%'
    OR application_name IN ('datamartUsers', 'datamartCountries', 'datamartGlobal')
    OR application_name LIKE 'datamartUsers-%'
    OR application_name LIKE 'datamartCountries-%'
    OR query ~* 'CALL\s+staging\.process_notes|CALL\s+dwh\.update_(automation|experience)'
  );

-- 4) Datamart-only view (less noise if you only care about datamart generation).
SELECT
  pid,
  application_name,
  clock_timestamp() - query_start AS duration,
  state,
  LEFT(query, 120) AS query_preview
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state = 'active'
  AND (
    application_name IN ('datamartUsers', 'datamartCountries', 'datamartGlobal')
    OR application_name LIKE 'datamartUsers-%'
    OR application_name LIKE 'datamartCountries-%'
  );

-- 5) ETL metadata flags (not step-specific; useful for context).
SELECT key, value
FROM dwh.properties
ORDER BY key;
