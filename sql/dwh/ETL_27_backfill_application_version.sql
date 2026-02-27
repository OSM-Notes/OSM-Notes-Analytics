-- Backfill dwh.facts.dimension_application_version from opening comment body
-- when the fact has an application but version was never set (e.g. ETL path did not set it).
--
-- Prerequisites:
--   - public.note_comments_text exists (local or FDW) and has the opening comment body
--   - dwh.get_application_version_id exists
--   - Run diagnose_version_adoption_rates.sql first; if "open_with_app_whose_body_has_version_pattern" > 0, run this script
--
-- After running: refresh datamart users/countries so version_adoption_rates gets populated.
-- Usage: psql -d your_dwh -f sql/dwh/ETL_27_backfill_application_version.sql

BEGIN;

-- Update facts that have app, no version, and whose opening comment body matches N.N or N.N.N
WITH to_update AS (
  SELECT f.fact_id,
         dwh.get_application_version_id(
           f.dimension_application_creation,
           (SELECT (regexp_match(t.body, '(\d+\.\d+(?:\.\d+)?)')) [1])
         ) AS new_version_id
  FROM dwh.facts f
  JOIN public.note_comments_text t
    ON t.note_id = f.id_note AND t.sequence_action = f.sequence_action
  WHERE f.action_comment = 'opened'
    AND f.dimension_application_creation IS NOT NULL
    AND f.dimension_application_version IS NULL
    AND t.body IS NOT NULL
    AND t.body ~* '\d+\.\d+(\.\d+)?'
),

updated AS (
  UPDATE dwh.facts f
  SET dimension_application_version = u.new_version_id
  FROM to_update u
  WHERE f.fact_id = u.fact_id
    AND u.new_version_id IS NOT NULL
  RETURNING f.fact_id
)

SELECT COUNT(*) AS backfilled_count FROM updated;

COMMIT;

-- Optional: show new version dimension rows
SELECT COUNT(*) AS dimension_application_versions_rows
FROM dwh.dimension_application_versions;
