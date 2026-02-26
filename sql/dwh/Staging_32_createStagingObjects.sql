-- Create procedure for staging tables.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-24

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Creating staging procedure' AS Task;

/**
 * Processes comments and inserts them into the fact table.
 */
CREATE OR REPLACE PROCEDURE staging.process_notes_at_date (
  max_processed_timestamp TIMESTAMP,
  INOUT m_count INTEGER,
  m_equals BOOLEAN
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
  m_fact_id INTEGER;
   m_latitude DECIMAL;
   m_longitude DECIMAL;
  m_comment_length INTEGER;
  m_has_url BOOLEAN;
  m_has_mention BOOLEAN;
  rec_note_action RECORD;
  notes_on_day REFCURSOR;
  index_exists BOOLEAN;
  max_note_id_snapshot INTEGER; -- Snapshot of MAX(note_id) to ensure consistency
 BEGIN
  -- Capture MAX(note_id) at the start to ensure consistency between notes and note_comments
  -- This prevents race conditions where new notes are inserted while processing
  SELECT COALESCE(MAX(note_id), 0)
    INTO max_note_id_snapshot
  FROM public.notes;

  -- Note: For partitioned tables, ON CONFLICT doesn't work with indexes on the main table
  -- We need indexes on each partition. Since this is complex and the unique index
  -- will prevent duplicates at the database level, we'll insert without ON CONFLICT
  -- and let the database enforce uniqueness. If a duplicate is attempted, it will fail
  -- and we can handle it gracefully.
  -- The unique index facts_unique_note_action exists and will prevent duplicates.

  -- Note: The cursor queries below read from ingestion tables (note_comments, notes, note_comments_text)
  -- and should ideally be executed in READ ONLY mode for better concurrency, but this procedure also
  -- performs writes, so READ ONLY cannot be applied to the entire transaction.
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
         -- Direct enum comparison (no CAST needed): foreign table is defined as note_event_enum
         -- ETL_60_setupFDW.sql ensures the foreign table uses note_event_enum type, not TEXT
         -- This allows PostgreSQL to use indexes and avoids full table scans
         AND o.event = ''opened''
         AND o.note_id <= ' || max_note_id_snapshot || ')
     LEFT JOIN public.note_comments_text t
     ON (c.note_id = t.note_id AND c.sequence_action = t.sequence_action)

    WHERE c.created_at >= ''' || max_processed_timestamp
    || '''  AND DATE(c.created_at) = ''' || DATE(max_processed_timestamp) -- Notes for the same date.
    || '''  AND c.note_id <= ' || max_note_id_snapshot || ' -- Ensure consistency
    ORDER BY c.note_id, c.sequence_action
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
         -- Direct enum comparison (no CAST needed): foreign table is defined as note_event_enum
         -- ETL_60_setupFDW.sql ensures the foreign table uses note_event_enum type, not TEXT
         -- This allows PostgreSQL to use indexes and avoids full table scans
         AND o.event = ''opened''
         AND o.note_id <= ' || max_note_id_snapshot || ')
     LEFT JOIN public.note_comments_text t
     ON (c.note_id = t.note_id AND c.sequence_action = t.sequence_action)

    WHERE c.created_at > ''' || max_processed_timestamp
    || '''  AND DATE(c.created_at) = ''' || DATE(max_processed_timestamp) -- Notes for the same date.
    || '''  AND c.note_id <= ' || max_note_id_snapshot || ' -- Ensure consistency
    ORDER BY c.note_id, c.sequence_action
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
    -- Note: This SELECT reads from ingestion table (countries) and should ideally
    -- be executed in READ ONLY mode for better concurrency, but this procedure also
    -- performs writes, so READ ONLY cannot be applied to the entire transaction.
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
   -- Handle anonymous notes (NULL user_id) by using Anonymous user (user_id = -1)
   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_open
   FROM dwh.dimension_users
    WHERE user_id = COALESCE(rec_note_action.created_id_user, -1) AND is_current;

   -- Gets the user who performed the action (if action is opened, then it
   -- is the same).
   -- Handle anonymous comments (NULL user_id) by using Anonymous user (user_id = -1)
   SELECT /* Notes-staging */ dimension_user_id
    INTO m_dimension_user_action
   FROM dwh.dimension_users
    WHERE user_id = COALESCE(rec_note_action.action_id_user, -1) AND is_current;

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
    -- Use body from cursor (already loaded via LEFT JOIN in query)
    m_text_comment := rec_note_action.body;
     m_application := staging.get_application(m_text_comment);
     -- Try to parse version simple pattern N.N or N.N.N
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
   ELSE
    SELECT /* Notes-staging */ recent_opened_dimension_id_date
     INTO m_recent_opened_dimension_id_date
    FROM dwh.facts f
    WHERE f.fact_id = (
     SELECT /* Notes-staging */ max(fact_id)
     FROM dwh.facts f
     WHERE f.id_note = rec_note_action.id_note
    );
   END IF;
   -- Handle case where we can't find opening date (fallback to opened_dimension_id_date)
   -- This can happen when processing a note for the first time in incremental mode
   IF (m_recent_opened_dimension_id_date IS NULL) THEN
    RAISE NOTICE '% - Warning: Could not find opening date for note_id %, sequence % - using opened_dimension_id_date as fallback',
      CLOCK_TIMESTAMP(), rec_note_action.id_note,
      rec_note_action.sequence_action;
    -- Use opened_dimension_id_date as fallback (always available for any note)
    m_recent_opened_dimension_id_date := m_opened_id_date;
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

   -- Prepare local/timezone/season using note position
   -- Note: This SELECT reads from ingestion table (notes) and should ideally
   -- be executed in READ ONLY mode for better concurrency, but this procedure also
   -- performs writes, so READ ONLY cannot be applied to the entire transaction.
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
   -- Note: For partitioned tables, ON CONFLICT doesn't work reliably
   -- The unique index facts_unique_note_action will prevent duplicates at the database level
   -- If a duplicate is attempted, PostgreSQL will raise an error which we can handle
   BEGIN
    INSERT INTO dwh.facts (
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
    )
    RETURNING fact_id INTO m_fact_id;
   EXCEPTION
    WHEN unique_violation THEN
     -- Duplicate fact, skip it (idempotent operation)
     -- This can happen if the same comment is processed multiple times
     m_fact_id := NULL;
   END;

   -- Populate bridge table for hashtags (ALL hashtags - unlimited)
   -- Only insert hashtags if fact_id is not NULL (fact was successfully inserted)
   -- If fact_id is NULL, it means the fact was a duplicate and was skipped
   IF m_fact_id IS NOT NULL AND array_length(m_all_hashtag_ids, 1) > 0 THEN
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

   -- Modifies the dimension user and country for the datamart to identify it.
   UPDATE /* Notes-ETL */ dwh.dimension_users
    SET modified = TRUE
    WHERE dimension_user_id = m_dimension_user_action;

   UPDATE /* Notes-ETL */ dwh.dimension_countries
    SET modified = TRUE
    WHERE dimension_country_id = m_dimension_country_id;

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
    RAISE NOTICE '%: % processed facts until %.', CLOCK_TIMESTAMP(), m_count,
     max_processed_timestamp;
   END IF;

  END LOOP;

  CLOSE notes_on_day;
 END
$proc$
;
COMMENT ON PROCEDURE staging.process_notes_at_date IS
  'Processes all comments more recent than a specific timestamp, from base tables and loads them in the data warehouse';

CREATE OR REPLACE PROCEDURE staging.process_notes_actions_into_dwh (
 )
 LANGUAGE plpgsql
 AS $proc$
 DECLARE
  qty_dwh_notes INTEGER;
  qty_notes_on_date INTEGER;
  max_note_action_date DATE;
  max_note_on_dwh_timestamp TIMESTAMP;
  max_processed_date DATE;
  initial_load_flag TEXT;
  use_equals BOOLEAN;
  start_of_day TIMESTAMP;
  max_note_id_snapshot INTEGER; -- Snapshot of MAX(note_id) to ensure consistency
  original_statement_timeout TEXT; -- Store original timeout setting
 BEGIN
  -- OPTIMIZATION: Set statement_timeout for FDW queries to prevent indefinite blocking
  -- Default timeout: 5 minutes (300 seconds) - adjust if needed for large datasets
  -- This prevents the ETL from hanging indefinitely on slow FDW queries
  SELECT current_setting('statement_timeout') INTO original_statement_timeout;
  SET LOCAL statement_timeout = '300s'; -- 5 minutes timeout for FDW queries

  -- Capture MAX(note_id) at the start to ensure consistency between notes and note_comments
  -- This prevents race conditions where new notes are inserted while processing
  SELECT COALESCE(MAX(note_id), 0)
    INTO max_note_id_snapshot
  FROM public.notes;

  -- Use this snapshot for all queries to ensure referential integrity
  -- All note_comments processed will have their corresponding notes
  -- Base case, when at least the first day of notes is processed.
  -- There are 231 note actions this day: 2013-04-24 (Epoch's OSM notes).
  -- Check if initial load flag exists in properties FIRST
  -- This is more reliable than counting facts, as the flag indicates the state
  -- The flag can be 'true' (set during table creation) or 'completed' (set after initial load)
  SELECT /* Notes-staging */ value
   INTO initial_load_flag
  FROM dwh.properties
  WHERE key = 'initial load';

  -- Check if there are any facts in DWH
  SELECT /* Notes-staging */ COUNT(1)
   INTO qty_dwh_notes
  FROM dwh.facts;

  -- Only do initial load if:
  -- 1. Initial load flag is NULL or 'true' (not 'completed')
  -- 2. AND there are NO facts
  -- If flag is 'completed', skip initial load even if qty_dwh_notes is 0 (may be a visibility issue)
  -- IMPORTANT: Use IS NOT DISTINCT FROM to handle NULL correctly
  IF (initial_load_flag IS NOT DISTINCT FROM 'completed') THEN
   -- Initial load was already completed, skip it and proceed to incremental
   NULL; -- Do nothing, continue to incremental logic below
  ELSIF (qty_dwh_notes = 0 AND (initial_load_flag IS NULL OR initial_load_flag = 'true')) THEN
   RAISE NOTICE 'INITIAL LOAD DETECTED - Processing all historical data from 2013-04-24';
   RAISE NOTICE 'This may take several hours for the complete dataset.';

   -- Initial load: process all historical data using the same incremental logic
   -- but starting from 2013-04-24
   -- Get the date of the most recent note action from base tables
   -- Filter by max_note_id_snapshot to ensure consistency
   SELECT /* Notes-staging */ MAX(DATE(created_at))
    INTO max_note_action_date
   FROM public.note_comments
   WHERE note_id <= max_note_id_snapshot;

   -- Start from the first date with comments
   -- Filter by max_note_id_snapshot to ensure consistency
   SELECT /* Notes-staging */ MIN(DATE(created_at))
    INTO max_processed_date
   FROM public.note_comments
   WHERE note_id <= max_note_id_snapshot;

   -- Process all dates from first date until the latest date (skip empty days)
   WHILE (max_processed_date <= max_note_action_date) LOOP
    -- Timestamp of the max processed note on DWH for this date (should be NULL for initial load)
    -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage
    SELECT /* Notes-staging */ MAX(action_at)
     INTO max_note_on_dwh_timestamp
    FROM dwh.facts
    WHERE action_at >= max_processed_date::TIMESTAMP
     AND action_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP;

    IF (max_note_on_dwh_timestamp IS NULL) THEN
     max_note_on_dwh_timestamp := max_processed_date::TIMESTAMP;
    END IF;

    -- Count notes to process on this date
    -- Filter by max_note_id_snapshot to ensure consistency
    -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage on FDW
    SELECT /* Notes-staging */ COUNT(1)
     INTO qty_notes_on_date
    FROM public.note_comments
    WHERE created_at >= max_processed_date::TIMESTAMP
     AND created_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP
     AND created_at > max_note_on_dwh_timestamp
     AND note_id <= max_note_id_snapshot;

    -- Process notes for this date if there are any
    IF (qty_notes_on_date > 0) THEN
     CALL staging.process_notes_at_date(max_note_on_dwh_timestamp,
       qty_dwh_notes, TRUE);
    END IF;

    -- Find next date that actually has comments (skip empty days)
    -- Filter by max_note_id_snapshot to ensure consistency
    -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage on FDW
    SELECT /* Notes-staging */ MIN(DATE(created_at))
     INTO max_processed_date
   FROM public.note_comments
   WHERE created_at >= (max_processed_date + INTERVAL '1 day')::TIMESTAMP
     AND note_id <= max_note_id_snapshot;

    -- If no more dates with comments, exit loop
    IF (max_processed_date IS NULL OR max_processed_date > max_note_action_date) THEN
     EXIT;
    END IF;
   END LOOP;

   RAISE NOTICE 'INITIAL LOAD COMPLETED - % facts processed', qty_dwh_notes;

   -- Set initial load flag to prevent re-running initial load
   -- Use INSERT ... ON CONFLICT since key is now PRIMARY KEY
   BEGIN
    INSERT INTO dwh.properties (key, value)
     VALUES ('initial load', 'completed');
   EXCEPTION
    WHEN unique_violation THEN
     UPDATE dwh.properties SET value = 'completed' WHERE key = 'initial load';
   END;

   RETURN; -- Exit procedure after initial load
  END IF;

  -- Incremental case: process only NEW comments since last ETL execution
  -- Get the most recent timestamp processed in DWH (not just the date)
  SELECT /* Notes-staging */ MAX(action_at)
   INTO max_note_on_dwh_timestamp
  FROM dwh.facts;

  -- If no facts exist, this should have been caught by initial load check above
  -- But handle it gracefully just in case
  IF (max_note_on_dwh_timestamp IS NULL) THEN
   RAISE EXCEPTION 'No facts found in DWH but initial load was not executed. This should not happen.';
  END IF;

  -- Get the date of the most recent note action from base tables
  -- Filter by max_note_id_snapshot to ensure consistency
  SELECT /* Notes-staging */ MAX(DATE(created_at))
   INTO max_note_action_date
  FROM public.note_comments
  WHERE note_id <= max_note_id_snapshot;

  -- Get the date of the most recent note processed on the DWH
  SELECT /* Notes-staging */ MAX(date_id)
   INTO max_processed_date
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id);

  -- Validation: DWH should not have more recent data than base tables
  IF (max_note_action_date < max_processed_date) THEN
   RAISE EXCEPTION 'DWH has more recent notes than received on base tables.';
  END IF;

  -- If all comments are already processed, exit early
  IF (max_processed_date > max_note_action_date) THEN
   RAISE NOTICE 'All comments already processed. No new data to process.';
   RETURN;
  END IF;

  -- Process comments incrementally: only process dates that have NEW comments
  -- Start from the date after the last processed date, or the last processed date if it has new comments
  WHILE (max_processed_date <= max_note_action_date) LOOP
   -- Timestamp of the max processed note on DWH.
   -- It is on the same DATE of max_processed_date.
   -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage
   SELECT /* Notes-staging */ MAX(action_at)
    INTO max_note_on_dwh_timestamp
   FROM dwh.facts
   WHERE action_at >= max_processed_date::TIMESTAMP
    AND action_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP;
   IF (max_note_on_dwh_timestamp IS NULL) THEN
    max_note_on_dwh_timestamp := max_processed_date::TIMESTAMP;
   END IF;

   -- Gets the number of notes that have not being processed on the date being
   -- processed.
   -- Filter by max_note_id_snapshot to ensure consistency
   -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage on FDW
    SELECT /* Notes-staging */ COUNT(1)
     INTO qty_notes_on_date
    FROM public.note_comments
    WHERE created_at >= max_processed_date::TIMESTAMP
     AND created_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP
     AND created_at > max_note_on_dwh_timestamp
     AND note_id <= max_note_id_snapshot;
--qty_notes_on_date;

   -- If there are 0 notes to process, then skip to next date that has comments
   -- OPTIMIZATION: Instead of incrementing day by day, jump directly to next date with comments
   IF (qty_notes_on_date = 0) THEN
    -- Find next date that actually has comments (skip empty days)
    -- We only need to check if the date is greater, not the timestamp
    -- Filter by max_note_id_snapshot to ensure consistency
    -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage on FDW
    SELECT /* Notes-staging */ MIN(DATE(created_at))
     INTO max_processed_date
   FROM public.note_comments
   WHERE created_at >= (max_processed_date + INTERVAL '1 day')::TIMESTAMP
     AND note_id <= max_note_id_snapshot;

    -- If no more dates with comments, exit loop
    IF (max_processed_date IS NULL OR max_processed_date > max_note_action_date) THEN
     EXIT;
    END IF;

    -- Get the max timestamp processed for the new date (if any facts exist for this date)
    -- This ensures we don't reprocess comments that were already processed
    -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage
    SELECT /* Notes-staging */ MAX(action_at)
     INTO max_note_on_dwh_timestamp
    FROM dwh.facts
    WHERE action_at >= max_processed_date::TIMESTAMP
     AND action_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP;

    -- Determine if we should use m_equals = TRUE or FALSE
    -- Use TRUE (>=) if:
    --  1. No facts exist for this date (max_note_on_dwh_timestamp IS NULL) - process all comments from start of day
    --  2. The timestamp is at the start of the day (00:00:00) - ensure we catch all comments
    -- Use FALSE (>) if:
    --  - Facts exist and timestamp is not at start of day - only process new comments after the last processed
    start_of_day := max_processed_date::TIMESTAMP;

    IF (max_note_on_dwh_timestamp IS NULL) THEN
     -- No facts for this date, start from beginning of day
     max_note_on_dwh_timestamp := start_of_day;
     use_equals := TRUE; -- Process all comments from start of day (>=)
    ELSIF (max_note_on_dwh_timestamp = start_of_day) THEN
     -- Timestamp is at start of day, use >= to catch all comments
     use_equals := TRUE;
    ELSE
     -- Timestamp is later in the day, only process new comments after it
     use_equals := FALSE;
    END IF;


   -- Gets the number of notes that have not being processed on the new date
   -- being processed.
   -- Filter by max_note_id_snapshot to ensure consistency
   -- OPTIMIZATION: Use timestamp range instead of DATE() to allow index usage on FDW
    SELECT /* Notes-staging */ COUNT(1)
     INTO qty_notes_on_date
    FROM public.note_comments
    WHERE created_at >= max_processed_date::TIMESTAMP
     AND created_at < (max_processed_date + INTERVAL '1 day')::TIMESTAMP
     AND created_at > max_note_on_dwh_timestamp
     AND note_id <= max_note_id_snapshot;
--qty_notes_on_date;

    -- Process notes for the new date with appropriate m_equals value
    CALL staging.process_notes_at_date(max_note_on_dwh_timestamp,
      qty_dwh_notes, use_equals);
   ELSE
    -- There are comments not processed on the DHW for the currently processing
    -- day.
--qty_notes_on_date;

    CALL staging.process_notes_at_date(max_note_on_dwh_timestamp,
      qty_dwh_notes, TRUE);
   END IF;
--max_note_on_dwh_timestamp, qty_notes_on_date;
  END LOOP;
--max_note_action_date;

  -- Restore original statement_timeout
  EXECUTE format('SET LOCAL statement_timeout = %L', original_statement_timeout);
 END
$proc$
;
COMMENT ON PROCEDURE staging.process_notes_actions_into_dwh IS
  'Processes all non-processes notes';

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'All staging objects created' AS Task;
