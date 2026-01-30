-- Adds constraints, indexes, and triggers to the fact table.
-- Includes foreign keys, performance indexes, and resolution metric triggers.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-24

-- Primary keys
-- NOTE: Cannot add PRIMARY KEY to partitioned table without including partition key column
-- The facts table is partitioned by action_at, so we skip the PRIMARY KEY constraint
-- and rely on fact_id uniqueness instead
SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Skipping primary key (partitioned table)' AS Task;

-- ALTER TABLE dwh.facts
--  ADD CONSTRAINT pk_facts
--  PRIMARY KEY (fact_id);

-- Foreign keys.
SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating foreign keys' AS Task;

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_country
 FOREIGN KEY (dimension_id_country)
 REFERENCES dwh.dimension_countries (dimension_country_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_action
 FOREIGN KEY (action_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_hour_of_week_action
 FOREIGN KEY (action_dimension_id_hour_of_week)
  REFERENCES dwh.dimension_time_of_week (dimension_tow_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_action
 FOREIGN KEY (action_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_opened
 FOREIGN KEY (opened_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_time_opened
 FOREIGN KEY (opened_dimension_id_hour_of_week)
  REFERENCES dwh.dimension_time_of_week (dimension_tow_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_opened
 FOREIGN KEY (opened_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_closed
 FOREIGN KEY (closed_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_time_closed
 FOREIGN KEY (closed_dimension_id_hour_of_week)
  REFERENCES dwh.dimension_time_of_week (dimension_tow_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_closed
 FOREIGN KEY (closed_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_application_created
 FOREIGN KEY (dimension_application_creation)
 REFERENCES dwh.dimension_applications (dimension_application_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_application_version
 FOREIGN KEY (dimension_application_version)
 REFERENCES dwh.dimension_application_versions (dimension_application_version_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_timezone_action
 FOREIGN KEY (action_timezone_id)
 REFERENCES dwh.dimension_timezones (dimension_timezone_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_local_day_action
 FOREIGN KEY (local_action_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_local_hour_action
 FOREIGN KEY (local_action_dimension_id_hour_of_week)
 REFERENCES dwh.dimension_time_of_week (dimension_tow_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_season_action
 FOREIGN KEY (action_dimension_id_season)
 REFERENCES dwh.dimension_seasons (dimension_season_id);

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating indexes' AS Task;

-- Unique constraint to prevent duplicate facts
-- A fact is uniquely identified by (id_note, action_at)
-- Note: sequence_action can be NULL, so we use action_at instead
-- First, remove any duplicate facts (keep the one with the lowest fact_id)
DO $$
DECLARE
  duplicates_count INTEGER;
BEGIN
  -- Delete duplicate facts, keeping only the one with the lowest fact_id
  WITH duplicates AS (
    SELECT fact_id, ROW_NUMBER() OVER (PARTITION BY id_note, action_at ORDER BY fact_id) as rn
    FROM dwh.facts
  )
  DELETE FROM dwh.facts
  WHERE fact_id IN (
    SELECT fact_id FROM duplicates WHERE rn > 1
  );

  GET DIAGNOSTICS duplicates_count = ROW_COUNT;
  IF duplicates_count > 0 THEN
    RAISE NOTICE 'Removed % duplicate facts before creating unique index', duplicates_count;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS facts_unique_note_action
 ON dwh.facts (id_note, action_at);
COMMENT ON INDEX dwh.facts_unique_note_action IS
  'Prevents duplicate facts: one fact per note action timestamp';

-- Unique keys

CREATE INDEX IF NOT EXISTS facts_action_date ON dwh.facts (action_at);
COMMENT ON INDEX dwh.facts_action_date IS
  'Improves queries by action timestamp';

-- Comment metrics indexes
CREATE INDEX IF NOT EXISTS facts_has_url ON dwh.facts (has_url) WHERE has_url = TRUE;
COMMENT ON INDEX dwh.facts_has_url IS
  'Improves queries filtering comments with URLs';

CREATE INDEX IF NOT EXISTS facts_has_mention ON dwh.facts (has_mention) WHERE has_mention = TRUE;
COMMENT ON INDEX dwh.facts_has_mention IS
  'Improves queries filtering comments with mentions';

CREATE INDEX IF NOT EXISTS action_idx
 ON dwh.facts (action_dimension_id_user, action_comment, id_note);
COMMENT ON INDEX dwh.action_idx IS 'Improves queries by user and action type';

CREATE INDEX IF NOT EXISTS open_user_idx
 ON dwh.facts (opened_dimension_id_user);
COMMENT ON INDEX dwh.open_user_idx IS 'Improves queries by creating user';

CREATE INDEX IF NOT EXISTS open_idnote_idx
 ON dwh.facts (opened_dimension_id_user, id_note);
COMMENT ON INDEX dwh.open_idnote_idx IS 'Improves queries by creating user';

CREATE INDEX IF NOT EXISTS open_user_date_idx
 ON dwh.facts (opened_dimension_id_date, opened_dimension_id_user);
COMMENT ON INDEX dwh.open_user_date_idx IS
  'Improves queries by creating date and user';

CREATE INDEX IF NOT EXISTS open_date_user_idx
 ON dwh.facts (opened_dimension_id_user, opened_dimension_id_date);
COMMENT ON INDEX dwh.open_date_user_idx IS
  'Improves queries by creating user and date';

CREATE INDEX IF NOT EXISTS closed_user_idx
ON dwh.facts (closed_dimension_id_user);
COMMENT ON INDEX dwh.closed_user_idx IS 'Improves queries by closing user';

CREATE INDEX IF NOT EXISTS closed_idnote_idx
ON dwh.facts (closed_dimension_id_user, id_note);
COMMENT ON INDEX dwh.closed_idnote_idx IS 'Improves queries by closing user';

CREATE INDEX IF NOT EXISTS closed_user_date_idx
ON dwh.facts (closed_dimension_id_date, closed_dimension_id_user);
COMMENT ON INDEX dwh.closed_user_date_idx IS
  'Improves queries by closing date and user';

CREATE INDEX IF NOT EXISTS closed_date_user_idx
ON dwh.facts (closed_dimension_id_user, closed_dimension_id_date);
COMMENT ON INDEX dwh.closed_date_user_idx IS
  'Improves queries by closing user and date';

CREATE INDEX IF NOT EXISTS country_open_user_idx
ON dwh.facts (dimension_id_country, opened_dimension_id_user);
COMMENT ON INDEX dwh.country_open_user_idx IS
  'Improves queries by country and opening user';

CREATE INDEX IF NOT EXISTS country_closed_user_idx
ON dwh.facts (dimension_id_country, closed_dimension_id_user);
COMMENT ON INDEX dwh.country_closed_user_idx IS
  'Improves queries by country and closing user';

CREATE INDEX IF NOT EXISTS hours_opening_idx
ON dwh.facts (opened_dimension_id_hour_of_week, opened_dimension_id_user);
COMMENT ON INDEX dwh.hours_opening_idx IS
  'Improves queries by opening hour and user';

CREATE INDEX IF NOT EXISTS hours_commenting_idx
ON dwh.facts (action_dimension_id_hour_of_week, action_dimension_id_user);
COMMENT ON INDEX dwh.hours_commenting_idx IS
  'Improves queries by action hour and user';

CREATE INDEX IF NOT EXISTS hours_closing_idx
ON dwh.facts (closed_dimension_id_hour_of_week, closed_dimension_id_user);
COMMENT ON INDEX dwh.hours_closing_idx IS
  'Improves queries by closing hour and user';

CREATE INDEX IF NOT EXISTS user_dateidx
ON dwh.facts (action_dimension_id_user, action_dimension_id_date);
COMMENT ON INDEX dwh.user_dateidx IS
  'Improves queries by action user and date';

CREATE INDEX IF NOT EXISTS date_user_action_idx
ON dwh.facts (action_dimension_id_date, action_dimension_id_user,
 action_comment);
COMMENT ON INDEX dwh.date_user_action_idx IS
  'Improves queries by action date, user and type';

CREATE INDEX IF NOT EXISTS date_action_country_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date, action_comment);
COMMENT ON INDEX dwh.date_action_country_idx IS
  'Improves queries by action country, date and type';

CREATE INDEX IF NOT EXISTS date_action_open_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date,
  opened_dimension_id_user);
COMMENT ON INDEX dwh.date_action_open_idx IS
  'Improves queries by action country, date and user open';

CREATE INDEX IF NOT EXISTS date_action_close_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date,
  closed_dimension_id_user);
COMMENT ON INDEX dwh.date_action_close_idx IS
  'Improves queries by action country, date and user close';

CREATE INDEX IF NOT EXISTS action_country_idx
ON dwh.facts (dimension_id_country, action_comment);
COMMENT ON INDEX dwh.action_country_idx IS
  'Improves queries by country and action type';

CREATE INDEX IF NOT EXISTS recent_opened_idx
 ON dwh.facts (recent_opened_dimension_id_date);
COMMENT ON INDEX dwh.recent_opened_idx IS 'Improves queries for reopened notes';

CREATE INDEX IF NOT EXISTS resolution_idx
 ON dwh.facts (id_note, fact_id);
COMMENT ON INDEX dwh.resolution_idx IS 'Improves queries to get resolve notes';

CREATE INDEX IF NOT EXISTS user_note_idx
 ON dwh.facts (id_note, fact_id);
COMMENT ON INDEX dwh.user_note_idx IS 'Improves queries to get resolve notes';

CREATE INDEX IF NOT EXISTS note_sequence_idx
 ON dwh.facts (id_note, sequence_action);
COMMENT ON INDEX dwh.note_sequence_idx IS 'Improves queries to get notes and sequence';

CREATE INDEX IF NOT EXISTS note_action_at_idx
 ON dwh.facts (action_at);

-- New indexes for local analysis and seasons
CREATE INDEX IF NOT EXISTS local_action_idx
 ON dwh.facts (action_timezone_id, local_action_dimension_id_date,
  local_action_dimension_id_hour_of_week);
COMMENT ON INDEX dwh.local_action_idx IS 'Queries by local tz/date/hour';

CREATE INDEX IF NOT EXISTS season_action_idx
 ON dwh.facts (action_dimension_id_season, action_dimension_id_date);
COMMENT ON INDEX dwh.season_action_idx IS 'Queries by season and date';
COMMENT ON INDEX dwh.note_action_at_idx IS 'Improves queries with action_at';

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating triggers' AS Task;

CREATE OR REPLACE FUNCTION dwh.update_days_to_resolution()
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
   SELECT /* Notes-ETL */ date_id
    INTO m_open_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.opened_dimension_id_date;

   SELECT /* Notes-ETL */ date_id
    INTO m_close_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.action_dimension_id_date;

   m_days := m_close_date - m_open_date;
   UPDATE dwh.facts
    SET days_to_resolution = m_days
     WHERE fact_id = NEW.fact_id;

   -- Days between last reopen and most recent close.
   SELECT /* Notes-ETL */ MAX(date_id)
    INTO m_reopen_date
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON f.action_dimension_id_date = d.dimension_day_id
    WHERE id_note = NEW.id_note
    AND action_comment = 'reopened';
   IF (m_reopen_date IS NOT NULL) THEN
    -- Days from the last reopen.
    m_days := m_close_date - m_reopen_date;
    UPDATE dwh.facts
     SET days_to_resolution_from_reopen = m_days
     WHERE fact_id = NEW.fact_id;

    -- Days in open status
    SELECT /* Notes-ETL */ SUM(days_difference)
     INTO m_days
    FROM (
     SELECT /* Notes-ETL */ dd.date_id - dd2.date_id days_difference
     FROM dwh.facts f
     JOIN dwh.dimension_days dd
     ON f.action_dimension_id_date = dd.dimension_day_id
     JOIN dwh.dimension_days dd2
     ON f.recent_opened_dimension_id_date = dd2.dimension_day_id
     WHERE f.id_note = NEW.id_note
     AND f.action_comment <> 'closed'
    ) AS t
    ;
    UPDATE dwh.facts
     SET days_to_resolution_active = m_days
     WHERE fact_id = NEW.fact_id;

   END IF;
  END IF;
  RETURN NEW;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION dwh.update_days_to_resolution IS
  'Sets the number of days between the creation and the resolution dates';

-- Drop trigger if exists before creating it
DROP TRIGGER IF EXISTS update_days_to_resolution ON dwh.facts;

CREATE TRIGGER update_days_to_resolution
  AFTER INSERT ON dwh.facts
  FOR EACH ROW
  EXECUTE FUNCTION dwh.update_days_to_resolution()
;
COMMENT ON TRIGGER update_days_to_resolution ON dwh.facts IS
  'Updates the number of days between creation and resolution dates';

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating indexes for fact_hashtags bridge table' AS Task;

-- Indexes for fact_hashtags bridge table (for hashtag analytics)
CREATE INDEX IF NOT EXISTS idx_fact_hashtags_fact
  ON dwh.fact_hashtags(fact_id);
COMMENT ON INDEX dwh.idx_fact_hashtags_fact IS
  'Improves joins from fact_hashtags to facts table';

CREATE INDEX IF NOT EXISTS idx_fact_hashtags_tag
  ON dwh.fact_hashtags(dimension_hashtag_id);
COMMENT ON INDEX dwh.idx_fact_hashtags_tag IS
  'Improves queries filtering by specific hashtag';

CREATE INDEX IF NOT EXISTS idx_fact_hashtags_composite
  ON dwh.fact_hashtags(dimension_hashtag_id, fact_id);
COMMENT ON INDEX dwh.idx_fact_hashtags_composite IS
  'Composite index for common hashtag + fact join patterns';
