-- Procedure to insert datamart country.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-21

/**
 * Inserts a contry in the datamart, with the values that do not change.
 */
CREATE OR REPLACE PROCEDURE dwh.insert_datamart_country (
  m_dimension_country_id INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $proc$
 DECLARE
  m_country_id INTEGER;
  m_country_name VARCHAR(100);
  m_country_name_es VARCHAR(100);
  m_country_name_en VARCHAR(100);
  m_iso_alpha2 VARCHAR(2);
  m_iso_alpha3 VARCHAR(3);
  m_dimension_continent_id INTEGER;
  m_date_starting_creating_notes DATE;
  m_date_starting_solving_notes DATE;
  m_first_open_note_id INTEGER;
  m_first_commented_note_id INTEGER;
  m_first_closed_note_id INTEGER;
  m_first_reopened_note_id INTEGER;
  m_last_year_activity CHAR(371);
  r RECORD;
 BEGIN
  SELECT /* Notes-datamartCountries */ c.country_id, c.country_name,
   c.country_name_es, c.country_name_en, c.iso_alpha2, c.iso_alpha3,
   reg.continent_id AS dimension_continent_id
   INTO m_country_id, m_country_name, m_country_name_es, m_country_name_en,
        m_iso_alpha2, m_iso_alpha3, m_dimension_continent_id
  FROM dwh.dimension_countries c
  LEFT JOIN dwh.dimension_regions reg ON c.region_id = reg.dimension_region_id
  LEFT JOIN dwh.dimension_continents ON reg.continent_id = dimension_continents.dimension_continent_id
  WHERE c.dimension_country_id = m_dimension_country_id;

  -- Check if country was found (SELECT INTO leaves variables NULL if no row matches)
  IF m_country_id IS NULL OR m_country_name IS NULL THEN
    RAISE EXCEPTION 'Country with dimension_country_id % not found', m_dimension_country_id;
  END IF;

  -- date_starting_creating_notes
  SELECT /* Notes-datamartCountries */ date_id
   INTO m_date_starting_creating_notes
  FROM dwh.dimension_days
  WHERE dimension_day_id = (
   SELECT /* Notes-datamartCountries */ MIN(opened_dimension_id_date)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
  );

  -- date_starting_solving_notes
  SELECT /* Notes-datamartCountries */ date_id
   INTO m_date_starting_solving_notes
  FROM dwh.dimension_days
  WHERE dimension_day_id = (
   SELECT /* Notes-datamartCountries */ MIN(closed_dimension_id_date)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
  );

  -- first_open_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_first_open_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MIN(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
    AND f.action_comment = 'opened'
  );

  -- first_commented_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_first_commented_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MIN(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
    AND f.action_comment = 'commented'
  );

  -- first_closed_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_first_closed_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MIN(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
    AND f.action_comment = 'closed'
  );

  -- first_reopened_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_first_reopened_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MIN(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_country_id
    AND f.action_comment = 'reopened'
  );

  m_last_year_activity := '0';
  -- Create the last year activity
  FOR r IN
   SELECT /* Notes-datamartCountries */ t.date_id, qty
   FROM (
    SELECT /* Notes-datamartCountries */ e.date_id AS date_id,
     COALESCE(c.qty, 0) AS qty
    FROM dwh.dimension_days e
    LEFT JOIN (
    SELECT /* Notes-datamartCountries */ d.dimension_day_id day_id, count(1) qty
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_country_id
     GROUP BY d.dimension_day_id
    ) c
    ON (e.dimension_day_id = c.day_id)
    ORDER BY e.date_id DESC
    LIMIT 371
   ) AS t
   ORDER BY t.date_id ASC
  LOOP
   m_last_year_activity := dwh.refresh_today_activities(m_last_year_activity,
     (dwh.get_score_user_activity(r.qty::INTEGER)));
  END LOOP;

  INSERT INTO dwh.datamartCountries (
   dimension_country_id,
   country_id,
   country_name,
   country_name_es,
   country_name_en,
   iso_alpha2,
   iso_alpha3,
   dimension_continent_id,
   date_starting_creating_notes,
   date_starting_solving_notes,
   first_open_note_id,
   first_commented_note_id,
   first_closed_note_id,
   first_reopened_note_id,
   last_year_activity
  ) VALUES (
   m_dimension_country_id,
   m_country_id,
   m_country_name,
   m_country_name_es,
   m_country_name_en,
   m_iso_alpha2,
   m_iso_alpha3,
   m_dimension_continent_id,
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
COMMENT ON PROCEDURE dwh.insert_datamart_country IS
  'Inserts a country in the corresponding datamart';

CREATE OR REPLACE PROCEDURE dwh.update_datamart_country_activity_year (
  m_dimension_country_id INTEGER,
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
  m_ranking_users_opening_year JSON;
  m_ranking_users_closing_year JSON;
  m_current_year SMALLINT;
  m_check_year_populated INTEGER;
  stmt TEXT;
 BEGIN
  SELECT /* Notes-datamartCountries */ EXTRACT(YEAR FROM CURRENT_DATE)
   INTO m_current_year;

  stmt := 'SELECT /* Notes-datamartCountries */ history_' || m_year || '_open '
   || 'FROM dwh.datamartCountries '
   || 'WHERE dimension_country_id = ' || m_dimension_country_id;
  INSERT INTO dwh.logs (message) VALUES (stmt);
  EXECUTE stmt
   INTO m_check_year_populated;

  IF (m_check_year_populated IS NULL OR m_check_year_populated = m_current_year) THEN

   -- OPTIMIZATION: Use consolidated function to get all year activity metrics in a single query
   -- This replaces 7+ separate SELECT queries with 1 table scan
   -- Falls back to individual queries if function doesn't exist (backward compatibility)
   IF EXISTS (
     SELECT 1 FROM pg_proc
     WHERE proname = 'get_country_year_activity_consolidated'
   ) THEN
     -- Use consolidated function (much faster)
     SELECT
       history_year_open,
       history_year_commented,
       history_year_closed,
       history_year_closed_with_comment,
       history_year_reopened,
       ranking_users_opening_year,
       ranking_users_closing_year
     INTO
       m_history_year_open,
       m_history_year_commented,
       m_history_year_closed,
       m_history_year_closed_with_comment,
       m_history_year_reopened,
       m_ranking_users_opening_year,
       m_ranking_users_closing_year
     FROM dwh.get_country_year_activity_consolidated(m_dimension_country_id, m_year);
   ELSE
     -- Fallback to original individual queries (backward compatibility)
     -- history_year_open
     SELECT /* Notes-datamartCountries */ COUNT(1)
      INTO m_history_year_open
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_country_id
      AND f.action_comment = 'opened'
      AND EXTRACT(YEAR FROM d.date_id) = m_year;

     -- history_year_commented
     SELECT /* Notes-datamartCountries */ COUNT(1)
      INTO m_history_year_commented
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_country_id
      AND f.action_comment = 'commented'
      AND EXTRACT(YEAR FROM d.date_id) = m_year;

     -- history_year_closed
     SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
      INTO m_history_year_closed
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_country_id
      AND f.action_comment = 'closed'
      AND EXTRACT(YEAR FROM d.date_id) = m_year;

     -- history_year_closed_with_comment
     SELECT /* Notes-datamartCountries */ COUNT(1)
      INTO m_history_year_closed_with_comment
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
      JOIN public.note_comments nc
      ON (f.id_note = nc.note_id
          AND nc.event = 'closed')
      JOIN public.note_comments_text nct
      ON (nc.note_id = nct.note_id AND nc.sequence_action = nct.sequence_action)
     WHERE f.dimension_id_country = m_dimension_country_id
      AND f.action_comment = 'closed'
      AND EXTRACT(YEAR FROM d.date_id) = m_year
      AND nct.body IS NOT NULL
      AND LENGTH(TRIM(nct.body)) > 0;

     -- history_year_reopened
     SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
      INTO m_history_year_reopened
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.action_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_country_id
      AND f.action_comment = 'reopened'
      AND EXTRACT(YEAR FROM d.date_id) = m_year;

     -- m_ranking_users_opening_year
     SELECT /* Notes-datamartCountries */
       JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
         'quantity', quantity))
       INTO m_ranking_users_opening_year
     FROM (
       SELECT /* Notes-datamartCountries */
         RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
       FROM (
         SELECT /* Notes-datamartCountries */ u.username AS username,
           COUNT(1) AS quantity
         FROM dwh.facts f
           JOIN dwh.dimension_users u
             ON f.opened_dimension_id_user = u.dimension_user_id
           JOIN dwh.dimension_days d
             ON f.opened_dimension_id_date = d.dimension_day_id
         WHERE f.dimension_id_country = m_dimension_country_id
           AND EXTRACT(YEAR FROM d.date_id) = m_year
         GROUP BY u.username
         ORDER BY COUNT(1) DESC
         LIMIT 50
       ) AS T
     ) AS S;

     -- m_ranking_users_closing_year
     SELECT /* Notes-datamartCountries */
       JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
         'quantity', quantity))
       INTO m_ranking_users_closing_year
     FROM (
       SELECT /* Notes-datamartCountries */
         RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
       FROM (
         SELECT /* Notes-datamartCountries */ u.username AS username,
           COUNT(1) AS quantity
         FROM dwh.facts f
           JOIN dwh.dimension_users u
             ON f.closed_dimension_id_user = u.dimension_user_id
           JOIN dwh.dimension_days d
             ON f.closed_dimension_id_date = d.dimension_day_id
         WHERE f.dimension_id_country = m_dimension_country_id
           AND EXTRACT(YEAR FROM d.date_id) = m_year
         GROUP BY u.username
         ORDER BY COUNT(1) DESC
         LIMIT 50
       ) AS T
     ) AS S;
   END IF;

   stmt := 'UPDATE dwh.datamartCountries SET '
     || 'history_' || m_year || '_open = ' || m_history_year_open || ', '
     || 'history_' || m_year || '_commented = '
     || m_history_year_commented || ', '
     || 'history_' || m_year || '_closed = ' || m_history_year_closed || ', '
     || 'history_' || m_year || '_closed_with_comment = '
     || m_history_year_closed_with_comment || ', '
     || 'history_' || m_year || '_reopened = '
     || m_history_year_reopened || ', '
     || 'ranking_users_opening_' || m_year || ' = '
     || QUOTE_NULLABLE(m_ranking_users_opening_year) || ', '
     || 'ranking_users_closing_' || m_year || ' = '
     || QUOTE_NULLABLE(m_ranking_users_closing_year) || ' '
     || 'WHERE dimension_country_id = ' || m_dimension_country_id;
   INSERT INTO dwh.logs (message) VALUES (SUBSTR(stmt, 1, 900));
   EXECUTE stmt;
  END IF;
 END
$proc$;
COMMENT ON PROCEDURE dwh.update_datamart_country_activity_year IS
  'Processes the country''s activity per given year';

/**
 * Updates a datamart country.
 */
CREATE OR REPLACE PROCEDURE dwh.update_datamart_country (
  m_dimension_id_country INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $proc$
 DECLARE
  qty INTEGER;
  m_todays_activity INTEGER;
  m_last_year_activity CHAR(371);
  m_latest_open_note_id INTEGER;
  m_latest_commented_note_id INTEGER;
  m_latest_closed_note_id INTEGER;
  m_latest_reopened_note_id INTEGER;
  m_dates_most_open JSON;
  m_dates_most_closed JSON;
  m_hashtags JSON;
  m_users_open_notes JSON;
  m_users_solving_notes JSON;
  m_users_open_notes_current_month JSON;
  m_users_solving_notes_current_month JSON;
  m_users_open_notes_current_day JSON;
  m_users_solving_notes_current_day JSON;
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
  m_notes_backlog_size INTEGER;
  m_notes_age_distribution JSON;
  m_notes_created_last_30_days INTEGER;
  m_notes_resolved_last_30_days INTEGER;
  m_resolution_by_year JSON;
  m_resolution_by_month JSON;
  -- DM-002: Hashtag analysis variables
  m_hashtags_opening JSON;
  m_hashtags_resolution JSON;
  m_hashtags_comments JSON;
  m_top_opening_hashtag VARCHAR(50);
  m_top_resolution_hashtag VARCHAR(50);
  m_opening_hashtag_count INTEGER;
  m_resolution_hashtag_count INTEGER;
  m_application_usage_trends JSON;
  m_version_adoption_rates JSON;
  m_notes_health_score DECIMAL(5,2);
  m_new_vs_resolved_ratio DECIMAL(5,2);
  m_backlog_ratio DECIMAL(5,2);
  m_recent_activity_score DECIMAL(5,2);
  m_start_time TIMESTAMP;
  m_end_time TIMESTAMP;
  m_duration_seconds DECIMAL(10,3);
  m_facts_count INTEGER;
  BEGIN
  -- Start timing
  m_start_time := CLOCK_TIMESTAMP();
  SELECT /* Notes-datamartCountries */ COUNT(1)
   INTO qty
   FROM dwh.datamartCountries
   WHERE dimension_country_id = m_dimension_id_country;
  IF (qty = 0) THEN
   CALL dwh.insert_datamart_country(m_dimension_id_country);
  END IF;

  -- Get current date components
  m_current_year := EXTRACT(YEAR FROM CURRENT_DATE)::SMALLINT;
  m_current_month := EXTRACT(MONTH FROM CURRENT_DATE)::SMALLINT;
  m_current_day := EXTRACT(DAY FROM CURRENT_DATE)::SMALLINT;

  -- last_year_activity
  SELECT /* Notes-datamartCountries */ last_year_activity
   INTO m_last_year_activity
  FROM dwh.datamartCountries c
  WHERE c.dimension_country_id = m_dimension_id_country;
  SELECT /* Notes-datamartCountries */ COUNT(1)
   INTO m_todays_activity
  FROM dwh.facts f
   JOIN dwh.dimension_days d
   ON (f.action_dimension_id_date = d.dimension_day_id)
  WHERE f.dimension_id_country = m_dimension_id_country
  AND d.date_id = CURRENT_DATE;
  m_last_year_activity := dwh.refresh_today_activities(m_last_year_activity,
    dwh.get_score_country_activity(m_todays_activity));

  -- latest_open_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_latest_open_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MAX(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_id_country
  );

  -- latest_commented_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_latest_commented_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MAX(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_id_country
    AND f.action_comment = 'commented'
  );

  -- latest_closed_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_latest_closed_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MAX(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_id_country
  );

  -- latest_reopened_note_id
  SELECT /* Notes-datamartCountries */ id_note
   INTO m_latest_reopened_note_id
  FROM dwh.facts
  WHERE fact_id = (
   SELECT /* Notes-datamartCountries */ MAX(fact_id)
   FROM dwh.facts f
   WHERE f.dimension_id_country = m_dimension_id_country
    AND f.action_comment = 'reopened'
  );

  -- OPTIMIZATION: Use consolidated function to get dates metrics in a single query
  -- This replaces 2 separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_dates_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT dates_most_open, dates_most_closed
    INTO m_dates_most_open, m_dates_most_closed
    FROM dwh.get_country_dates_metrics_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- dates_most_open
    SELECT /* Notes-datamartCountries */
     JSON_AGG(JSON_BUILD_OBJECT('date', date, 'quantity', quantity))
     INTO m_dates_most_open
    FROM (
     SELECT /* Notes-datamartCountries */ date_id AS date, COUNT(1) AS quantity
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.opened_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_id_country
     GROUP BY date_id
     ORDER BY COUNT(1) DESC
     LIMIT 50
    ) AS T;

    -- dates_most_closed
    SELECT /* Notes-datamartCountries */
     JSON_AGG(JSON_BUILD_OBJECT('date', date, 'quantity', quantity))
     INTO m_dates_most_closed
    FROM (
     SELECT /* Notes-datamartCountries */ date_id AS date, COUNT(1) AS quantity
     FROM dwh.facts f
      JOIN dwh.dimension_days d
      ON (f.closed_dimension_id_date = d.dimension_day_id)
     WHERE f.dimension_id_country = m_dimension_id_country
     GROUP BY date_id
     ORDER BY COUNT(1) DESC
     LIMIT 50
    ) AS T;
  END IF;

  -- hashtags - aggregates all hashtags used in this country with their frequency
  SELECT /* Notes-datamartCountries */
   JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag,
   'quantity', quantity))
   INTO m_hashtags
  FROM (
   SELECT /* Notes-datamartCountries */
    RANK () OVER (ORDER BY quantity DESC) rank, hashtag, quantity
   FROM (
    SELECT /* Notes-datamartCountries */ h.description AS hashtag,
     COUNT(1) AS quantity
    FROM dwh.facts f
     JOIN dwh.fact_hashtags fh
     ON f.fact_id = fh.fact_id
     JOIN dwh.dimension_hashtags h
     ON fh.dimension_hashtag_id = h.dimension_hashtag_id
    WHERE f.dimension_id_country = m_dimension_id_country
     AND h.description IS NOT NULL
    GROUP BY h.description
    ORDER BY COUNT(1) DESC
    LIMIT 50
   ) AS T
  ) AS T2;

  -- OPTIMIZATION: Use consolidated function to get all hashtag metrics in a single query
  -- This replaces 7+ separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_hashtag_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT
      hashtags_opening,
      hashtags_resolution,
      hashtags_comments,
      top_opening_hashtag,
      top_resolution_hashtag,
      opening_hashtag_count,
      resolution_hashtag_count
    INTO
      m_hashtags_opening,
      m_hashtags_resolution,
      m_hashtags_comments,
      m_top_opening_hashtag,
      m_top_resolution_hashtag,
      m_opening_hashtag_count,
      m_resolution_hashtag_count
    FROM dwh.get_country_hashtag_metrics_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- DM-002: Hashtags by action type - Opening hashtags
    SELECT /* Notes-datamartCountries */
     JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
     INTO m_hashtags_opening
    FROM (
     SELECT
      RANK() OVER (ORDER BY COUNT(*) DESC) AS rank,
      h.description AS hashtag,
      COUNT(*) AS count
     FROM dwh.fact_hashtags fh
     JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
     JOIN dwh.facts f ON fh.fact_id = f.fact_id
     WHERE f.dimension_id_country = m_dimension_id_country
      AND fh.is_opening_hashtag = TRUE
     GROUP BY h.description
     ORDER BY COUNT(*) DESC
     LIMIT 10
    ) opening_stats;

    -- DM-002: Resolution hashtags
    SELECT /* Notes-datamartCountries */
     JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
     INTO m_hashtags_resolution
    FROM (
     SELECT
      RANK() OVER (ORDER BY COUNT(*) DESC) AS rank,
      h.description AS hashtag,
      COUNT(*) AS count
     FROM dwh.fact_hashtags fh
     JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
     JOIN dwh.facts f ON fh.fact_id = f.fact_id
     WHERE f.dimension_id_country = m_dimension_id_country
      AND fh.is_resolution_hashtag = TRUE
     GROUP BY h.description
     ORDER BY COUNT(*) DESC
     LIMIT 10
    ) resolution_stats;

    -- DM-002: Comment hashtags
    SELECT /* Notes-datamartCountries */
     JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
     INTO m_hashtags_comments
    FROM (
     SELECT
      RANK() OVER (ORDER BY COUNT(*) DESC) AS rank,
      h.description AS hashtag,
      COUNT(*) AS count
     FROM dwh.fact_hashtags fh
     JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
     JOIN dwh.facts f ON fh.fact_id = f.fact_id
     WHERE f.dimension_id_country = m_dimension_id_country
      AND fh.used_in_action = 'commented'
     GROUP BY h.description
     ORDER BY COUNT(*) DESC
     LIMIT 10
    ) comment_stats;

    -- DM-002: Top opening hashtag
    SELECT h.description
    INTO m_top_opening_hashtag
    FROM dwh.fact_hashtags fh
    JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
    JOIN dwh.facts f ON fh.fact_id = f.fact_id
    WHERE f.dimension_id_country = m_dimension_id_country
     AND fh.is_opening_hashtag = TRUE
    GROUP BY h.description
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    -- DM-002: Top resolution hashtag
    SELECT h.description
    INTO m_top_resolution_hashtag
    FROM dwh.fact_hashtags fh
    JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
    JOIN dwh.facts f ON fh.fact_id = f.fact_id
    WHERE f.dimension_id_country = m_dimension_id_country
     AND fh.is_resolution_hashtag = TRUE
    GROUP BY h.description
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    -- DM-002: Opening hashtag count
    SELECT COUNT(DISTINCT fh.fact_id)
    INTO m_opening_hashtag_count
    FROM dwh.fact_hashtags fh
    JOIN dwh.facts f ON fh.fact_id = f.fact_id
    WHERE f.dimension_id_country = m_dimension_id_country
     AND fh.is_opening_hashtag = TRUE;

    -- DM-002: Resolution hashtag count
    SELECT COUNT(DISTINCT fh.fact_id)
    INTO m_resolution_hashtag_count
    FROM dwh.fact_hashtags fh
    JOIN dwh.facts f ON fh.fact_id = f.fact_id
    WHERE f.dimension_id_country = m_dimension_id_country
     AND fh.is_resolution_hashtag = TRUE;
  END IF;

  -- OPTIMIZATION: Use consolidated function to get all user rankings in a single query
  -- This replaces 6+ separate SELECT queries with 1-2 table scans
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_user_rankings_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT
      users_open_notes,
      users_solving_notes,
      users_open_notes_current_month,
      users_solving_notes_current_month,
      users_open_notes_current_day,
      users_solving_notes_current_day
    INTO
      m_users_open_notes,
      m_users_solving_notes,
      m_users_open_notes_current_month,
      m_users_solving_notes_current_month,
      m_users_open_notes_current_day,
      m_users_solving_notes_current_day
    FROM dwh.get_country_user_rankings_consolidated(
      m_dimension_id_country,
      m_current_year,
      m_current_month,
      m_current_day
    );
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- users_open_notes
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_open_notes
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.opened_dimension_id_user = u.dimension_user_id
        WHERE f.dimension_id_country = m_dimension_id_country
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;

    -- users_solving_notes
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_solving_notes
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.closed_dimension_id_user = u.dimension_user_id
        WHERE f.dimension_id_country = m_dimension_id_country
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;

    SELECT /* Notes-datamartCountries */ EXTRACT(YEAR FROM CURRENT_TIMESTAMP)
     INTO m_current_year;

    SELECT /* Notes-datamartCountries */ EXTRACT(MONTH FROM CURRENT_TIMESTAMP)
     INTO m_current_month;

    SELECT /* Notes-datamartCountries */ EXTRACT(DAY FROM CURRENT_TIMESTAMP)
     INTO m_current_day;

    -- users_open_notes_current_month
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_open_notes_current_month
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.opened_dimension_id_user = u.dimension_user_id
          JOIN dwh.dimension_days d
            ON f.opened_dimension_id_date = d.dimension_day_id
        WHERE f.dimension_id_country = m_dimension_id_country
          AND EXTRACT(MONTH FROM d.date_id) = m_current_month
          AND EXTRACT(YEAR FROM d.date_id) = m_current_year
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;

    -- users_solving_notes_current_month
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_solving_notes_current_month
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.closed_dimension_id_user = u.dimension_user_id
          JOIN dwh.dimension_days d
            ON f.closed_dimension_id_date = d.dimension_day_id
        WHERE f.dimension_id_country = m_dimension_id_country
          AND EXTRACT(MONTH FROM d.date_id) = m_current_month
          AND EXTRACT(YEAR FROM d.date_id) = m_current_year
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;

    -- users_open_notes_current_day
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_open_notes_current_day
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.opened_dimension_id_user = u.dimension_user_id
          JOIN dwh.dimension_days d
            ON f.opened_dimension_id_date = d.dimension_day_id
        WHERE f.dimension_id_country = m_dimension_id_country
          AND EXTRACT(DAY FROM d.date_id) = m_current_day
          AND EXTRACT(MONTH FROM d.date_id) = m_current_month
          AND EXTRACT(YEAR FROM d.date_id) = m_current_year
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;

    -- users_solving_notes_current_day
    SELECT /* Notes-datamartCountries */
      JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username,
        'quantity', quantity))
      INTO m_users_solving_notes_current_day
    FROM (
      SELECT /* Notes-datamartCountries */
        RANK () OVER (ORDER BY quantity DESC) rank, username, quantity
      FROM (
        SELECT /* Notes-datamartCountries */ u.username AS username,
          COUNT(1) AS quantity
        FROM dwh.facts f
          JOIN dwh.dimension_users u
            ON f.closed_dimension_id_user = u.dimension_user_id
          JOIN dwh.dimension_days d
            ON f.closed_dimension_id_date = d.dimension_day_id
        WHERE f.dimension_id_country = m_dimension_id_country
          AND EXTRACT(DAY FROM d.date_id) = m_current_day
          AND EXTRACT(MONTH FROM d.date_id) = m_current_month
          AND EXTRACT(YEAR FROM d.date_id) = m_current_year
        GROUP BY u.username
        ORDER BY COUNT(1) DESC
        LIMIT 50
      ) AS T
    ) AS S;
  END IF;

  -- OPTIMIZATION: Use consolidated function to get working hours metrics in a single query
  -- This replaces 3 separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_working_hours_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT working_hours_of_week_opening, working_hours_of_week_commenting, working_hours_of_week_closing
    INTO m_working_hours_of_week_opening, m_working_hours_of_week_commenting, m_working_hours_of_week_closing
    FROM dwh.get_country_working_hours_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- working_hours_of_week_opening
    -- Note: Uses action_dimension_id_season for seasonal analysis
    WITH hours AS (
     SELECT /* Notes-datamartCountries */ day_of_week, hour_of_day, COUNT(1)
     FROM dwh.facts f
      JOIN dwh.dimension_time_of_week t
      ON f.opened_dimension_id_hour_of_week = t.dimension_tow_id
     WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'opened'
      AND f.action_dimension_id_season IS NOT NULL
     GROUP BY day_of_week, hour_of_day
     ORDER BY day_of_week, hour_of_day
    )
    SELECT /* Notes-datamartCountries */ JSON_AGG(hours.*)
     INTO m_working_hours_of_week_opening
    FROM hours;

    -- working_hours_of_week_commenting
    -- Note: Uses action_dimension_id_season for seasonal analysis
    WITH hours AS (
     SELECT /* Notes-datamartCountries */ day_of_week, hour_of_day, COUNT(1)
     FROM dwh.facts f
      JOIN dwh.dimension_time_of_week t
      ON f.action_dimension_id_hour_of_week = t.dimension_tow_id
     WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'commented'
      AND f.action_dimension_id_season IS NOT NULL
     GROUP BY day_of_week, hour_of_day
     ORDER BY day_of_week, hour_of_day
    )
    SELECT /* Notes-datamartCountries */ JSON_AGG(hours.*)
     INTO m_working_hours_of_week_commenting
    FROM hours;

    -- working_hours_of_week_closing
    -- Note: Uses action_dimension_id_season for seasonal analysis
    WITH hours AS (
     SELECT /* Notes-datamartCountries */ day_of_week, hour_of_day, COUNT(1)
     FROM dwh.facts f
      JOIN dwh.dimension_time_of_week t
      ON f.closed_dimension_id_hour_of_week = t.dimension_tow_id
     WHERE f.dimension_id_country = m_dimension_id_country
       AND f.action_dimension_id_season IS NOT NULL
     GROUP BY day_of_week, hour_of_day
     ORDER BY day_of_week, hour_of_day
    )
    SELECT /* Notes-datamartCountries */ JSON_AGG(hours.*)
     INTO m_working_hours_of_week_closing
    FROM hours;
  END IF;

  -- OPTIMIZATION: Use consolidated function to get all basic metrics in a single query
  -- This replaces 20+ separate SELECT queries with 1-2 table scans
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_basic_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT
      history_whole_open,
      history_whole_commented,
      history_whole_closed,
      history_whole_closed_with_comment,
      history_whole_reopened,
      history_year_open,
      history_year_commented,
      history_year_closed,
      history_year_closed_with_comment,
      history_year_reopened,
      history_month_open,
      history_month_commented,
      history_month_closed,
      history_month_closed_with_comment,
      history_month_reopened,
      history_day_open,
      history_day_commented,
      history_day_closed,
      history_day_closed_with_comment,
      history_day_reopened
    INTO
      m_history_whole_open,
      m_history_whole_commented,
      m_history_whole_closed,
      m_history_whole_closed_with_comment,
      m_history_whole_reopened,
      m_history_year_open,
      m_history_year_commented,
      m_history_year_closed,
      m_history_year_closed_with_comment,
      m_history_year_reopened,
      m_history_month_open,
      m_history_month_commented,
      m_history_month_closed,
      m_history_month_closed_with_comment,
      m_history_month_reopened,
      m_history_day_open,
      m_history_day_commented,
      m_history_day_closed,
      m_history_day_closed_with_comment,
      m_history_day_reopened
    FROM dwh.get_country_basic_metrics_consolidated(
      m_dimension_id_country,
      m_current_year,
      m_current_month,
      m_current_day
    );
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- history_whole_open
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_whole_open
    FROM dwh.facts f
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'opened';

    -- history_whole_commented
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_whole_commented
    FROM dwh.facts f
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'commented';

    -- history_whole_closed
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_whole_closed
    FROM dwh.facts f
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed';

    -- history_whole_closed_with_comment
    SELECT /* Notes-datamartCountries */ COUNT(1)
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
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND nct.body IS NOT NULL
     AND LENGTH(TRIM(nct.body)) > 0;

    -- history_whole_reopened
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_whole_reopened
    FROM dwh.facts f
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'reopened';

    -- history_year_open
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_year_open
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'opened'
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_year_commented
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_year_commented
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'commented'
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_year_closed
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_year_closed
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_year_closed_with_comment
    SELECT /* Notes-datamartCountries */ COUNT(1)
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
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year
     AND nct.body IS NOT NULL
     AND LENGTH(TRIM(nct.body)) > 0;

    -- history_year_reopened
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_year_reopened
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'reopened'
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_month_open
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_month_open
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'opened'
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_month_commented
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_month_commented
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'commented'
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_month_closed
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_month_closed
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_month_closed_with_comment
    SELECT /* Notes-datamartCountries */ COUNT(1)
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
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year
     AND nct.body IS NOT NULL
     AND LENGTH(TRIM(nct.body)) > 0;

    -- history_month_reopened
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_month_reopened
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'reopened'
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_day_open
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_day_open
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'opened'
     AND EXTRACT(DAY FROM d.date_id) = m_current_day
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_day_commented
    SELECT /* Notes-datamartCountries */ COUNT(1)
     INTO m_history_day_commented
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'commented'
     AND EXTRACT(DAY FROM d.date_id) = m_current_day
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_day_closed
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_day_closed
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(DAY FROM d.date_id) = m_current_day
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;

    -- history_day_closed_with_comment
    SELECT /* Notes-datamartCountries */ COUNT(1)
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
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'closed'
     AND EXTRACT(DAY FROM d.date_id) = m_current_day
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year
     AND nct.body IS NOT NULL
     AND LENGTH(TRIM(nct.body)) > 0;

    -- history_day_reopened
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_day_reopened
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.action_comment = 'reopened'
     AND EXTRACT(DAY FROM d.date_id) = m_current_day
     AND EXTRACT(MONTH FROM d.date_id) = m_current_month
     AND EXTRACT(YEAR FROM d.date_id) = m_current_year;
  END IF;

  -- Average resolution time
  SELECT COALESCE(AVG(days_to_resolution), 0)
   INTO m_avg_days_to_resolution
  FROM dwh.facts
  WHERE dimension_id_country = m_dimension_id_country
    AND days_to_resolution IS NOT NULL
    AND action_comment = 'closed';

  -- Median resolution time
  SELECT COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution), 0)
   INTO m_median_days_to_resolution
  FROM dwh.facts
  WHERE dimension_id_country = m_dimension_id_country
    AND days_to_resolution IS NOT NULL
    AND action_comment = 'closed';

  -- Count resolved notes
  SELECT COUNT(DISTINCT f1.id_note)
   INTO m_notes_resolved_count
  FROM dwh.facts f1
  WHERE f1.dimension_id_country = m_dimension_id_country
    AND f1.action_comment = 'closed';

  -- Count notes still open
  SELECT COUNT(DISTINCT f2.id_note)
   INTO m_notes_still_open_count
  FROM dwh.facts f2
  WHERE f2.dimension_id_country = m_dimension_id_country
    AND f2.action_comment = 'opened'
    AND NOT EXISTS (
      SELECT 1
      FROM dwh.facts f3
      WHERE f3.id_note = f2.id_note
        AND f3.action_comment = 'closed'
        AND f3.dimension_id_country = f2.dimension_id_country
    );

  -- Calculate resolution rate
  IF (m_notes_resolved_count + m_notes_still_open_count) > 0 THEN
    m_resolution_rate := (m_notes_resolved_count::DECIMAL / (m_notes_resolved_count + m_notes_still_open_count)) * 100;
  ELSE
    m_resolution_rate := 0;
  END IF;

  -- OPTIMIZATION: Use consolidated function to get applications metrics in a single query
  -- This replaces 4 separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_applications_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT applications_used, most_used_application_id, mobile_apps_count, desktop_apps_count
    INTO m_applications_used, m_most_used_application_id, m_mobile_apps_count, m_desktop_apps_count
    FROM dwh.get_country_applications_metrics_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- Applications used (JSON array with app_id, app_name, count)
    SELECT /* Notes-datamartCountries */ json_agg(
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
     WHERE f.dimension_id_country = m_dimension_id_country
      AND f.dimension_application_creation IS NOT NULL
      AND f.action_comment = 'opened'
     GROUP BY f.dimension_application_creation, a.application_name
     ORDER BY app_count DESC
    ) AS app_stats;

    -- Most used application
    SELECT /* Notes-datamartCountries */ dimension_application_creation
    INTO m_most_used_application_id
    FROM dwh.facts
    WHERE dimension_id_country = m_dimension_id_country
     AND dimension_application_creation IS NOT NULL
     AND action_comment = 'opened'
    GROUP BY dimension_application_creation
    ORDER BY COUNT(*) DESC
    LIMIT 1;

    -- Mobile apps count (android, ios, and other mobile platforms)
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.dimension_application_creation)
    INTO m_mobile_apps_count
    FROM dwh.facts f
     JOIN dwh.dimension_applications a
     ON a.dimension_application_id = f.dimension_application_creation
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.dimension_application_creation IS NOT NULL
     AND f.action_comment = 'opened'
     AND (a.platform IN ('android', 'ios')
      OR a.platform LIKE 'mobile%'
      OR a.category = 'mobile');

    -- Desktop apps count (web and desktop platforms)
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.dimension_application_creation)
    INTO m_desktop_apps_count
    FROM dwh.facts f
     JOIN dwh.dimension_applications a
     ON a.dimension_application_id = f.dimension_application_creation
    WHERE f.dimension_id_country = m_dimension_id_country
     AND f.dimension_application_creation IS NOT NULL
     AND f.action_comment = 'opened'
     AND (a.platform = 'web'
      OR a.platform IN ('desktop', 'windows', 'linux', 'macos'));
  END IF;

  -- OPTIMIZATION: Use consolidated function to get comments metrics in a single query
  -- This replaces 4 separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_comments_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT avg_comment_length, comments_with_url_count, comments_with_url_pct,
           comments_with_mention_count, comments_with_mention_pct, avg_comments_per_note
    INTO m_avg_comment_length, m_comments_with_url_count, m_comments_with_url_pct,
         m_comments_with_mention_count, m_comments_with_mention_pct, m_avg_comments_per_note
    FROM dwh.get_country_comments_metrics_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- Average comment length
    SELECT /* Notes-datamartCountries */ COALESCE(AVG(comment_length), 0)
    INTO m_avg_comment_length
    FROM dwh.facts
    WHERE dimension_id_country = m_dimension_id_country
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
    WHERE dimension_id_country = m_dimension_id_country
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
    WHERE dimension_id_country = m_dimension_id_country
     AND action_comment = 'commented';

    -- Average comments per note
    SELECT /* Notes-datamartCountries */
     CASE
      WHEN COUNT(DISTINCT opened_dimension_id_user) > 0
      THEN COUNT(*)::DECIMAL / COUNT(DISTINCT id_note)
      ELSE 0
     END
    INTO m_avg_comments_per_note
    FROM dwh.facts
    WHERE dimension_id_country = m_dimension_id_country
     AND action_comment = 'commented';
  END IF;

  -- Phase 4: Community Health Metrics
  -- Active notes count (currently open notes)
  -- Using note_current_status table for better performance (ETL-004)
  SELECT /* Notes-datamartCountries */ COALESCE(COUNT(*), 0)
  INTO m_active_notes_count
  FROM dwh.note_current_status ncs
  WHERE ncs.dimension_id_country = m_dimension_id_country
    AND ncs.is_currently_open = TRUE;

  -- Notes backlog size (same as active notes)
  m_notes_backlog_size := m_active_notes_count;

  -- OPTIMIZATION: Use consolidated function to get notes age metrics in a single query
  -- This replaces 2 separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_notes_age_metrics_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT notes_age_distribution, notes_created_last_30_days
    INTO m_notes_age_distribution, m_notes_created_last_30_days
    FROM dwh.get_country_notes_age_metrics_consolidated(m_dimension_id_country);
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- Notes age distribution
    SELECT /* Notes-datamartCountries */ json_agg(
      json_build_object(
        'age_range', age_range,
        'count', age_count
      ) ORDER BY age_range
    )
    INTO m_notes_age_distribution
    FROM (
      SELECT
        age_range,
        COUNT(*) as age_count
      FROM (
        SELECT
          CASE
            WHEN CURRENT_DATE - dd.date_id <= 7 THEN '0-7 days'
            WHEN CURRENT_DATE - dd.date_id <= 30 THEN '8-30 days'
            WHEN CURRENT_DATE - dd.date_id <= 90 THEN '31-90 days'
            ELSE '90+ days'
          END as age_range
        FROM dwh.facts f
        JOIN dwh.dimension_days dd ON f.opened_dimension_id_date = dd.dimension_day_id
        WHERE f.dimension_id_country = m_dimension_id_country
          AND f.action_comment = 'opened'
          AND NOT EXISTS (
            SELECT 1
            FROM dwh.facts f2
            WHERE f2.id_note = f.id_note
              AND f2.action_comment = 'closed'
              AND f2.dimension_id_country = m_dimension_id_country
          )
      ) subq
      GROUP BY age_range
    ) AS grouped;

    -- Notes created last 30 days
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT id_note)
    INTO m_notes_created_last_30_days
    FROM dwh.facts f
    WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'opened'
      AND f.opened_dimension_id_date IN (
        SELECT dimension_day_id
        FROM dwh.dimension_days
        WHERE date_id >= CURRENT_DATE - INTERVAL '30 days'
      );
  END IF;

  -- Notes resolved last 30 days
  SELECT /* Notes-datamartCountries */ COUNT(DISTINCT id_note)
  INTO m_notes_resolved_last_30_days
  FROM dwh.facts f
  WHERE f.dimension_id_country = m_dimension_id_country
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
    WHERE f.dimension_id_country = m_dimension_id_country
  ),
  opened AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           COUNT(DISTINCT id_note) AS opened_cnt
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'opened'
    GROUP BY 1
  ),
  closed AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           COUNT(DISTINCT id_note) AS closed_cnt,
           AVG(f.days_to_resolution) FILTER (WHERE f.days_to_resolution IS NOT NULL)::DECIMAL(10,2) AS avg_days,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.days_to_resolution)::DECIMAL(10,2) AS median_days
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.closed_dimension_id_date = d.dimension_day_id
    WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'closed'
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
    WHERE f.dimension_id_country = m_dimension_id_country
  ),
  opened_m AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           EXTRACT(MONTH FROM d.date_id)::INT AS m,
           COUNT(DISTINCT id_note) AS opened_cnt
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
    WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'opened'
    GROUP BY 1,2
  ),
  closed_m AS (
    SELECT EXTRACT(YEAR FROM d.date_id)::INT AS y,
           EXTRACT(MONTH FROM d.date_id)::INT AS m,
           COUNT(DISTINCT id_note) AS closed_cnt,
           AVG(f.days_to_resolution) FILTER (WHERE f.days_to_resolution IS NOT NULL)::DECIMAL(10,2) AS avg_days,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.days_to_resolution)::DECIMAL(10,2) AS median_days
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.closed_dimension_id_date = d.dimension_day_id
    WHERE f.dimension_id_country = m_dimension_id_country
      AND f.action_comment = 'closed'
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
  SELECT /* Notes-datamartCountries */ COALESCE(json_agg(
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
    WHERE f.dimension_id_country = m_dimension_id_country
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
      WHERE f.dimension_id_country = m_dimension_id_country
        AND f.action_comment = 'opened'
        AND f.dimension_application_creation IS NOT NULL
        AND EXTRACT(YEAR FROM d.date_id) = years.y
      GROUP BY f.dimension_application_creation, a.application_name
    ) app_stats
  ) app_trends;

  -- Version adoption rates by year
  SELECT /* Notes-datamartCountries */ COALESCE(json_agg(
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
    WHERE f.dimension_id_country = m_dimension_id_country
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
      WHERE f.dimension_id_country = m_dimension_id_country
        AND f.action_comment = 'opened'
        AND f.dimension_application_version IS NOT NULL
        AND EXTRACT(YEAR FROM d.date_id) = years.y
      GROUP BY av.version
    ) version_stats
  ) version_trends;

  -- Notes health score (0-100)
  -- Based on: resolution_rate (40%), backlog_ratio (30%), recent_activity (30%)
  -- Backlog ratio: notes_still_open / total_notes_opened
  IF (m_history_whole_open > 0) THEN
    m_backlog_ratio := (m_notes_still_open_count::DECIMAL / m_history_whole_open) * 100;
  ELSE
    m_backlog_ratio := 0;
  END IF;

  -- Recent activity score: based on notes created vs resolved in last 30 days
  IF (m_notes_created_last_30_days > 0) THEN
    -- If more resolved than created, score is high
    IF (m_notes_resolved_last_30_days >= m_notes_created_last_30_days) THEN
      m_recent_activity_score := 100;
    ELSE
      -- Score decreases if backlog is growing
      m_recent_activity_score := (m_notes_resolved_last_30_days::DECIMAL / m_notes_created_last_30_days) * 100;
    END IF;
  ELSE
    -- No recent activity, but if there's no backlog, still good
    IF (m_notes_still_open_count = 0) THEN
      m_recent_activity_score := 100;
    ELSE
      m_recent_activity_score := 0;
    END IF;
  END IF;

  -- Calculate health score: weighted average
  -- Resolution rate (40%) + (100 - backlog_ratio) (30%) + recent_activity (30%)
  m_notes_health_score := (
    (m_resolution_rate * 0.4) +
    ((100 - LEAST(m_backlog_ratio, 100)) * 0.3) +
    (m_recent_activity_score * 0.3)
  );

  -- New vs resolved ratio (last 30 days)
  IF (m_notes_resolved_last_30_days > 0) THEN
    m_new_vs_resolved_ratio := (m_notes_created_last_30_days::DECIMAL / m_notes_resolved_last_30_days);
  ELSE
    IF (m_notes_created_last_30_days > 0) THEN
      m_new_vs_resolved_ratio := 999.99; -- Infinite ratio (no resolutions)
    ELSE
      m_new_vs_resolved_ratio := 0; -- No activity
    END IF;
  END IF;

  -- Updates country with new values.
  UPDATE dwh.datamartCountries
  SET
   last_year_activity = m_last_year_activity,
   latest_open_note_id = m_latest_open_note_id,
   latest_commented_note_id = m_latest_commented_note_id,
   latest_closed_note_id = m_latest_closed_note_id,
   latest_reopened_note_id = m_latest_reopened_note_id,
   dates_most_open = m_dates_most_open,
   dates_most_closed = m_dates_most_closed,
   hashtags = m_hashtags,
   users_open_notes = m_users_open_notes,
   users_solving_notes = m_users_solving_notes,
   users_open_notes_current_month = m_users_open_notes_current_month,
   users_solving_notes_current_month = m_users_solving_notes_current_month,
   users_open_notes_current_day = m_users_open_notes_current_day,
   users_solving_notes_current_day = m_users_solving_notes_current_day,
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
  , top_opening_hashtag = m_top_opening_hashtag
  , top_resolution_hashtag = m_top_resolution_hashtag
  , opening_hashtag_count = m_opening_hashtag_count
  , resolution_hashtag_count = m_resolution_hashtag_count
  , application_usage_trends = m_application_usage_trends
  , version_adoption_rates = m_version_adoption_rates
  , notes_health_score = m_notes_health_score
  , new_vs_resolved_ratio = m_new_vs_resolved_ratio
  WHERE dimension_country_id = m_dimension_id_country;

  -- Process years incrementally (only years with changes or new years)
  -- This optimization reduces processing time by skipping years without changes
  FOR m_year IN
   SELECT year FROM dwh.get_years_to_process(m_dimension_id_country)
  LOOP
   -- Use incremental version if available, otherwise fall back to original
   IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'update_datamart_country_activity_year_incremental'
   ) THEN
    CALL dwh.update_datamart_country_activity_year_incremental(m_dimension_id_country, m_year);
   ELSE
    -- Fallback to original procedure
    CALL dwh.update_datamart_country_activity_year(m_dimension_id_country, m_year);
   END IF;
  END LOOP;

  -- Update new metrics (DM-006, DM-007, DM-008)
  -- Only if the function exists (for backward compatibility)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_country_new_metrics') THEN
    BEGIN
      PERFORM dwh.update_country_new_metrics(m_dimension_id_country);
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for missing columns (backward compatibility)
      NULL;
    END;
  END IF;

  -- Update DM-009: Open notes by year
  -- Only if the function exists (for backward compatibility)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_country_open_notes_by_year') THEN
    BEGIN
      PERFORM dwh.update_country_open_notes_by_year(m_dimension_id_country);
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for missing columns (backward compatibility)
      NULL;
    END;
  END IF;

  -- Update DM-010: Longest resolution notes (top 10)
  -- Only if the function exists (for backward compatibility)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_country_longest_resolution_notes') THEN
    BEGIN
      PERFORM dwh.update_country_longest_resolution_notes(m_dimension_id_country, 10);
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
  WHERE dimension_id_country = m_dimension_id_country;

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
     'country',
     m_dimension_id_country,
     m_start_time,
     m_end_time,
     m_duration_seconds,
     1,
     m_facts_count,
     'success'
   );
  END IF;

  RAISE NOTICE 'Country % processed in %.3f seconds (%, facts)',
    m_dimension_id_country,
    m_duration_seconds,
    m_facts_count;
 END
$proc$;
COMMENT ON PROCEDURE dwh.update_datamart_country IS
  'Processes modifed countries';
