-- Phase 2: Update recent_opened_dimension_id_date for all facts
-- This is done AFTER Phase 1 parallel load, using a single massive UPDATE
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-22

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Starting Phase 2: Updating recent_opened_dimension_id_date for all facts' AS Task;

-- Create indexes for faster lookups (if not exists)
CREATE INDEX IF NOT EXISTS facts_id_note_fact_id_idx ON dwh.facts (id_note, fact_id);
CREATE INDEX IF NOT EXISTS facts_id_note_action_fact_id_idx ON dwh.facts (id_note, action_comment, fact_id);

-- Update recent_opened_dimension_id_date for all facts
-- Strategy: Use LATERAL JOIN to find the most recent opening action (opened or reopened)
-- for each note, then update all facts of that note
UPDATE dwh.facts f
SET recent_opened_dimension_id_date = opening.recent_opened_date
FROM (
  SELECT DISTINCT ON (f2.id_note)
    f2.id_note,
    f2.opened_dimension_id_date as recent_opened_date
  FROM dwh.facts f2
  WHERE f2.action_comment IN ('opened', 'reopened')
  ORDER BY f2.id_note, f2.fact_id DESC
) opening
WHERE f.id_note = opening.id_note
AND f.recent_opened_dimension_id_date IS NULL;

-- For facts with action_comment = 'opened' or 'reopened', use their own date
UPDATE dwh.facts
SET recent_opened_dimension_id_date = opened_dimension_id_date
WHERE action_comment IN ('opened', 'reopened')
AND recent_opened_dimension_id_date IS NULL;

-- For facts with action_comment = 'closed', use the opened date
UPDATE dwh.facts
SET recent_opened_dimension_id_date = opened_dimension_id_date
WHERE action_comment = 'closed'
AND recent_opened_dimension_id_date IS NULL;

-- Verify all facts have recent_opened_dimension_id_date set
DO $$
DECLARE
  null_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO null_count
  FROM dwh.facts
  WHERE recent_opened_dimension_id_date IS NULL;

  IF null_count > 0 THEN
    RAISE WARNING 'Phase 2: % facts still have NULL recent_opened_dimension_id_date', null_count;
  ELSE
    RAISE NOTICE 'Phase 2: All facts have recent_opened_dimension_id_date set successfully';
  END IF;
END $$;

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Phase 2 completed: recent_opened_dimension_id_date updated for all facts' AS Task;

