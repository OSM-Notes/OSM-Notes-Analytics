-- Create base objects for initial load (without year-specific variables).
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-22

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Creating base staging objects for initial load' AS Task;

-- Create staging facts table (temporary for initial load)
DROP TABLE IF EXISTS staging.facts_temp;
CREATE TABLE staging.facts_temp AS TABLE dwh.facts;

-- Create sequence for staging facts
CREATE SEQUENCE IF NOT EXISTS staging.facts_temp_seq;

-- Set default values
ALTER TABLE staging.facts_temp ALTER fact_id
  SET DEFAULT NEXTVAL('staging.facts_temp_seq'::regclass);

ALTER TABLE staging.facts_temp ALTER processing_time
  SET DEFAULT CURRENT_TIMESTAMP;

-- PRIMARY KEY is already copied from dwh.facts, so no need to add it again
-- REMOVED: ALTER TABLE staging.facts_temp ADD PRIMARY KEY (fact_id);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS facts_action_at_idx_temp ON staging.facts_temp (action_at);
COMMENT ON INDEX staging.facts_action_at_idx_temp IS
  'Improves queries by action timestamp for initial load';

CREATE INDEX IF NOT EXISTS action_idx_temp
 ON staging.facts_temp (action_dimension_id_date, id_note, action_comment);
COMMENT ON INDEX staging.action_idx_temp
 IS 'Improves queries for reopened notes for initial load';

CREATE INDEX IF NOT EXISTS date_differences_idx_temp
 ON staging.facts_temp (action_dimension_id_date,
  recent_opened_dimension_id_date, id_note, action_comment);
COMMENT ON INDEX staging.date_differences_idx_temp
  IS 'Improves queries for reopened notes for initial load';

-- Create function to update days to resolution
CREATE OR REPLACE FUNCTION staging.update_days_to_resolution_temp()
  RETURNS TRIGGER AS
 $$
 DECLARE
  m_open_date DATE;
  m_reopen_date DATE;
  m_close_date DATE;
  m_days INTEGER;
 BEGIN
  IF (NEW.action_comment = 'closed') THEN
   -- Days between initial open and most recent close.
   SELECT /* Notes-staging */ date_id
    INTO m_open_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.opened_dimension_id_date;

   SELECT /* Notes-staging */ date_id
    INTO m_close_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.action_dimension_id_date;

   m_days := m_close_date - m_open_date;
   UPDATE staging.facts_temp
    SET days_to_resolution = m_days
    WHERE fact_id = NEW.fact_id;

   -- Days between last reopen and most recent close.
   SELECT /* Notes-staging */ MAX(date_id)
    INTO m_reopen_date
   FROM staging.facts_temp f
    JOIN dwh.dimension_days d
    ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.id_note = NEW.id_note
    AND f.action_comment = 'reopened';

   IF (m_reopen_date IS NOT NULL) THEN
    -- Days from the last reopen.
    m_days := m_close_date - m_reopen_date;
    UPDATE staging.facts_temp
     SET days_to_resolution_from_reopen = m_days
     WHERE fact_id = NEW.fact_id;

    -- Days in open status
    SELECT /* Notes-staging */ SUM(days_difference)
     INTO m_days
    FROM (
     SELECT /* Notes-staging */ dd.date_id - dd2.date_id days_difference
     FROM staging.facts_temp f
     JOIN dwh.dimension_days dd
     ON f.action_dimension_id_date = dd.dimension_day_id
     JOIN dwh.dimension_days dd2
     ON f.recent_opened_dimension_id_date = dd2.dimension_day_id
     WHERE f.id_note = NEW.id_note
     AND f.action_comment <> 'closed'
    ) AS t
    ;
    UPDATE staging.facts_temp
     SET days_to_resolution_active = m_days
     WHERE fact_id = NEW.fact_id;

   END IF;
  END IF;
  RETURN NEW;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION staging.update_days_to_resolution_temp IS
  'Sets the number of days between the creation and the resolution dates for initial load';

-- Create trigger
CREATE OR REPLACE TRIGGER update_days_to_resolution_temp
  AFTER INSERT ON staging.facts_temp
  FOR EACH ROW
  EXECUTE FUNCTION staging.update_days_to_resolution_temp()
;
COMMENT ON TRIGGER update_days_to_resolution_temp ON staging.facts_temp IS
  'Updates the number of days between creation and resolution dates for initial load';

-- Generate all dates from 2013-04-24 to current year
DO /* Notes-ETL-addWeekHours */
$$
DECLARE
  m_day_year DATE;
  m_dummy INTEGER;
  m_max_day_year DATE;
BEGIN
  -- Insert all days from 2013-04-24 to current year in the dimension.
  SELECT /* Notes-staging */ DATE('2013-04-24')
    INTO m_day_year;
  SELECT /* Notes-staging */ DATE(EXTRACT(YEAR FROM CURRENT_DATE) || '-12-31')
    INTO m_max_day_year;
  RAISE NOTICE 'Min and max dates % - %.', m_day_year, m_max_day_year;
  WHILE (m_day_year <= m_max_day_year) LOOP
   m_dummy := dwh.get_date_id(m_day_year);
   SELECT /* Notes-staging */ m_day_year + 1
     INTO m_day_year;
  END LOOP;
  RAISE NOTICE 'All dates generated.';
END
$$;

-- Create index for performance
CREATE INDEX IF NOT EXISTS comments_function_year ON public.note_comments (EXTRACT(YEAR FROM created_at), created_at);
COMMENT ON INDEX comments_function_year IS
  'Index to improve access when processing ETL per years';

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Base staging objects for initial load created' AS Task;
