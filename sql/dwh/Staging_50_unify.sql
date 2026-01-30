-- Unifies facts that were loaded in parallel by year.
-- Computes cross-year metrics and fills recent_opened_dimension_id_date.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-21

-- Set the next number to generate to the sequence.
SELECT /* Notes-staging */
    SETVAL((SELECT PG_GET_SERIAL_SEQUENCE('dwh.facts', 'fact_id')),
    (SELECT (MAX(fact_id) + 1) FROM dwh.facts), FALSE);

DO /* Notes-staging */
 $$
 DECLARE
  m_qty_iterations INTEGER;
  m_iter INTEGER;
  m_recent_opened_dimension_id_date INTEGER;
  m_previous_action_fact_id INTEGER;
  rec_no_recent_open_fact RECORD;
  no_recent_open CURSOR FOR
   SELECT /* Notes-staging */
    fact_id, id_note, action_comment
   FROM dwh.facts f
   WHERE f.recent_opened_dimension_id_date IS NULL
   ORDER BY id_note, action_at
   FOR UPDATE;

 BEGIN
  -- Calculates how many iterations should be run.
  SELECT /* Notes-staging */ MAX(qty)
   INTO m_qty_iterations
  FROM (
   SELECT COUNT(1) qty, id_note
   FROM dwh.facts f
   WHERE f.recent_opened_dimension_id_date IS NULL
   GROUP BY f.id_note
  ) AS t;

  m_iter := 0;
  WHILE (m_iter < m_qty_iterations) LOOP
   OPEN no_recent_open;

   LOOP
    FETCH no_recent_open INTO rec_no_recent_open_fact;
    -- Exit when no more rows to fetch.
    EXIT WHEN NOT FOUND;

    -- Get the previous action fact_id for this note
    SELECT /* Notes-staging */ max(fact_id)
     INTO m_previous_action_fact_id
    FROM dwh.facts f
    WHERE f.id_note = rec_no_recent_open_fact.id_note
    AND f.fact_id < rec_no_recent_open_fact.fact_id;

    -- Try to get recent_opened_dimension_id_date from previous action
    IF (m_previous_action_fact_id IS NOT NULL) THEN
     SELECT /* Notes-staging */ recent_opened_dimension_id_date
      INTO m_recent_opened_dimension_id_date
     FROM dwh.facts f
     WHERE f.fact_id = m_previous_action_fact_id;
    END IF;

    -- If still NULL, find the most recent 'opened' or 'reopened' action for this note
    IF (m_recent_opened_dimension_id_date IS NULL) THEN
     SELECT /* Notes-staging */ action_dimension_id_date
      INTO m_recent_opened_dimension_id_date
     FROM dwh.facts f
     WHERE f.id_note = rec_no_recent_open_fact.id_note
      AND f.fact_id < rec_no_recent_open_fact.fact_id
      AND f.action_comment IN ('opened', 'reopened')
     ORDER BY f.fact_id DESC
     LIMIT 1;

     -- If this is the first action and it's an 'opened', use opened_dimension_id_date
     IF (m_recent_opened_dimension_id_date IS NULL
         AND rec_no_recent_open_fact.action_comment = 'opened') THEN
      SELECT /* Notes-staging */ opened_dimension_id_date
       INTO m_recent_opened_dimension_id_date
      FROM dwh.facts f
      WHERE f.fact_id = rec_no_recent_open_fact.fact_id;
     END IF;
    END IF;

    UPDATE dwh.facts
     SET recent_opened_dimension_id_date = m_recent_opened_dimension_id_date
     WHERE CURRENT OF no_recent_open;
   END LOOP;

   m_previous_action_fact_id := null;
   m_recent_opened_dimension_id_date := null;

   CLOSE no_recent_open;
   m_iter := m_iter + 1;
  END LOOP;
 END
 $$
;

-- Check if there are still facts with NULL recent_opened_dimension_id_date
-- This should no longer happen with the improved logic above
DO /* Notes-staging */
 $$
 DECLARE
  m_count_nulls INTEGER;
  rec RECORD;
 BEGIN
  SELECT /* Notes-staging */ COUNT(*)
   INTO m_count_nulls
  FROM dwh.facts
  WHERE recent_opened_dimension_id_date IS NULL;

  IF (m_count_nulls > 0) THEN
   RAISE WARNING 'Found % facts with NULL recent_opened_dimension_id_date. These will be logged and deleted.', m_count_nulls;

   -- Log the problematic records for investigation
   RAISE NOTICE 'Logging problematic facts:';
   FOR rec IN (
    SELECT fact_id, id_note, action_comment, action_at,
           action_dimension_id_user, opened_dimension_id_user
    FROM dwh.facts
    WHERE recent_opened_dimension_id_date IS NULL
    ORDER BY id_note, action_at
    LIMIT 100  -- Limit to first 100 to avoid excessive logging
   ) LOOP
    RAISE NOTICE 'fact_id: %, note_id: %, action: %, action_at: %, action_user: %, opened_user: %',
     rec.fact_id, rec.id_note, rec.action_comment, rec.action_at,
     rec.action_dimension_id_user, rec.opened_dimension_id_user;
   END LOOP;

   IF (m_count_nulls > 100) THEN
    RAISE NOTICE '... and % more records', m_count_nulls - 100;
   END IF;

   -- Delete the problematic records
   DELETE FROM dwh.facts
   WHERE recent_opened_dimension_id_date IS NULL;

   RAISE WARNING 'Deleted % facts with NULL recent_opened_dimension_id_date', m_count_nulls;
  ELSE
   RAISE NOTICE 'All facts have valid recent_opened_dimension_id_date. No deletions needed.';
  END IF;
 END
 $$
;

ALTER TABLE dwh.facts ALTER COLUMN recent_opened_dimension_id_date SET NOT NULL;
