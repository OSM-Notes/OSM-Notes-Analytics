-- Simple initial load procedure that processes all historical data.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-24

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Starting initial load of all historical data' AS Task;

-- Create a simple procedure for initial load
CREATE OR REPLACE PROCEDURE staging.process_initial_load()
LANGUAGE plpgsql
AS $proc$
DECLARE
  m_dimension_country_id INTEGER;
  m_dimension_user_open INTEGER;
  m_dimension_user_close INTEGER;
  m_dimension_user_action INTEGER;
  m_opened_id_date INTEGER;
  m_opened_id_hour_of_week INTEGER;
  m_closed_id_date INTEGER;
  m_closed_id_hour_of_week INTEGER;
  m_action_id_date INTEGER;
  m_action_id_hour_of_week INTEGER;
  m_application INTEGER;
  m_application_version INTEGER;
  m_recent_opened_dimension_id_date INTEGER;
  m_hashtag_number INTEGER;
  m_text_comment TEXT;
  m_hashtag_name TEXT;
  m_all_hashtag_ids INTEGER[]; -- Array to store ALL hashtags (unlimited)
  m_timezone_id INTEGER;
  m_local_action_id_date INTEGER;
  m_local_action_id_hour_of_week INTEGER;
  m_season_id SMALLINT;
  m_latitude DECIMAL;
  m_longitude DECIMAL;
  m_comment_length INTEGER;
  m_has_url BOOLEAN;
  m_has_mention BOOLEAN;
  rec_note_action RECORD;
  notes_cursor REFCURSOR;
  m_count INTEGER := 0;
BEGIN
  RAISE NOTICE 'Starting initial load of all historical data...';

  -- Open cursor for all notes ordered by note_id and sequence_action
  OPEN notes_cursor FOR
   SELECT /* Notes-staging */
    c.note_id id_note, c.sequence_action sequence_action,
    n.created_at created_at, o.id_user created_id_user, n.id_country id_country,
    c.sequence_action seq, c.event action_comment, c.id_user action_id_user,
    c.created_at action_at, t.body
   FROM public.note_comments c
    JOIN public.notes n
    ON (c.note_id = n.note_id)
    JOIN public.note_comments o
    ON (n.note_id = o.note_id
        AND o.event = 'opened')
    LEFT JOIN public.note_comments_text t
    ON (c.note_id = t.note_id AND c.sequence_action = t.sequence_action)
   ORDER BY c.note_id, c.sequence_action;

  LOOP
   FETCH notes_cursor INTO rec_note_action;
   EXIT WHEN NOT FOUND;

   -- Get country dimension
   SELECT /* Notes-staging */ dimension_country_id
    INTO m_dimension_country_id
   FROM dwh.dimension_countries
   WHERE country_id = rec_note_action.id_country;
   IF (m_dimension_country_id IS NULL) THEN
    -- Try to insert the country if it exists in base table
    INSERT INTO dwh.dimension_countries
     (country_id, country_name, country_name_es, country_name_en)
    SELECT /* Notes-staging */ c.country_id, c.country_name, c.country_name_es, c.country_name_en
    FROM public.countries c
    WHERE c.country_id = rec_note_action.id_country
     AND c.country_id NOT IN (SELECT country_id FROM dwh.dimension_countries)
    ON CONFLICT (country_id) DO NOTHING
    RETURNING dimension_country_id INTO m_dimension_country_id;

    -- If still NULL (country not in base table or insert failed), use fallback
    IF (m_dimension_country_id IS NULL) THEN
     -- Use fallback country (dimension_country_id = 1, country_id = -1)
     SELECT /* Notes-staging */ dimension_country_id
      INTO m_dimension_country_id
     FROM dwh.dimension_countries
     WHERE country_id = -1;
     -- If fallback doesn't exist, create it (with ON CONFLICT to handle parallel inserts)
     IF (m_dimension_country_id IS NULL) THEN
      INSERT INTO dwh.dimension_countries
       (country_id, country_name, country_name_es, country_name_en)
      VALUES (-1, 'Unknown - International waters',
       'Desconocido - Aguas internacionales', 'Unknown - International waters')
      ON CONFLICT (country_id) DO NOTHING
      RETURNING dimension_country_id INTO m_dimension_country_id;
      -- If still NULL after conflict, select it
      IF (m_dimension_country_id IS NULL) THEN
       SELECT /* Notes-staging */ dimension_country_id
        INTO m_dimension_country_id
       FROM dwh.dimension_countries
       WHERE country_id = -1;
      END IF;
     END IF;
    END IF;
   END IF;

   -- Get user dimensions
   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_open
   FROM dwh.dimension_users
   WHERE user_id = rec_note_action.created_id_user AND is_current;

   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_action
   FROM dwh.dimension_users
   WHERE user_id = rec_note_action.action_id_user AND is_current;

   m_dimension_user_close := m_dimension_user_action;

   -- Get date and time dimensions
   m_opened_id_date := dwh.get_date_id(rec_note_action.created_at);
   m_opened_id_hour_of_week := dwh.get_hour_of_week_id(rec_note_action.created_at);
   m_action_id_date := dwh.get_date_id(rec_note_action.action_at);
   m_action_id_hour_of_week := dwh.get_hour_of_week_id(rec_note_action.action_at);

   -- Initialize closed dimensions
   m_closed_id_date := NULL;
   m_closed_id_hour_of_week := NULL;

   -- Get application info if present
   m_text_comment := rec_note_action.body;
   IF (m_text_comment LIKE '%iD%' OR m_text_comment LIKE '%JOSM%' OR m_text_comment LIKE '%Potlatch%') THEN
    m_application := staging.get_application(m_text_comment);
    -- Try to parse version simple pattern N.N or N.N.N
    IF (m_text_comment ~* '\\d+\\.\\d+(\\.\\d+)?') THEN
     m_application_version := dwh.get_application_version_id(
       m_application,
       (SELECT regexp_match(m_text_comment, '(\\d+\\.\\d+(?:\\.\\d+)?)')::text)
     );
    END IF;
   ELSE
    m_application := NULL;
    m_application_version := NULL;
   END IF;

   -- Get the most recent opening action: creation or reopening.
   IF (rec_note_action.action_comment = 'opened') THEN
    m_recent_opened_dimension_id_date := m_opened_id_date;
   ELSIF (rec_note_action.action_comment = 'reopened') THEN
    m_recent_opened_dimension_id_date := m_action_id_date;
   ELSE
    -- For other actions, find the most recent opening from already processed facts
    SELECT /* Notes-staging */ recent_opened_dimension_id_date
     INTO m_recent_opened_dimension_id_date
    FROM staging.facts_temp f
    WHERE f.fact_id = (
     SELECT /* Notes-staging */ max(fact_id)
     FROM staging.facts_temp f
     WHERE f.id_note = rec_note_action.id_note
    );
   END IF;

   -- Handle case where we can't find opening date (shouldn't happen with proper ordering)
   IF (m_recent_opened_dimension_id_date IS NULL) THEN
    RAISE NOTICE 'Warning: Could not find opening date for note_id %, sequence % - using action date',
      rec_note_action.id_note, rec_note_action.sequence_action;
    m_recent_opened_dimension_id_date := m_action_id_date;
   END IF;

   -- Get hashtags (UNLIMITED)
   m_hashtag_number := 0;
   m_all_hashtag_ids := ARRAY[]::INTEGER[]; -- Initialize empty array

   IF (rec_note_action.body LIKE '%#%') THEN
    m_text_comment := rec_note_action.body;

    -- Process ALL hashtags using WHILE loop (no limit)
    WHILE (m_text_comment LIKE '%#%') LOOP
     CALL staging.get_hashtag(m_text_comment, m_hashtag_name);
     m_hashtag_number := m_hashtag_number + 1;

     -- Get hashtag ID and store in array
     DECLARE
      hashtag_id INTEGER;
     BEGIN
      hashtag_id := staging.get_hashtag_id(m_hashtag_name);
      m_all_hashtag_ids := array_append(m_all_hashtag_ids, hashtag_id);
     END;
    END LOOP;
   END IF;

   -- Get timezone and local time info
   SELECT n.latitude, n.longitude INTO m_latitude, m_longitude
   FROM public.notes n WHERE n.note_id = rec_note_action.id_note;
   m_timezone_id := dwh.get_timezone_id_by_lonlat(m_longitude, m_latitude);
   m_local_action_id_date := dwh.get_local_date_id(rec_note_action.action_at, m_timezone_id);
   m_local_action_id_hour_of_week := dwh.get_local_hour_of_week_id(rec_note_action.action_at, m_timezone_id);
   m_season_id := dwh.get_season_id(rec_note_action.action_at, m_latitude);

   -- Calculate comment metrics
   m_comment_length := LENGTH(rec_note_action.body);
   m_has_url := rec_note_action.body ~ 'https?://';
   m_has_mention := rec_note_action.body ~ '@\w+';

   -- Insert the fact into staging
   INSERT INTO staging.facts_temp (
     id_note, sequence_action, dimension_id_country,
     action_at, action_comment, action_dimension_id_date,
     action_dimension_id_hour_of_week, action_dimension_id_user,
     opened_dimension_id_date, opened_dimension_id_hour_of_week,
     opened_dimension_id_user,
     closed_dimension_id_date, closed_dimension_id_hour_of_week,
     closed_dimension_id_user, dimension_application_creation,
     dimension_application_version,
     recent_opened_dimension_id_date, hashtag_number,
     action_timezone_id, local_action_dimension_id_date,
     local_action_dimension_id_hour_of_week, action_dimension_id_season,
     comment_length, has_url, has_mention
    ) VALUES (
     rec_note_action.id_note, rec_note_action.sequence_action, m_dimension_country_id,
     rec_note_action.action_at, rec_note_action.action_comment,
     m_action_id_date, m_action_id_hour_of_week, m_dimension_user_action,
     m_opened_id_date, m_opened_id_hour_of_week, m_dimension_user_open,
     m_closed_id_date, m_closed_id_hour_of_week, m_dimension_user_close,
     m_application, m_application_version,
     m_recent_opened_dimension_id_date, m_hashtag_number,
     m_timezone_id, m_local_action_id_date,
     m_local_action_id_hour_of_week, m_season_id,
     m_comment_length, m_has_url, m_has_mention
    );

   m_count := m_count + 1;
   IF (MOD(m_count, 10000) = 0) THEN
    RAISE NOTICE '%: % processed facts until %.', CLOCK_TIMESTAMP(), m_count,
     rec_note_action.action_at;
   END IF;

  END LOOP;

  CLOSE notes_cursor;

  -- Copy from staging to production
  RAISE NOTICE 'Copying % facts from staging to production...', m_count;
  INSERT INTO dwh.facts SELECT * FROM staging.facts_temp;

  -- Clean up staging table
  DROP TABLE staging.facts_temp;
  DROP SEQUENCE staging.facts_temp_seq;

  RAISE NOTICE 'Initial load completed successfully with % facts processed.', m_count;
END
$proc$;

-- Execute the initial load
CALL staging.process_initial_load();

-- Drop the procedure
DROP PROCEDURE staging.process_initial_load();

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Initial load completed' AS Task;
