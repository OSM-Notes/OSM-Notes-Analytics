-- Phase 2b: Update closed_dimension_id_date for opened facts
-- This updates each opened fact with the NEXT closed action for that note
-- This correctly handles notes with multiple open-close cycles (reopened notes)
-- This is required for ML training data and analytics
-- This should run AFTER Phase 2 (recent_opened_dimension_id_date update)
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-19
-- Purpose: Populate closed_dimension_id_date in opened facts for ML training

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Starting Phase 2b: Updating closed_dimension_id_date for opened facts' AS Task;

-- Create indexes for faster lookups (if not exists)
CREATE INDEX IF NOT EXISTS facts_id_note_action_fact_id_idx ON dwh.facts (id_note, action_comment, fact_id);
CREATE INDEX IF NOT EXISTS facts_closed_dimension_id_date_idx ON dwh.facts (closed_dimension_id_date) WHERE action_comment = 'opened';
CREATE INDEX IF NOT EXISTS facts_id_note_action_at_idx ON dwh.facts (id_note, action_at, action_comment);

-- Update closed_dimension_id_date for opened facts where note has been closed
-- Strategy: For each opened fact, find the NEXT closed action that occurs AFTER it
-- This correctly pairs each opened fact with its immediate close, not the most recent close
-- Note: Cannot use LATERAL in UPDATE FROM, so we use a subquery with DISTINCT ON to find the next close
UPDATE dwh.facts f_opened
SET
  closed_dimension_id_date = closed_info.next_closed_date,
  closed_dimension_id_hour_of_week = closed_info.next_closed_hour,
  closed_dimension_id_user = closed_info.next_closed_user
FROM (
  SELECT DISTINCT ON (f_opened_inner.fact_id)
    f_opened_inner.fact_id,
    f_closed.action_dimension_id_date as next_closed_date,
    f_closed.action_dimension_id_hour_of_week as next_closed_hour,
    f_closed.action_dimension_id_user as next_closed_user
  FROM dwh.facts f_opened_inner
  JOIN dwh.facts f_closed ON (
    f_closed.id_note = f_opened_inner.id_note
    AND f_closed.action_comment = 'closed'
    AND f_closed.action_at > f_opened_inner.action_at
  )
  WHERE f_opened_inner.action_comment = 'opened'
    AND f_opened_inner.closed_dimension_id_date IS NULL
  ORDER BY f_opened_inner.fact_id, f_closed.action_at ASC
) closed_info
WHERE f_opened.fact_id = closed_info.fact_id;

-- Verify update
-- Check that opened facts that have a subsequent close action have been updated
DO $$
DECLARE
  null_count INTEGER;
  total_opened INTEGER;
  with_closed INTEGER;
BEGIN
  SELECT COUNT(*) INTO total_opened
  FROM dwh.facts
  WHERE action_comment = 'opened';

  SELECT COUNT(*) INTO with_closed
  FROM dwh.facts
  WHERE action_comment = 'opened'
    AND closed_dimension_id_date IS NOT NULL;

  -- Count opened facts that should have a closed_dimension_id_date
  -- (i.e., opened facts that have a closed action occurring AFTER them)
  SELECT COUNT(*) INTO null_count
  FROM dwh.facts f_opened
  WHERE f_opened.action_comment = 'opened'
    AND f_opened.closed_dimension_id_date IS NULL
    AND EXISTS (
      SELECT 1
      FROM dwh.facts f_closed
      WHERE f_closed.id_note = f_opened.id_note
        AND f_closed.action_comment = 'closed'
        AND f_closed.action_at > f_opened.action_at
    );

  IF null_count > 0 THEN
    RAISE WARNING 'Phase 2b: % opened facts still have NULL closed_dimension_id_date (but have a subsequent close action)', null_count;
  ELSE
    RAISE NOTICE 'Phase 2b: Updated closed_dimension_id_date for opened facts. Total opened: %, With closed date: %', total_opened, with_closed;
  END IF;
END $$;

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Phase 2b completed: closed_dimension_id_date updated for opened facts' AS Task;
