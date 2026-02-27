-- Validate resolution_by_year and resolution_by_month columns are populated
-- and JSON structure contains expected keys.
-- Run against your DWH database, e.g.:
--   psql -d your_db -f tests/sql/validate_resolution_temporal_metrics.sql

\echo '=== 1. Sample: resolution_by_year / resolution_by_month populated (Countries) ==='
SELECT dimension_country_id,
       (resolution_by_year IS NOT NULL) AS has_year,
       (resolution_by_month IS NOT NULL) AS has_month
FROM dwh.datamartCountries
ORDER BY dimension_country_id
LIMIT 5;

\echo ''
\echo '=== 2. Sample: resolution_by_year / resolution_by_month populated (Users) ==='
SELECT dimension_user_id,
       (resolution_by_year IS NOT NULL) AS has_year,
       (resolution_by_month IS NOT NULL) AS has_month
FROM dwh.datamartUsers
ORDER BY dimension_user_id
LIMIT 5;

-- Check that not all resolution_rate values are 0 (validates fix for "all zeros" bug)
\echo ''
\echo '=== 3. Users with at least one non-zero resolution_rate in resolution_by_year ==='
SELECT COUNT(*) AS users_with_nonzero_resolution_rate
FROM dwh.datamartUsers du
WHERE du.resolution_by_year IS NOT NULL
  AND EXISTS (
    SELECT elem
    FROM jsonb_array_elements(du.resolution_by_year::jsonb) AS elem  -- noqa: L025
    WHERE (elem ->> 'resolution_rate')::numeric > 0
  );

\echo ''
\echo '=== 4. Users with resolution_by_year all zeros (potential issue if they have closed notes) ==='
SELECT du.dimension_user_id,
       du.user_id,
       du.username,
       jsonb_array_length(du.resolution_by_year::jsonb) AS years_count
FROM dwh.datamartUsers du
WHERE du.resolution_by_year IS NOT NULL
  AND jsonb_array_length(du.resolution_by_year::jsonb) > 0
  AND NOT EXISTS (
    SELECT elem
    FROM jsonb_array_elements(du.resolution_by_year::jsonb) AS elem  -- noqa: L025
    WHERE (elem ->> 'resolution_rate')::numeric > 0
  )
ORDER BY du.dimension_user_id
LIMIT 10;

-- Inspect one JSON entry example (replace :country_id)
\echo ''
\echo '=== 5. Example: one resolution_by_year (uncomment and set dimension_country_id) ==='
-- SELECT jsonb_pretty(resolution_by_year::jsonb)
-- FROM dwh.datamartCountries WHERE dimension_country_id = 1;
