-- Create procedure for staging tables for year ${YEAR}.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-24

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Creating staging procedure for year' AS Task;

/**
 * Processes comments and inserts them into the fact table.
 * There are different processing types:
 * true: >=
 * false: =
 */
CREATE OR REPLACE PROCEDURE staging.process_notes_at_date_${YEAR} (
  max_processed_timestamp TIMESTAMP,
  INOUT m_count INTEGER,
  m_equals BOOLEAN,
  m_process_id_bash INTEGER DEFAULT NULL
 )
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
   m_fact_id INTEGER;
   m_comment_length INTEGER;
   m_has_url BOOLEAN;
   m_has_mention BOOLEAN;
  rec_note_action RECORD;
  notes_on_day REFCURSOR;
  m_process_id_db INTEGER;

 BEGIN
  -- Check the DB lock to validate it is from the same process (if process_id provided)
  IF (m_process_id_bash IS NOT NULL) THEN
   SELECT /* Notes-staging */ value
     INTO m_process_id_db
   FROM properties
   WHERE key = 'lock';
   IF (m_process_id_db IS NULL) THEN
    RAISE EXCEPTION 'This call does not have a lock.';
   ELSIF (m_process_id_bash <> m_process_id_db) THEN
    RAISE EXCEPTION 'The process that holds the lock (%) is different from the current one (%).',
      m_process_id_db, m_process_id_bash;
   END IF;
  END IF;

  IF (m_equals) THEN
   OPEN notes_on_day FOR EXECUTE('
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
         AND o.event = ''opened'')
     LEFT JOIN public.note_comments_text t
     ON (c.note_id = t.note_id AND c.sequence_action = t.sequence_action)

    WHERE c.created_at >= ''' || max_processed_timestamp
    || '''  AND DATE(c.created_at) = ''' || DATE(max_processed_timestamp) -- Notes for the same date.
    || ''' ORDER BY c.note_id, c.id
    ');
  ELSE
   OPEN notes_on_day FOR EXECUTE('
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
         AND o.event = ''opened'')
     LEFT JOIN public.note_comments_text t
     ON (c.note_id = t.note_id AND c.sequence_action = t.sequence_action)

    WHERE c.created_at > ''' || max_processed_timestamp
    || '''  AND DATE(c.created_at) = ''' || DATE(max_processed_timestamp) -- Notes for the same date.
    || ''' ORDER BY c.note_id, c.id
    ');
  END IF;
  LOOP
   FETCH notes_on_day INTO rec_note_action;
   -- Exit when no more rows to fetch.
   EXIT WHEN NOT FOUND;

--    rec_note_action.sequence_action;

   -- Gets the country of the comment.
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

   -- Gets the user who created the note.
   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_open
   FROM dwh.dimension_users
    WHERE user_id = rec_note_action.created_id_user AND is_current;

   -- Gets the user who performed the action (if action is opened, then it
   -- is the same).
   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_action
   FROM dwh.dimension_users
    WHERE user_id = rec_note_action.action_id_user AND is_current;

   -- Gets the days of the actions
   m_opened_id_date := dwh.get_date_id(rec_note_action.created_at);
   m_opened_id_hour_of_week :=
     dwh.get_hour_of_week_id(rec_note_action.created_at);
   m_action_id_date := dwh.get_date_id(rec_note_action.action_at);
   m_action_id_hour_of_week :=
     dwh.get_hour_of_week_id(rec_note_action.action_at);

   -- When the action is 'closed' it copies the data from the 'action'.
   IF (rec_note_action.action_comment = 'closed') THEN
    m_closed_id_date := m_action_id_date;
    m_closed_id_hour_of_week := m_action_id_hour_of_week;
    m_dimension_user_close := m_dimension_user_action;
   END IF;

   -- Gets the id of the app, if the action is opening.
   IF (rec_note_action.action_comment = 'opened') THEN
    SELECT /* Notes-staging */ body
     INTO m_text_comment
    FROM public.note_comments_text
    WHERE note_id = rec_note_action.id_note
     AND sequence_action = rec_note_action.seq; -- Sequence should be 1.
    m_application := staging.get_application(m_text_comment);
    IF (m_text_comment ~* '\\d+\\.\\d+(\\.\\d+)?') THEN
      m_application_version := dwh.get_application_version_id(
        m_application,
        (SELECT (regexp_match(m_text_comment, '(\\d+\\.\\d+(?:\\.\\d+)?)'))[1])
      );
    END IF;
   ELSE
    m_application := NULL;
    m_application_version := NULL;
   END IF;

   -- Gets the most recent opening action: creation or reopening.
   IF (rec_note_action.action_comment = 'opened') THEN
    m_recent_opened_dimension_id_date := m_opened_id_date;
   ELSIF (rec_note_action.action_comment = 'reopened') THEN
    m_recent_opened_dimension_id_date := m_action_id_date;
   --ELSE
   -- The real value is computed once all years are merged, in unify part.
   END IF;

   -- Gets hashtags (UNLIMITED)
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

   -- Defaults for local/tz/season
   -- Compute tz/season using note coordinates
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

   -- Insert the fact.
   INSERT INTO staging.facts_${YEAR} (
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
     m_timezone_id, m_local_action_id_date, m_local_action_id_hour_of_week,
     m_season_id,
     m_comment_length, m_has_url, m_has_mention
   ) RETURNING fact_id INTO m_fact_id;

   -- Populate bridge table for hashtags (ALL hashtags - unlimited)
   IF array_length(m_all_hashtag_ids, 1) > 0 THEN
     FOR i IN 1..array_length(m_all_hashtag_ids, 1) LOOP
       INSERT INTO dwh.fact_hashtags (
         fact_id, dimension_hashtag_id, position,
         used_in_action, is_opening_hashtag, is_resolution_hashtag
       ) VALUES (
         m_fact_id, m_all_hashtag_ids[i], i,
         rec_note_action.action_comment,
         (rec_note_action.action_comment = 'opened'),
         (rec_note_action.action_comment = 'closed')
       );
     END LOOP;
   END IF;

   -- Resets the variables.
   m_dimension_country_id := null;

   m_opened_id_date := null;
   m_opened_id_hour_of_week := null;
   m_dimension_user_open := null;

   m_closed_id_date := null;
   m_closed_id_hour_of_week := null;
   m_dimension_user_close := null;

   m_action_id_date := null;
   m_action_id_hour_of_week := null;
   m_dimension_user_action := null;

   m_text_comment := null;
   m_hashtag_name := null;
   m_hashtag_number := 0;
   m_all_hashtag_ids := ARRAY[]::INTEGER[]; -- Reset array

   m_count := m_count + 1;
   IF (MOD(m_count, 10000) = 0) THEN
    RAISE NOTICE '%: % processed facts for % until %.', CLOCK_TIMESTAMP(),
     m_count, ${YEAR}, max_processed_timestamp;
   END IF;

  END LOOP;

  CLOSE notes_on_day;
 END
$proc$
;
COMMENT ON PROCEDURE staging.process_notes_at_date_${YEAR} IS
  'Processes comments for ${YEAR} from base tables more recent than a specific timestamp and loads them in the data warehouse';

CREATE OR REPLACE PROCEDURE staging.process_notes_actions_into_staging_${YEAR} (
 )
 LANGUAGE plpgsql
 AS $proc$
 DECLARE
  qty_dwh_notes INTEGER;
  qty_notes_on_date INTEGER;
  max_note_action_date DATE;
  max_note_on_dwh_timestamp TIMESTAMP;
  max_processed_date DATE;
  min_timestamp TIMESTAMP;
 BEGIN
  -- Base case, when at least the first day of notes of the year is processed.
  SELECT /* Notes-staging */ COUNT(1)
   INTO qty_dwh_notes
  FROM staging.facts_${YEAR};
  IF (qty_dwh_notes = 0) THEN
   -- This is usually January 1st, except for 2013.
   SELECT /* Notes-staging */ MIN(created_at)
    INTO min_timestamp
   FROM public.note_comments
   WHERE EXTRACT(YEAR FROM created_at) = ${YEAR};
   CALL staging.process_notes_at_date_${YEAR}(min_timestamp, qty_dwh_notes,
     TRUE);
  END IF;

  -- Recursive case, when there is at least a day already processed.
  -- Gets the date of the most recent note action from base tables.
  SELECT /* Notes-staging */ MAX(DATE(created_at))
   INTO max_note_action_date
  FROM public.note_comments
  WHERE EXTRACT(YEAR FROM created_at) = ${YEAR};

  -- Gets the date of the most recent note processed on the DWH.
  SELECT /* Notes-staging */ MAX(date_id)
   INTO max_processed_date
  FROM staging.facts_${YEAR} f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id);

  IF (max_note_action_date < max_processed_date) THEN
   RAISE EXCEPTION 'DWH has more recent notes than received on base tables.';
  END IF;

  -- Processes notes while the max note received is equal to the most recent
  -- note processed.
  WHILE (max_processed_date <= max_note_action_date) LOOP
   -- Timestamp of the max processed note on DWH.
   -- It is on the same DATE of max_processed_date.
   SELECT /* Notes-staging */ MAX(action_at)
    INTO max_note_on_dwh_timestamp
   FROM staging.facts_${YEAR}
   WHERE DATE(action_at) = max_processed_date;
   IF (max_note_on_dwh_timestamp IS NULL) THEN
    max_note_on_dwh_timestamp := max_processed_date::TIMESTAMP;
   END IF;

   -- Gets the number of notes that have not being processed on the date being
   -- processed.
   SELECT /* Notes-staging */ COUNT(1)
    INTO qty_notes_on_date
   FROM public.note_comments
   WHERE DATE(created_at) = max_processed_date
    AND created_at > max_note_on_dwh_timestamp
    AND EXTRACT(YEAR FROM created_at) = ${YEAR};
--qty_notes_on_date;

   -- If there are 0 notes to process, then skip to next date that has comments
   -- OPTIMIZATION: Instead of incrementing day by day, jump directly to next date with comments
   IF (qty_notes_on_date = 0) THEN
    -- Find next date that actually has comments (skip empty days) for this year
    SELECT /* Notes-staging */ MIN(DATE(created_at))
     INTO max_processed_date
    FROM public.note_comments
    WHERE DATE(created_at) > max_processed_date
     AND EXTRACT(YEAR FROM created_at) = ${YEAR};

    -- If no more dates with comments, exit loop
    IF (max_processed_date IS NULL OR max_processed_date > max_note_action_date) THEN
     EXIT;
    END IF;

    -- Reset timestamp for new date to start of day
    max_note_on_dwh_timestamp := max_processed_date::TIMESTAMP;


   -- Gets the number of notes that have not being processed on the new date
   -- being processed.
    SELECT /* Notes-staging */ COUNT(1)
     INTO qty_notes_on_date
    FROM public.note_comments
    WHERE DATE(created_at) = max_processed_date
     AND created_at > max_note_on_dwh_timestamp
     AND EXTRACT(YEAR FROM created_at) = ${YEAR};
--qty_notes_on_date;

    -- Not necessary to process more notes on the same date.
    CALL staging.process_notes_at_date_${YEAR}(max_note_on_dwh_timestamp,
     qty_dwh_notes, FALSE);
   ELSE
    -- There are comments not processed on the DHW for the currently processing
    -- day.
--qty_notes_on_date;

    CALL staging.process_notes_at_date_${YEAR}(max_note_on_dwh_timestamp,
     qty_dwh_notes, TRUE);
   END IF;
--max_note_on_dwh_timestamp, qty_notes_on_date;
  END LOOP;
--max_note_action_date;
 END
$proc$
;
COMMENT ON PROCEDURE staging.process_notes_actions_into_staging_${YEAR} IS
  'Processes all non-processes notes for year ${YEAR}';

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'All staging objects created for year ${YEAR}' AS Task;
