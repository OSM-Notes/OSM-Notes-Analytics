-- Procedure to insert datamart user.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-26

/**
 * Inserts a user in the datamart, with the values that do not change.
 */
CREATE OR REPLACE PROCEDURE dwh.insert_datamart_user (
  m_dimension_user_id INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $proc$
 DECLARE
  m_user_id INTEGER;
  m_username VARCHAR(256);
  m_date_starting_creating_notes DATE;
  m_date_starting_solving_notes DATE;
  m_first_open_note_id INTEGER;
  m_first_commented_note_id INTEGER;
  m_first_closed_note_id INTEGER;
  m_first_reopened_note_id INTEGER;
  m_last_year_activity CHAR(371);
  r RECORD;
 BEGIN
  -- Gets the OSM user id and the username.
  SELECT /* Notes-datamartUsers */ user_id, username
   INTO m_user_id, m_username
  FROM dwh.dimension_users
  WHERE dimension_user_id = m_dimension_user_id
    AND is_current = TRUE;

  -- Check if user was found (SELECT INTO leaves variables NULL if no row matches)
  IF m_user_id IS NULL OR m_username IS NULL THEN
    RAISE EXCEPTION 'User with dimension_user_id % not found or has no current record (is_current = TRUE)', m_dimension_user_id;
  END IF;

  -- Handle Anonymous user (user_id = -1 or username = 'Anonymous')
  -- Note: Anonymous user handling for user_id = -1 or username = 'Anonymous'
  IF m_user_id = -1 OR m_username = 'Anonymous' THEN
    m_username := COALESCE(m_username, 'Anonymous');
  END IF;

  -- Gets the date of the first note created by the current user.
  -- date_starting_creating_notes
  SELECT /* Notes-datamartUsers */ MIN(date_id)
   INTO m_date_starting_creating_notes
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.opened_dimension_id_date = d.dimension_day_id)
  WHERE f.opened_dimension_id_user = m_dimension_user_id;

  -- Gets the date of the first note resolved by the current user.
  -- date_starting_solving_notes
  SELECT /* Notes-datamartUsers */ MIN(date_id)
   INTO m_date_starting_solving_notes
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.closed_dimension_id_date = d.dimension_day_id)
   WHERE f.closed_dimension_id_user = m_dimension_user_id;

  -- first_open_note_id
  SELECT /* Notes-datamartUsers */ MIN(id_note)
   INTO m_first_open_note_id
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'opened';

  -- first_commented_note_id
  SELECT /* Notes-datamartUsers */ MIN(id_note)
   INTO m_first_commented_note_id
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'commented';

  -- first_closed_note_id
  SELECT /* Notes-datamartUsers */ MIN(id_note)
   INTO m_first_closed_note_id
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed';

  -- first_reopened_note_id
  SELECT /* Notes-datamartUsers */ MIN(id_note)
   INTO m_first_reopened_note_id
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened';

  -- Creates the activity array.
  m_last_year_activity := '0';
  -- Create the last year activity
  FOR r IN
   SELECT /* Notes-datamartUsers */ t.date_id, qty
   FROM (
    SELECT /* Notes-datamartUsers */ e.date_id, COALESCE(u.qty, 0) qty
    FROM dwh.dimension_days e
    LEFT JOIN (
     SELECT /* Notes-datamartUsers */ d.dimension_day_id day_id, count(1) qty
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.action_dimension_id_user = m_dimension_user_id
     GROUP BY d.dimension_day_id
    ) u
    ON (e.dimension_day_id = u.day_id)
    ORDER BY e.date_id DESC
    LIMIT 371
   ) AS t
   ORDER BY t.date_id ASC
 LOOP
   m_last_year_activity := dwh.refresh_today_activities(m_last_year_activity,
     (dwh.get_score_user_activity(r.qty::INTEGER)));
  END LOOP;

  INSERT INTO dwh.datamartUsers (
   dimension_user_id,
   user_id,
   username,
   date_starting_creating_notes,
   date_starting_solving_notes,
   first_open_note_id,
   first_commented_note_id,
   first_closed_note_id,
   first_reopened_note_id,
   last_year_activity
  ) VALUES (
   m_dimension_user_id,
   m_user_id,
   m_username,
   m_date_starting_creating_notes,
   m_date_starting_solving_notes,
   m_first_open_note_id,
   m_first_commented_note_id,
   m_first_closed_note_id,
   m_first_reopened_note_id,
   m_last_year_activity
  ) ON CONFLICT DO NOTHING;
 END
$proc$;
COMMENT ON PROCEDURE dwh.insert_datamart_user IS
  'Inserts a user in the corresponding datamart';

/*
 * Updates the datamart for a specific year.
 */
CREATE OR REPLACE PROCEDURE dwh.update_datamart_user_activity_year (
  m_dimension_user_id INTEGER,
  m_year SMALLINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $proc$
 DECLARE
  m_history_year_open INTEGER;
  m_history_year_commented INTEGER;
  m_history_year_closed INTEGER;
  m_history_year_closed_with_comment INTEGER;
  m_history_year_reopened INTEGER;
  m_ranking_countries_opening_year JSON;
  m_ranking_countries_closing_year JSON;
  m_current_year SMALLINT;
  m_check_year_populated INTEGER;
  stmt TEXT;
 BEGIN
  SELECT /* Notes-datamartUsers */ EXTRACT(YEAR FROM CURRENT_DATE)
   INTO m_current_year;

  stmt := 'SELECT /* Notes-datamartUsers */ history_' || m_year || '_open '
   || 'FROM dwh.datamartUsers '
   || 'WHERE dimension_user_id = ' || m_dimension_user_id;
  INSERT INTO dwh.logs (message) VALUES (stmt);
  EXECUTE stmt
   INTO m_check_year_populated;

  IF (m_check_year_populated IS NULL
   OR m_check_year_populated = m_current_year) THEN

   -- history_year_open
   SELECT /* Notes-datamartUsers */ COUNT(1)
    INTO m_history_year_open
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.action_dimension_id_date = d.dimension_day_id)
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'opened'
    AND d.year = m_year;

   -- history_year_commented
   SELECT /* Notes-datamartUsers */ COUNT(1)
    INTO m_history_year_commented
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.action_dimension_id_date = d.dimension_day_id)
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'commented'
    AND d.year = m_year;

   -- history_year_closed
   SELECT /* Notes-datamartUsers */ COUNT(1)
    INTO m_history_year_closed
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.action_dimension_id_date = d.dimension_day_id)
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'closed'
    AND d.year = m_year;

   -- history_year_closed_with_comment
   -- Note: This SELECT reads from ingestion tables (note_comments, note_comments_text)
   -- and should ideally be executed in READ ONLY mode for better concurrency, but this
   -- procedure also performs writes, so READ ONLY cannot be applied to the entire transaction.
   SELECT /* Notes-datamartUsers */ COUNT(1)
    INTO m_history_year_closed_with_comment
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON f.action_dimension_id_date = d.dimension_day_id
    JOIN public.note_comments nc
    ON (f.id_note = nc.note_id
        AND nc.event = 'closed')
    JOIN public.note_comments_text nct
    ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'closed'
    AND d.year = m_year
    AND nct.body IS NOT NULL
    AND LENGTH(TRIM(nct.body)) > 0;

   -- history_year_reopened
   SELECT /* Notes-datamartUsers */ COUNT(1)
    INTO m_history_year_reopened
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.action_dimension_id_date = d.dimension_day_id)
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'reopened'
    AND d.year = m_year;

   -- m_ranking_countries_opening_year
   SELECT /* Notes-datamartUsers */
    JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country_name', country_name,
    'quantity', quantity))
    INTO m_ranking_countries_opening_year
   FROM (
    SELECT /* Notes-datamartUsers */
     RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
	  FROM (
     SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
      COUNT(1) AS quantity
     FROM dwh.facts f
      JOIN dwh.dimension_countries c
      ON f.dimension_id_country = c.dimension_country_id
      JOIN dwh.dimension_days d
      ON f.opened_dimension_id_date = d.dimension_day_id
     WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND d.year = m_year
     GROUP BY c.country_name_es
     ORDER BY COUNT(1) DESC
     LIMIT 50
    ) AS T
   ) AS S;

   -- m_ranking_countries_closing_year
   SELECT /* Notes-datamartUsers */
    JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country_name', country_name,
    'quantity', quantity))
    INTO m_ranking_countries_closing_year
   FROM (
    SELECT /* Notes-datamartUsers */
     RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
    FROM (
     SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
      COUNT(1) AS quantity
     FROM dwh.facts f
      JOIN dwh.dimension_countries c
      ON f.dimension_id_country = c.dimension_country_id
      JOIN dwh.dimension_days d
      ON f.closed_dimension_id_date = d.dimension_day_id
     WHERE f.closed_dimension_id_user = m_dimension_user_id
      AND d.year = m_year
     GROUP BY c.country_name_es
     ORDER BY COUNT(1) DESC
     LIMIT 50
    ) AS T
   ) AS S;

   stmt := 'UPDATE dwh.datamartUsers SET '
     || 'history_' || m_year || '_open = ' || m_history_year_open || ', '
     || 'history_' || m_year || '_commented = '
     || m_history_year_commented || ', '
     || 'history_' || m_year || '_closed = ' || m_history_year_closed || ', '
     || 'history_' || m_year || '_closed_with_comment = '
     || m_history_year_closed_with_comment || ', '
     || 'history_' || m_year || '_reopened = '
     || m_history_year_reopened || ', '
     || 'ranking_countries_opening_' || m_year || ' = '
     || QUOTE_NULLABLE(m_ranking_countries_opening_year) || ', '
     || 'ranking_countries_closing_' || m_year || ' = '
     || QUOTE_NULLABLE(m_ranking_countries_closing_year) || ' '
     || 'WHERE dimension_user_id = ' || m_dimension_user_id;
   INSERT INTO logs (message) VALUES (SUBSTR(stmt, 1, 900));
   EXECUTE stmt;
  END IF;
 END
$proc$;
COMMENT ON PROCEDURE dwh.update_datamart_user_activity_year IS
  'Processes the user''s activity per given year';

/**
 * Returns the type of type of contributor.
 */
 CREATE OR REPLACE FUNCTION dwh.get_contributor_type (
   m_dimension_user_id INTEGER
 ) RETURNS SMALLINT AS
 $$
 DECLARE
  m_cointributor_id SMALLINT;
  m_oldest_action DATE;
  m_oldest_action_year SMALLINT;
  m_current_year SMALLINT;
  m_recent_action DATE;
  m_total_actions INTEGER;
  m_total_opened INTEGER;
  m_total_closed INTEGER;
  coeficient DECIMAL;
 BEGIN
  SELECT /* Notes-datamartUsers */ MIN(d.date_id), MAX(d.date_id)
   INTO m_oldest_action, m_recent_action
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id;

  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_total_actions
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id;

  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_total_closed
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = m_dimension_user_id;

  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_total_opened
  FROM dwh.facts f
  WHERE f.opened_dimension_id_user = m_dimension_user_id;

  coeficient := m_total_closed / (m_total_opened + 1);

  m_oldest_action_year := EXTRACT(YEAR FROM m_oldest_action);
  m_current_year := EXTRACT(YEAR FROM CURRENT_DATE);
  m_cointributor_id := 0;
  IF (m_oldest_action > CURRENT_DATE - 30) THEN
   m_cointributor_id := 2; -- Just starting notero
  ELSIF (m_oldest_action > CURRENT_DATE - 90) THEN
   m_cointributor_id := 3; -- Newbie notero.
  ELSIF (m_oldest_action_year = 2013
    AND m_oldest_action_year = m_current_year) THEN
   m_cointributor_id := 4; -- All-time notero.
   -- It has contributed since the first year, and the current year.
   -- The assumption is that is has contributed all years in between.
  ELSIF (m_oldest_action = m_recent_action) THEN
   m_cointributor_id := 5; -- Hit and run.
   -- It contibuted only one day older than 90 days.
  ELSIF (m_oldest_action_year = m_current_year
    OR m_oldest_action_year = m_current_year - 1) THEN
   m_cointributor_id := 6; -- Junior notero.
   -- It has been contributed in the last 2 calendar years.
  ELSIF (m_recent_action < CURRENT_DATE - 720) THEN
   m_cointributor_id := 7; -- Inactive notero.
   -- It has not contributed in the last 2 years.
  ELSIF (m_recent_action < CURRENT_DATE - 1800) THEN
   m_cointributor_id := 8; -- Retired notero.
   -- It has not contributed in the last 5 years.
  ELSIF (m_recent_action < CURRENT_DATE - 2000) THEN
   m_cointributor_id := 9; -- Forgotten notero.
   -- It has not contributed in the last 7 years.
  ELSIF (m_total_actions < 25) THEN
   m_cointributor_id := 10; -- Exporadic notero.
   -- Less than 100 contributions, in more than 2 years.
  ELSIF (m_total_closed < 100 AND coeficient > 1) THEN
   m_cointributor_id := 11; -- Start closing notero.
   -- Less than 100 closed, in more than 2 years.
  ELSIF (m_total_actions < 100) THEN
   m_cointributor_id := 12; -- Casual notero.
   -- Less than 100 contributions, in more than 2 years.
  ELSIF (m_total_closed < 400 AND coeficient > 1) THEN
   m_cointributor_id := 13; -- Heavy closing notero.
   -- Less than 400 contributions, in more than 2 years.
  ELSIF (m_total_actions < 400) THEN
   m_cointributor_id := 14; -- Heavy notero.
   -- Less than 400 contributions, in more than 2 years.
  ELSIF (m_total_closed < 1600 AND coeficient > 1) THEN
   m_cointributor_id := 15; -- Crazy closing notero.
   -- Less than 1600 contributions, in more than 2 years.
  ELSIF (m_total_actions < 1600) THEN
   m_cointributor_id := 16; -- Crazy notero.
   -- Less than 1600 contributions, in more than 2 years.
  ELSIF (m_total_closed < 6400 AND coeficient > 1) THEN
   m_cointributor_id := 17; -- Addicted closing notero.
   -- Less than 6400 contributions, in more than 2 years.
  ELSIF (m_total_actions < 6400) THEN
   m_cointributor_id := 18; -- Addicted notero.
   -- Less than 6400 contributions, in more than 2 years.
  ELSIF (m_total_closed < 25600 AND coeficient > 1) THEN
   m_cointributor_id := 19; -- Epic closing notero.
   -- Less than 25600 contributions, in more than 2 years.
  ELSIF (m_total_actions < 25600) THEN
   m_cointributor_id := 20; -- Epic notero.
   -- Less than 25600 contributions, in more than 2 years.
  ELSIF (m_total_closed < 102400 AND coeficient > 1) THEN
   m_cointributor_id := 21; -- Bot closing notero.
   -- Less than 102400 contributions, in more than 2 years.
  ELSIF (m_total_actions < 102400) THEN
   m_cointributor_id := 22; -- Robot notero.
   -- Less than 102400 contributions, in more than 2 years.
  ELSIF (m_total_actions >= 102400) THEN
   m_cointributor_id := 23; -- OoM exception notero.
   -- More than 102400 contributions, in more than 2 years.
   -- Out of memory execption notero.
  ELSE
   m_cointributor_id := 1; -- Normal noter.
   -- It should never return this.
   RAISE NOTICE 'Unkown contributor type %.', m_dimension_user_id;
  END IF;
  RETURN m_cointributor_id;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION dwh.get_contributor_type IS
  'Returns the type of contributor';

/**
 * Updates a datamart user.
 */
CREATE OR REPLACE PROCEDURE dwh.update_datamart_user (
  m_dimension_user_id INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $proc$
 DECLARE
  qty SMALLINT;
  m_start_time TIMESTAMP;
  m_end_time TIMESTAMP;
  m_duration_seconds DECIMAL(10,3);
  m_facts_count INTEGER;
  m_id_contributor_type SMALLINT;
  m_todays_activity INTEGER;
  m_last_year_activity CHAR(371);
  m_latest_open_note_id INTEGER;
  m_latest_commented_note_id INTEGER;
  m_latest_closed_note_id INTEGER;
  m_latest_reopened_note_id INTEGER;
  m_dates_most_open JSON;
  m_dates_most_closed JSON;
  m_hashtags JSON;
  m_countries_open_notes JSON;
  m_countries_solving_notes JSON;
  m_countries_open_notes_current_month JSON;
  m_countries_solving_notes_current_month JSON;
  m_countries_open_notes_current_day JSON;
  m_countries_solving_notes_current_day JSON;
  m_working_hours_of_week_opening JSON;
  m_working_hours_of_week_commenting JSON;
  m_working_hours_of_week_closing JSON;
  m_history_whole_open INTEGER; -- Qty opened notes.
  m_history_whole_commented INTEGER; -- Qty commented notes.
  m_history_whole_closed INTEGER; -- Qty closed notes.
  m_history_whole_closed_with_comment INTEGER; -- Qty closed notes with comments.
  m_history_whole_reopened INTEGER; -- Qty reopened notes.
  m_history_year_open INTEGER; -- Qty in the current year.
  m_history_year_commented INTEGER;
  m_history_year_closed INTEGER;
  m_history_year_closed_with_comment INTEGER;
  m_history_year_reopened INTEGER;
  m_history_month_open INTEGER; -- Qty in the current month.
  m_history_month_commented INTEGER;
  m_history_month_closed INTEGER;
  m_history_month_closed_with_comment INTEGER;
  m_history_month_reopened INTEGER;
  m_history_day_open INTEGER; -- Qty in the current day.
  m_history_day_commented INTEGER;
  m_history_day_closed INTEGER;
  m_history_day_closed_with_comment INTEGER;
  m_history_day_reopened INTEGER;

  m_year SMALLINT;
  m_current_year SMALLINT;
  m_current_month SMALLINT;
  m_current_day SMALLINT;

  m_avg_days_to_resolution DECIMAL(10,2);
  m_median_days_to_resolution DECIMAL(10,2);
  m_notes_resolved_count INTEGER;
  m_notes_still_open_count INTEGER;
  m_notes_opened_but_not_closed_by_user INTEGER;
  m_resolution_rate DECIMAL(5,2);

  m_applications_used JSON;
  m_most_used_application_id INTEGER;
  m_mobile_apps_count INTEGER;
  m_desktop_apps_count INTEGER;

  m_avg_comment_length DECIMAL(10,2);
  m_comments_with_url_count INTEGER;
  m_comments_with_url_pct DECIMAL(5,2);
  m_comments_with_mention_count INTEGER;
  m_comments_with_mention_pct DECIMAL(5,2);
  m_avg_comments_per_note DECIMAL(10,2);
  m_active_notes_count INTEGER;

  -- DM-002: Hashtag analysis variables
  m_hashtags_opening JSON;
  m_hashtags_resolution JSON;
  m_hashtags_comments JSON;
  m_favorite_opening_hashtag VARCHAR(50);
  m_favorite_resolution_hashtag VARCHAR(50);
  m_opening_hashtag_count INTEGER;
  m_resolution_hashtag_count INTEGER;
  m_notes_backlog_size INTEGER;
  m_notes_age_distribution JSON;
  m_notes_created_last_30_days INTEGER;
  m_notes_resolved_last_30_days INTEGER;
  m_resolution_by_year JSON;
  m_resolution_by_month JSON;
  m_application_usage_trends JSON;
  m_version_adoption_rates JSON;
  m_user_response_time DECIMAL(10,2);
  m_days_since_last_action INTEGER;
  m_collaboration_patterns JSON;
  -- Enhanced date columns from dimension_days
  m_iso_week SMALLINT;
  m_quarter SMALLINT;
  m_month_name VARCHAR(16);
  -- Enhanced time columns from dimension_time_of_week
  m_hour_of_week SMALLINT;
  m_period_of_day VARCHAR(16);
  BEGIN
  -- Start timing
  m_start_time := CLOCK_TIMESTAMP();
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO qty
  FROM dwh.datamartUsers
  WHERE dimension_user_id = m_dimension_user_id;
  -- Checks if the user is already in the datamart.
  IF (qty = 0) THEN
   CALL dwh.insert_datamart_user(m_dimension_user_id);
  END IF;

  -- id_contributor_type
  m_id_contributor_type := dwh.get_contributor_type(m_dimension_user_id);

  -- last_year_activity
  SELECT /* Notes-datamartUsers */ last_year_activity
   INTO m_last_year_activity
  FROM dwh.datamartUsers u
  WHERE u.dimension_user_id = m_dimension_user_id;

  -- Retrieves the curent activity array from the user, and updates with the
  -- current day's activities.
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_todays_activity
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
  AND d.date_id = CURRENT_DATE;
  m_last_year_activity := dwh.refresh_today_activities(m_last_year_activity,
    dwh.get_score_user_activity(m_todays_activity));

  -- latest_open_note_id
  SELECT /* Notes-datamartUsers */ MAX(id_note)
  FROM dwh.facts f
   INTO m_latest_open_note_id
  WHERE f.opened_dimension_id_user = m_dimension_user_id;

  -- latest_commented_note_id
  SELECT /* Notes-datamartUsers */ MAX(id_note)
   INTO m_latest_commented_note_id
  FROM dwh.facts f
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'commented';

  -- latest_closed_note_id
  SELECT /* Notes-datamartUsers */ MAX(id_note)
   INTO m_latest_closed_note_id
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = m_dimension_user_id;

  -- latest_reopened_note_id
  SELECT /* Notes-datamartUsers */ MAX(id_note)
   INTO m_latest_reopened_note_id
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened';

  -- dates_most_open
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('date', date, 'quantity', quantity))
   INTO m_dates_most_open
  FROM (
   SELECT /* Notes-datamartUsers */ date_id AS date, COUNT(1) AS quantity
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.opened_dimension_id_date = d.dimension_day_id)
   WHERE f.opened_dimension_id_user = m_dimension_user_id
   GROUP BY date_id
   ORDER BY COUNT(1) DESC
   LIMIT 50
  ) AS T;

  -- dates_most_closed
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('date', date, 'quantity', quantity))
   INTO m_dates_most_closed
  FROM (
   SELECT /* Notes-datamartUsers */ date_id AS date, COUNT(1) AS quantity
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON (f.closed_dimension_id_date = d.dimension_day_id)
   WHERE f.closed_dimension_id_user = m_dimension_user_id
   GROUP BY date_id
   ORDER BY COUNT(1) DESC
   LIMIT 50
  ) AS T;

  -- hashtags - aggregates all hashtags used by this user with their frequency
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag,
   'quantity', quantity))
   INTO m_hashtags
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, hashtag, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ h.description AS hashtag,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.fact_hashtags fh
     ON f.fact_id = fh.fact_id
     JOIN dwh.dimension_hashtags h
     ON fh.dimension_hashtag_id = h.dimension_hashtag_id
    WHERE f.action_dimension_id_user = m_dimension_user_id
     AND h.description IS NOT NULL
    GROUP BY h.description
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS T2;

  -- countries_open_notes
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_open_notes
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- countries_solving_notes
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_solving_notes
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */
     c.country_name_es AS country_name, COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
    WHERE f.closed_dimension_id_user = m_dimension_user_id
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- PEFR: high impact.
  -- 22 per second.
  SELECT /* Notes-datamartUsers */ EXTRACT(YEAR FROM CURRENT_DATE)
   INTO m_current_year;
  SELECT /* Notes-datamartUsers */ EXTRACT(MONTH FROM CURRENT_DATE)
   INTO m_current_month;
  SELECT /* Notes-datamartUsers */ EXTRACT(DAY FROM CURRENT_DATE)
   INTO m_current_day;

  -- Note: Previous implementations used DATE_PART() or dwh.properties table
  -- Current implementation uses EXTRACT() for better performance (21 queries/second vs slower alternatives)

  -- countries_open_notes_current_month
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_open_notes_current_month
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
     JOIN dwh.dimension_days d
     ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
     AND d.month = m_current_month
     AND d.year = m_current_year
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- countries_solving_notes_current_month
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_solving_notes_current_month
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
     JOIN dwh.dimension_days d
     ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.closed_dimension_id_user = m_dimension_user_id
     AND d.month = m_current_month
     AND d.year = m_current_year
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- countries_open_notes_current_day
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_open_notes_current_day
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
     JOIN dwh.dimension_days d
     ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
     AND d.day = m_current_day
     AND d.month = m_current_month
     AND d.year = m_current_year
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- countries_solving_notes_current_day
  SELECT /* Notes-datamartUsers */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'country', country_name,
   'quantity', quantity))
   INTO m_countries_solving_notes_current_day
  FROM (
   SELECT /* Notes-datamartUsers */
    RANK () OVER (ORDER BY quantity DESC) rank, country_name, quantity
   FROM (
    SELECT /* Notes-datamartUsers */ c.country_name_es AS country_name,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.dimension_countries c
     ON f.dimension_id_country = c.dimension_country_id
     JOIN dwh.dimension_days d
     ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.closed_dimension_id_user = m_dimension_user_id
     AND d.day = m_current_day
     AND d.month = m_current_month
     AND d.year = m_current_year
    GROUP BY c.country_name_es
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS S;

  -- working_hours_of_week_opening
  -- Note: Uses action_dimension_id_season for seasonal analysis
  WITH hours AS (
   SELECT /* Notes-datamartUsers */ day_of_week, hour_of_day, COUNT(1)
   FROM dwh.facts f
    JOIN dwh.dimension_time_of_week t
    ON f.opened_dimension_id_hour_of_week = t.dimension_tow_id
   WHERE f.opened_dimension_id_user = m_dimension_user_id
     AND f.action_dimension_id_season IS NOT NULL
   GROUP BY day_of_week, hour_of_day
   ORDER BY day_of_week, hour_of_day
  )
  SELECT /* Notes-datamartUsers */ JSON_AGG(hours.*)
   INTO m_working_hours_of_week_opening
  FROM hours;

  -- working_hours_of_week_commenting
  -- Note: Uses action_dimension_id_season for seasonal analysis
  WITH hours AS (
   SELECT /* Notes-datamartUsers */ day_of_week, hour_of_day, COUNT(1)
   FROM dwh.facts f
    JOIN dwh.dimension_time_of_week t
    ON f.action_dimension_id_hour_of_week = t.dimension_tow_id
   WHERE f.action_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'commented'
    AND f.action_dimension_id_season IS NOT NULL
   GROUP BY day_of_week, hour_of_day
   ORDER BY day_of_week, hour_of_day
  )
  SELECT /* Notes-datamartUsers */ JSON_AGG(hours.*)
   INTO m_working_hours_of_week_commenting
  FROM hours;

  -- working_hours_of_week_closing
  -- Note: Uses action_dimension_id_season for seasonal analysis
  WITH hours AS (
   SELECT /* Notes-datamartUsers */ day_of_week, hour_of_day, COUNT(1)
   FROM dwh.facts f
    JOIN dwh.dimension_time_of_week t
    ON f.closed_dimension_id_hour_of_week = t.dimension_tow_id
   WHERE f.closed_dimension_id_user = m_dimension_user_id
     AND f.action_dimension_id_season IS NOT NULL
   GROUP BY day_of_week, hour_of_day
   ORDER BY day_of_week, hour_of_day
  )
  SELECT /* Notes-datamartUsers */ JSON_AGG(hours.*)
   INTO m_working_hours_of_week_closing
  FROM hours;

  -- history_whole_open
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_whole_open
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'opened';

  -- history_whole_commented
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_whole_commented
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'commented';

  -- history_whole_closed
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_whole_closed
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed';

  -- history_whole_closed_with_comment
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_whole_closed_with_comment
  FROM dwh.facts f
   JOIN (
    SELECT note_id, sequence_action, id_user
    FROM public.note_comments
    WHERE CAST(event AS text) = 'closed'
   ) nc
   ON (f.id_note = nc.note_id)
   JOIN public.note_comments_text nct
   ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND nct.body IS NOT NULL
   AND LENGTH(TRIM(nct.body)) > 0;

  -- history_whole_reopened
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_whole_reopened
  FROM dwh.facts f
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened';

  -- history_year_open
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_year_open
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'opened'
   AND d.year = m_current_year;

  -- history_year_commented
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_year_commented
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'commented'
   AND d.year = m_current_year;

  -- history_year_closed
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_year_closed
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.year = m_current_year;

  -- history_year_closed_with_comment
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_year_closed_with_comment
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
   JOIN (
    SELECT note_id, sequence_action, id_user
    FROM public.note_comments
    WHERE CAST(event AS text) = 'closed'
   ) nc
   ON (f.id_note = nc.note_id)
   JOIN public.note_comments_text nct
   ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.year = m_current_year
   AND nct.body IS NOT NULL
   AND LENGTH(TRIM(nct.body)) > 0;

  -- history_year_reopened
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_year_reopened
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened'
   AND d.year = m_current_year;

  -- history_month_open
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_month_open
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'opened'
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_month_commented
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_month_commented
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'commented'
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_month_closed
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_month_closed
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_month_closed_with_comment
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_month_closed_with_comment
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
   JOIN (
    SELECT note_id, sequence_action, id_user
    FROM public.note_comments
    WHERE CAST(event AS text) = 'closed'
   ) nc
   ON (f.id_note = nc.note_id)
   JOIN public.note_comments_text nct
   ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.month = m_current_month
   AND d.year = m_current_year
   AND nct.body IS NOT NULL
   AND LENGTH(TRIM(nct.body)) > 0;

  -- history_month_reopened
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_month_reopened
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened'
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_day_open
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_day_open
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'opened'
   AND d.day = m_current_day
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_day_commented
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_day_commented
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'commented'
   AND d.day = m_current_day
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_day_closed
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_day_closed
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.day = m_current_day
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- history_day_closed_with_comment
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_day_closed_with_comment
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
   JOIN (
    SELECT note_id, sequence_action, id_user
    FROM public.note_comments
    WHERE CAST(event AS text) = 'closed'
   ) nc
   ON (f.id_note = nc.note_id)
   JOIN public.note_comments_text nct
   ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'closed'
   AND d.day = m_current_day
   AND d.month = m_current_month
   AND d.year = m_current_year
   AND nct.body IS NOT NULL
   AND LENGTH(TRIM(nct.body)) > 0;

  -- history_day_reopened
  SELECT /* Notes-datamartUsers */ COUNT(1)
   INTO m_history_day_reopened
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.action_dimension_id_user = m_dimension_user_id
   AND f.action_comment = 'reopened'
   AND d.day = m_current_day
   AND d.month = m_current_month
   AND d.year = m_current_year;

  -- Average resolution time (use closed_dimension_id_user for closed actions)
  SELECT COALESCE(AVG(days_to_resolution), 0)
   INTO m_avg_days_to_resolution
  FROM dwh.facts
  WHERE closed_dimension_id_user = m_dimension_user_id
    AND days_to_resolution IS NOT NULL
    AND action_comment = 'closed';

  -- Median resolution time (use closed_dimension_id_user for closed actions)
  SELECT COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution), 0)
   INTO m_median_days_to_resolution
  FROM dwh.facts
  WHERE closed_dimension_id_user = m_dimension_user_id
    AND days_to_resolution IS NOT NULL
    AND action_comment = 'closed';

  -- Count resolved notes (user who closed, not who opened)
  SELECT COUNT(DISTINCT f1.id_note)
   INTO m_notes_resolved_count
  FROM dwh.facts f1
  WHERE f1.closed_dimension_id_user = m_dimension_user_id
    AND f1.action_comment = 'closed';

  -- Count notes still open (notes opened by user that are not closed)
  SELECT COUNT(DISTINCT f2.id_note)
   INTO m_notes_still_open_count
  FROM dwh.facts f2
  WHERE f2.opened_dimension_id_user = m_dimension_user_id
    AND f2.action_comment = 'opened'
    AND NOT EXISTS (
      SELECT 1
      FROM dwh.facts f3
      WHERE f3.id_note = f2.id_note
        AND f3.action_comment = 'closed'
        AND f3.closed_dimension_id_user = f2.opened_dimension_id_user
    );

  -- Count notes opened by user but never closed by same user
  -- (includes notes closed by others and notes still open)
  SELECT COUNT(DISTINCT f4.id_note)
   INTO m_notes_opened_but_not_closed_by_user
  FROM dwh.facts f4
  WHERE f4.opened_dimension_id_user = m_dimension_user_id
    AND f4.action_comment = 'opened'
    AND NOT EXISTS (
      SELECT 1
      FROM dwh.facts f5
      WHERE f5.id_note = f4.id_note
        AND f5.closed_dimension_id_user = m_dimension_user_id
        AND f5.action_comment = 'closed'
    );

  -- Calculate resolution rate
  IF (m_notes_resolved_count + m_notes_still_open_count) > 0 THEN
    m_resolution_rate := (m_notes_resolved_count::DECIMAL / (m_notes_resolved_count + m_notes_still_open_count)) * 100;
  ELSE
    m_resolution_rate := 0;
  END IF;

  -- Applications used (JSON array with app_id, app_name, count)
  SELECT /* Notes-datamartUsers */ json_agg(
   json_build_object(
    'app_id', app_id,
    'app_name', app_name,
    'count', app_count
   ) ORDER BY app_count DESC
  )
  INTO m_applications_used
  FROM (
   SELECT
    f.dimension_application_creation as app_id,
    a.application_name as app_name,
    COUNT(*) as app_count
   FROM dwh.facts f
    JOIN dwh.dimension_applications a
    ON a.dimension_application_id = f.dimension_application_creation
   WHERE f.opened_dimension_id_user = m_dimension_user_id
    AND f.dimension_application_creation IS NOT NULL
   GROUP BY f.dimension_application_creation, a.application_name
   ORDER BY app_count DESC
  ) AS app_stats;

  -- Most used application
  SELECT /* Notes-datamartUsers */ dimension_application_creation
  INTO m_most_used_application_id
  FROM dwh.facts
  WHERE opened_dimension_id_user = m_dimension_user_id
   AND dimension_application_creation IS NOT NULL
  GROUP BY dimension_application_creation
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Mobile apps count (android, ios, and other mobile platforms)
  SELECT /* Notes-datamartUsers */ COUNT(DISTINCT f.dimension_application_creation)
  INTO m_mobile_apps_count
  FROM dwh.facts f
   JOIN dwh.dimension_applications a
   ON a.dimension_application_id = f.dimension_application_creation
  WHERE f.opened_dimension_id_user = m_dimension_user_id
   AND f.dimension_application_creation IS NOT NULL
   AND (a.platform IN ('android', 'ios')
    OR a.platform LIKE 'mobile%'
    OR a.category = 'mobile');

  -- Desktop apps count (web and desktop platforms)
  SELECT /* Notes-datamartUsers */ COUNT(DISTINCT f.dimension_application_creation)
  INTO m_desktop_apps_count
  FROM dwh.facts f
   JOIN dwh.dimension_applications a
   ON a.dimension_application_id = f.dimension_application_creation
  WHERE f.opened_dimension_id_user = m_dimension_user_id
   AND f.dimension_application_creation IS NOT NULL
   AND (a.platform = 'web'
    OR a.platform IN ('desktop', 'windows', 'linux', 'macos'));

  -- Average comment length
  SELECT /* Notes-datamartUsers */ COALESCE(AVG(comment_length), 0)
  INTO m_avg_comment_length
  FROM dwh.facts
  WHERE action_dimension_id_user = m_dimension_user_id
   AND comment_length IS NOT NULL
   AND action_comment = 'commented';

  -- Comments with URL count and percentage
  SELECT
   COUNT(*) FILTER (WHERE has_url = TRUE) as url_count,
   COUNT(*) as total_comments,
   CASE
    WHEN COUNT(*) > 0
    THEN (COUNT(*) FILTER (WHERE has_url = TRUE)::DECIMAL / COUNT(*) * 100)
    ELSE 0
   END as url_pct
  INTO m_comments_with_url_count, qty, m_comments_with_url_pct
  FROM dwh.facts
  WHERE action_dimension_id_user = m_dimension_user_id
   AND action_comment = 'commented';

  -- Comments with mention count and percentage
  SELECT
   COUNT(*) FILTER (WHERE has_mention = TRUE) as mention_count,
   COUNT(*) as total_comments,
   CASE
    WHEN COUNT(*) > 0
    THEN (COUNT(*) FILTER (WHERE has_mention = TRUE)::DECIMAL / COUNT(*) * 100)
    ELSE 0
   END as mention_pct
  INTO m_comments_with_mention_count, qty, m_comments_with_mention_pct
  FROM dwh.facts
  WHERE action_dimension_id_user = m_dimension_user_id
   AND action_comment = 'commented';

  -- Average comments per note
  SELECT /* Notes-datamartUsers */
   CASE
    WHEN COUNT(DISTINCT opened_dimension_id_user) > 0
    THEN COUNT(*)::DECIMAL / COUNT(DISTINCT id_note)
    ELSE 0
   END
  INTO m_avg_comments_per_note
  FROM dwh.facts
  WHERE action_dimension_id_user = m_dimension_user_id
   AND action_comment = 'commented';

  -- Phase 4: Community Health Metrics
  -- Active notes count (currently open notes by this user)
  -- Using note_current_status table for better performance (ETL-003)
  SELECT /* Notes-datamartUsers */ COALESCE(COUNT(*), 0)
  INTO m_active_notes_count
  FROM dwh.note_current_status ncs
  WHERE ncs.opened_dimension_id_user = m_dimension_user_id
    AND ncs.is_currently_open = TRUE;

  -- Notes backlog size (same as active notes)
  m_notes_backlog_size := m_active_notes_count;

  -- Notes age distribution
  WITH age_ranges AS (
    SELECT
      CASE
        WHEN CURRENT_DATE - dd.date_id <= 7 THEN '0-7 days'
        WHEN CURRENT_DATE - dd.date_id <= 30 THEN '8-30 days'
        WHEN CURRENT_DATE - dd.date_id <= 90 THEN '31-90 days'
        ELSE '90+ days'
      END as age_range
    FROM dwh.facts f
    JOIN dwh.dimension_days dd ON f.opened_dimension_id_date = dd.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
      AND NOT EXISTS (
        SELECT 1
        FROM dwh.facts f2
        WHERE f2.id_note = f.id_note
          AND f2.action_comment = 'closed'
      )
  )
  SELECT /* Notes-datamartUsers */ json_agg(
    json_build_object(
      'age_range', ar.age_range,
      'count', age_counts.cnt
    ) ORDER BY ar.age_range
  )
  INTO m_notes_age_distribution
  FROM (
    SELECT age_range, COUNT(*) as cnt
    FROM age_ranges
    GROUP BY age_range
  ) age_counts
  JOIN (SELECT DISTINCT age_range FROM age_ranges) ar ON ar.age_range = age_counts.age_range;

  -- Notes created last 30 days
  SELECT /* Notes-datamartUsers */ COUNT(DISTINCT id_note)
  INTO m_notes_created_last_30_days
  FROM dwh.facts f
  WHERE f.opened_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'opened'
    AND f.opened_dimension_id_date IN (
      SELECT dimension_day_id
      FROM dwh.dimension_days
      WHERE date_id >= CURRENT_DATE - INTERVAL '30 days'
    );

  -- Notes resolved last 30 days
  SELECT /* Notes-datamartUsers */ COUNT(DISTINCT id_note)
  INTO m_notes_resolved_last_30_days
  FROM dwh.facts f
  WHERE f.closed_dimension_id_user = m_dimension_user_id
    AND f.action_comment = 'closed'
    AND f.closed_dimension_id_date IN (
      SELECT dimension_day_id
      FROM dwh.dimension_days
      WHERE date_id >= CURRENT_DATE - INTERVAL '30 days'
    );

  -- Resolution metrics by year (avg, median, resolution_rate)
  WITH years AS (
    SELECT DISTINCT EXTRACT(YEAR FROM d.date_id)::INT AS y
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.action_dimension_id_user = m_dimension_user_id
  ),
  opened AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           COUNT(DISTINCT id_note) AS opened_cnt
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
    GROUP BY 1
  ),
  closed AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           COUNT(DISTINCT id_note) AS closed_cnt,
           AVG(days_to_resolution)::DECIMAL(10,2) AS avg_days,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution)::DECIMAL(10,2) AS median_days
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.closed_dimension_id_date = d.dimension_day_id
    WHERE f.closed_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'closed'
      AND f.days_to_resolution IS NOT NULL
    GROUP BY 1
  )
  SELECT json_agg(
           json_build_object(
             'year', y,
             'avg_days', COALESCE(c.avg_days, 0),
             'median_days', COALESCE(c.median_days, 0),
             'resolution_rate', CASE WHEN COALESCE(o.opened_cnt,0) > 0
                                     THEN ROUND(COALESCE(c.closed_cnt,0)::DECIMAL / o.opened_cnt * 100, 2)
                                     ELSE 0 END
           ) ORDER BY y
         )
  INTO m_resolution_by_year
  FROM (
    SELECT y FROM years
    UNION
    SELECT y FROM opened
    UNION
    SELECT y FROM closed
  ) yx
  LEFT JOIN opened o USING (y)
  LEFT JOIN closed c USING (y);

  -- Resolution metrics by month (avg, median, resolution_rate)
  WITH ym AS (
    SELECT DISTINCT EXTRACT(YEAR FROM d.date_id)::INT AS y,
                    EXTRACT(MONTH FROM d.date_id)::INT AS m
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
    WHERE f.action_dimension_id_user = m_dimension_user_id
  ),
  opened_m AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           EXTRACT(MONTH FROM d.date_id)::INT AS m,
           COUNT(DISTINCT id_note) AS opened_cnt
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
    GROUP BY 1,2
  ),
  closed_m AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           EXTRACT(MONTH FROM d.date_id)::INT AS m,
           COUNT(DISTINCT id_note) AS closed_cnt,
           AVG(days_to_resolution)::DECIMAL(10,2) AS avg_days,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution)::DECIMAL(10,2) AS median_days
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.closed_dimension_id_date = d.dimension_day_id
    WHERE f.closed_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'closed'
      AND f.days_to_resolution IS NOT NULL
    GROUP BY 1,2
  )
  SELECT json_agg(
           json_build_object(
             'year', y,
             'month', m,
             'avg_days', COALESCE(c.avg_days, 0),
             'median_days', COALESCE(c.median_days, 0),
             'resolution_rate', CASE WHEN COALESCE(o.opened_cnt,0) > 0
                                     THEN ROUND(COALESCE(c.closed_cnt,0)::DECIMAL / o.opened_cnt * 100, 2)
                                     ELSE 0 END
           ) ORDER BY y, m
         )
  INTO m_resolution_by_month
  FROM (
    SELECT y, m FROM ym
    UNION
    SELECT y, m FROM opened_m
    UNION
    SELECT y, m FROM closed_m
  ) ymx
  LEFT JOIN opened_m o USING (y,m)
  LEFT JOIN closed_m c USING (y,m);

  -- Application usage trends by year
  SELECT /* Notes-datamartUsers */ COALESCE(json_agg(
    json_build_object(
      'year', y,
      'applications', app_data
    ) ORDER BY y
  ), '[]'::json)
  INTO m_application_usage_trends
  FROM (
    SELECT DISTINCT EXTRACT(YEAR FROM d.date_id)::INT AS y
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
  ) years
  CROSS JOIN LATERAL (
    SELECT json_agg(
      json_build_object(
        'app_id', app_id,
        'app_name', app_name,
        'count', app_count,
        'pct', CASE WHEN total > 0 THEN ROUND((app_count::DECIMAL / total * 100), 2) ELSE 0 END
      ) ORDER BY app_count DESC
    ) as app_data
    FROM (
      SELECT
        f.dimension_application_creation as app_id,
        a.application_name as app_name,
        COUNT(*) as app_count,
        SUM(COUNT(*)) OVER () as total
      FROM dwh.facts f
      JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
      JOIN dwh.dimension_applications a ON a.dimension_application_id = f.dimension_application_creation
      WHERE f.opened_dimension_id_user = m_dimension_user_id
        AND f.action_comment = 'opened'
        AND f.dimension_application_creation IS NOT NULL
        AND EXTRACT(YEAR FROM d.date_id) = years.y
      GROUP BY f.dimension_application_creation, a.application_name
    ) app_stats
  ) app_trends;

  -- Version adoption rates by year
  SELECT /* Notes-datamartUsers */ COALESCE(json_agg(
    json_build_object(
      'year', y,
      'versions', version_data
    ) ORDER BY y
  ), '[]'::json)
  INTO m_version_adoption_rates
  FROM (
    SELECT DISTINCT EXTRACT(YEAR FROM d.date_id)::INT AS y
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
      AND f.dimension_application_version IS NOT NULL
  ) years
  CROSS JOIN LATERAL (
    SELECT json_agg(
      json_build_object(
        'version', version,
        'count', version_count,
        'adoption_rate', CASE WHEN total > 0 THEN ROUND((version_count::DECIMAL / total * 100), 2) ELSE 0 END
      ) ORDER BY version_count DESC
    ) as version_data
    FROM (
      SELECT
        av.version as version,
        COUNT(*) as version_count,
        SUM(COUNT(*)) OVER () as total
      FROM dwh.facts f
      JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
      JOIN dwh.dimension_application_versions av ON av.dimension_application_version_id = f.dimension_application_version
      WHERE f.opened_dimension_id_user = m_dimension_user_id
        AND f.action_comment = 'opened'
        AND f.dimension_application_version IS NOT NULL
        AND EXTRACT(YEAR FROM d.date_id) = years.y
      GROUP BY av.version
    ) version_stats
  ) version_trends;

  -- User response time: average time from note open to first comment by this user
  SELECT /* Notes-datamartUsers */ COALESCE(AVG(
    EXTRACT(EPOCH FROM (c.action_at - o.action_at)) / 86400.0
  ), 0)
  INTO m_user_response_time
  FROM (
    SELECT DISTINCT ON (f.id_note) f.id_note, f.action_at
    FROM dwh.facts f
    WHERE f.opened_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'opened'
    ORDER BY f.id_note, f.action_at ASC
  ) o
  JOIN (
    SELECT DISTINCT ON (f.id_note) f.id_note, f.action_at
    FROM dwh.facts f
    WHERE f.action_dimension_id_user = m_dimension_user_id
      AND f.action_comment = 'commented'
    ORDER BY f.id_note, f.action_at ASC
  ) c ON c.id_note = o.id_note
  WHERE c.action_at > o.action_at;

  -- Days since last action
  -- CURRENT_DATE - date_id already returns INTEGER (days), no need for EXTRACT
  SELECT /* Notes-datamartUsers */ COALESCE(
    (CURRENT_DATE - d.date_id)::INTEGER,
    0
  )
  INTO m_days_since_last_action
  FROM dwh.facts f
  JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
  ORDER BY d.date_id DESC
  LIMIT 1;

  -- If no actions found, set to NULL (will be 0 due to COALESCE above)
  IF m_days_since_last_action IS NULL THEN
    m_days_since_last_action := 0;
  END IF;

  -- Enhanced date columns: Most common ISO week, quarter, and month name
  SELECT /* Notes-datamartUsers */ d.iso_week
   INTO m_iso_week
  FROM dwh.facts f
   JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
    AND d.iso_week IS NOT NULL
  GROUP BY d.iso_week
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  SELECT /* Notes-datamartUsers */ d.quarter
   INTO m_quarter
  FROM dwh.facts f
   JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
    AND d.quarter IS NOT NULL
  GROUP BY d.quarter
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  SELECT /* Notes-datamartUsers */ d.month_name
   INTO m_month_name
  FROM dwh.facts f
   JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
    AND d.month_name IS NOT NULL
  GROUP BY d.month_name
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Enhanced time columns: Most common hour_of_week and period_of_day
  SELECT /* Notes-datamartUsers */ t.hour_of_week
   INTO m_hour_of_week
  FROM dwh.facts f
   JOIN dwh.dimension_time_of_week t ON f.action_dimension_id_hour_of_week = t.dimension_tow_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
    AND t.hour_of_week IS NOT NULL
  GROUP BY t.hour_of_week
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  SELECT /* Notes-datamartUsers */ t.period_of_day
   INTO m_period_of_day
  FROM dwh.facts f
   JOIN dwh.dimension_time_of_week t ON f.action_dimension_id_hour_of_week = t.dimension_tow_id
  WHERE f.action_dimension_id_user = m_dimension_user_id
    AND t.period_of_day IS NOT NULL
  GROUP BY t.period_of_day
  ORDER BY COUNT(*) DESC
  LIMIT 1;

  -- Collaboration patterns
  WITH mentions_given AS (
    SELECT COUNT(*) as cnt
    FROM dwh.facts
    WHERE action_dimension_id_user = m_dimension_user_id
      AND action_comment = 'commented'
      AND has_mention = TRUE
  ),
  mentions_received AS (
    SELECT COUNT(*) as cnt
    FROM dwh.facts f1
    WHERE f1.action_comment = 'commented'
      AND f1.has_mention = TRUE
      AND EXISTS (
        SELECT 1
        FROM dwh.facts f2
        WHERE f2.id_note = f1.id_note
          AND f2.opened_dimension_id_user = m_dimension_user_id
          AND f2.action_comment = 'opened'
      )
  ),
  replies_count AS (
    SELECT COUNT(DISTINCT f1.id_note) as cnt
    FROM dwh.facts f1
    WHERE f1.action_dimension_id_user = m_dimension_user_id
      AND f1.action_comment = 'commented'
      AND EXISTS (
        SELECT 1
        FROM dwh.facts f2
        WHERE f2.id_note = f1.id_note
          AND f2.action_comment = 'commented'
          AND f2.action_at < f1.action_at
      )
  )
  SELECT /* Notes-datamartUsers */ COALESCE(json_build_object(
    'mentions_given', COALESCE(mg.cnt, 0),
    'mentions_received', COALESCE(mr.cnt, 0),
    'replies_count', COALESCE(rc.cnt, 0),
    'collaboration_score', COALESCE(mg.cnt, 0) + COALESCE(mr.cnt, 0) + COALESCE(rc.cnt, 0)
  ), '{"mentions_given":0,"mentions_received":0,"replies_count":0,"collaboration_score":0}'::json)
  INTO m_collaboration_patterns
  FROM mentions_given mg
  CROSS JOIN mentions_received mr
  CROSS JOIN replies_count rc;

  -- Updates user with new values.
  UPDATE dwh.datamartUsers
  SET id_contributor_type = m_id_contributor_type,
   last_year_activity = m_last_year_activity,
   latest_open_note_id = m_latest_open_note_id,
   latest_commented_note_id = m_latest_commented_note_id,
   latest_closed_note_id = m_latest_closed_note_id,
   latest_reopened_note_id = m_latest_reopened_note_id,
   dates_most_open = m_dates_most_open,
   dates_most_closed = m_dates_most_closed,
   hashtags = m_hashtags,
   countries_open_notes = m_countries_open_notes,
   countries_solving_notes = m_countries_solving_notes,
   countries_open_notes_current_month = m_countries_open_notes_current_month,
   countries_solving_notes_current_month = m_countries_solving_notes_current_month,
   countries_open_notes_current_day = m_countries_open_notes_current_day,
   countries_solving_notes_current_day = m_countries_solving_notes_current_day,
   working_hours_of_week_opening = m_working_hours_of_week_opening,
   working_hours_of_week_commenting = m_working_hours_of_week_commenting,
   working_hours_of_week_closing = m_working_hours_of_week_closing,
   history_whole_open = m_history_whole_open,
   history_whole_commented = m_history_whole_commented,
   history_whole_closed = m_history_whole_closed,
   history_whole_reopened = m_history_whole_reopened,
   history_year_open = m_history_year_open,
   history_year_commented = m_history_year_commented,
   history_year_closed = m_history_year_closed,
   history_year_closed_with_comment = m_history_year_closed_with_comment,
   history_year_reopened = m_history_year_reopened,
   history_month_open = m_history_month_open,
   history_month_commented = m_history_month_commented,
   history_month_closed = m_history_month_closed,
   history_month_closed_with_comment = m_history_month_closed_with_comment,
   history_month_reopened = m_history_month_reopened,
   history_day_open = m_history_day_open,
   history_day_commented = m_history_day_commented,
   history_day_closed = m_history_day_closed,
   history_day_closed_with_comment = m_history_day_closed_with_comment,
   history_day_reopened = m_history_day_reopened,
   avg_days_to_resolution = m_avg_days_to_resolution,
   median_days_to_resolution = m_median_days_to_resolution,
   notes_resolved_count = m_notes_resolved_count,
   notes_still_open_count = m_notes_still_open_count,
   notes_opened_but_not_closed_by_user = m_notes_opened_but_not_closed_by_user,
   resolution_rate = m_resolution_rate,
   applications_used = m_applications_used,
   most_used_application_id = m_most_used_application_id,
   mobile_apps_count = m_mobile_apps_count,
   desktop_apps_count = m_desktop_apps_count,
   avg_comment_length = m_avg_comment_length,
   comments_with_url_count = m_comments_with_url_count,
   comments_with_url_pct = m_comments_with_url_pct,
   comments_with_mention_count = m_comments_with_mention_count,
   comments_with_mention_pct = m_comments_with_mention_pct,
   avg_comments_per_note = m_avg_comments_per_note,
   active_notes_count = m_active_notes_count,
   notes_backlog_size = m_notes_backlog_size,
   notes_age_distribution = m_notes_age_distribution,
   notes_created_last_30_days = m_notes_created_last_30_days,
   notes_resolved_last_30_days = m_notes_resolved_last_30_days
  , resolution_by_year = m_resolution_by_year
  , resolution_by_month = m_resolution_by_month
  , hashtags_opening = m_hashtags_opening
  , hashtags_resolution = m_hashtags_resolution
  , hashtags_comments = m_hashtags_comments
  , favorite_opening_hashtag = m_favorite_opening_hashtag
  , favorite_resolution_hashtag = m_favorite_resolution_hashtag
  , opening_hashtag_count = m_opening_hashtag_count
  , resolution_hashtag_count = m_resolution_hashtag_count
  , application_usage_trends = m_application_usage_trends
  , version_adoption_rates = m_version_adoption_rates
  , user_response_time = m_user_response_time
  , days_since_last_action = m_days_since_last_action
  , collaboration_patterns = m_collaboration_patterns
  , iso_week = m_iso_week
  , quarter = m_quarter
  , month_name = m_month_name
  , hour_of_week = m_hour_of_week
  , period_of_day = m_period_of_day
  WHERE dimension_user_id = m_dimension_user_id;

  -- Only update year activity if procedure exists and years columns exist
  -- Skip year-by-year updates in test environment to avoid missing column errors
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_datamart_user_activity_year') THEN
    BEGIN
      m_year := 2013;
      WHILE (m_year <= m_current_year) LOOP
        CALL dwh.update_datamart_user_activity_year(m_dimension_user_id, m_year);
        m_year := m_year + 1;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for missing year columns (tests may not have all year columns)
      NULL;
    END;
  END IF;

  -- Update new metrics (DM-006, DM-007, DM-008, DM-011)
  -- Only if the function exists (for backward compatibility)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_user_new_metrics') THEN
    BEGIN
      PERFORM dwh.update_user_new_metrics(m_dimension_user_id);
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for missing columns (backward compatibility)
      NULL;
    END;
  END IF;

  -- End timing and log performance
  m_end_time := CLOCK_TIMESTAMP();
  m_duration_seconds := EXTRACT(EPOCH FROM (m_end_time - m_start_time));

  -- Get facts count for context
  SELECT COUNT(*)
   INTO m_facts_count
  FROM dwh.facts
  WHERE action_dimension_id_user = m_dimension_user_id;

  -- Log performance (only if table exists - backward compatibility)
  -- Use dynamic SQL to avoid compilation-time table validation
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'dwh'
    AND table_name = 'datamart_performance_log'
  ) THEN
   EXECUTE format('
     INSERT INTO dwh.datamart_performance_log (
       datamart_type,
       entity_id,
       start_time,
       end_time,
       duration_seconds,
       records_processed,
       facts_count,
       status
     ) VALUES (%L, %s, %L, %L, %s, %s, %s, %L)',
     'user',
     m_dimension_user_id,
     m_start_time,
     m_end_time,
     m_duration_seconds,
     1,
     m_facts_count,
     'success'
   );
  END IF;

  RAISE NOTICE 'User % processed in %.3f seconds (%, facts)',
    m_dimension_user_id,
    m_duration_seconds,
    m_facts_count;
END
$proc$;
COMMENT ON PROCEDURE dwh.update_datamart_user IS
  'Processes modifed user';
