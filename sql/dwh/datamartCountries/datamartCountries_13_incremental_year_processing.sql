-- Incremental Year Processing for datamartCountries
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-15
--
-- This optimization modifies the country datamart to only process years
-- that have new or modified data, instead of processing all years every time.

-- Step 1: Add tracking column to track last processed year
ALTER TABLE dwh.datamartCountries
  ADD COLUMN IF NOT EXISTS last_year_processed INTEGER DEFAULT NULL;

COMMENT ON COLUMN dwh.datamartCountries.last_year_processed IS
  'Last year that was fully processed for this country. Used for incremental updates.';

-- Step 2: Create function to get years with new/modified data for a country
CREATE OR REPLACE FUNCTION dwh.get_years_with_changes(
  p_dimension_country_id INTEGER
)
RETURNS TABLE(year INTEGER) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT EXTRACT(YEAR FROM d.date_id)::INTEGER AS year
  FROM dwh.facts f
  JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
  WHERE f.dimension_id_country = p_dimension_country_id
    -- Only include years that have facts (data exists)
    AND EXTRACT(YEAR FROM d.date_id) IS NOT NULL
  ORDER BY year DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION dwh.get_years_with_changes(INTEGER) IS
  'Returns list of years that have data for a given country, ordered by most recent first';

-- Step 3: Create optimized version of update_datamart_country_activity_year
-- that can be called incrementally
CREATE OR REPLACE PROCEDURE dwh.update_datamart_country_activity_year_incremental(
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
  -- Check if year column exists (for backward compatibility)
  SELECT /* Notes-datamartCountries */ EXTRACT(YEAR FROM CURRENT_DATE)
   INTO m_current_year;

  -- Only process if year is valid
  IF m_year IS NULL OR m_year < 2013 OR m_year > m_current_year THEN
    RAISE NOTICE 'Skipping invalid year % for country %', m_year, m_dimension_country_id;
    RETURN;
  END IF;

  -- Check if year column exists in datamart table
  stmt := 'SELECT /* Notes-datamartCountries */ history_' || m_year || '_open '
   || 'FROM dwh.datamartCountries '
   || 'WHERE dimension_country_id = ' || m_dimension_country_id;

  BEGIN
    EXECUTE stmt INTO m_check_year_populated;
  EXCEPTION WHEN undefined_column THEN
    -- Year column doesn't exist, skip processing
    RAISE NOTICE 'Year % column does not exist, skipping', m_year;
    RETURN;
  END;

  -- OPTIMIZATION: Use consolidated function to get all year activity metrics in a single query
  -- This replaces 7+ separate SELECT queries with 1 table scan
  -- Falls back to individual queries if function doesn't exist (backward compatibility)
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE proname = 'get_country_year_activity_consolidated'
  ) THEN
    -- Use consolidated function (much faster)
    SELECT
      yac.history_year_open,
      yac.history_year_commented,
      yac.history_year_closed,
      yac.history_year_closed_with_comment,
      yac.history_year_reopened,
      yac.ranking_users_opening_year,
      yac.ranking_users_closing_year
    INTO
      m_history_year_open,
      m_history_year_commented,
      m_history_year_closed,
      m_history_year_closed_with_comment,
      m_history_year_reopened,
      m_ranking_users_opening_year,
      m_ranking_users_closing_year
    FROM dwh.get_country_year_activity_consolidated(m_dimension_country_id, m_year) yac;
  ELSE
    -- Fallback to original individual queries (backward compatibility)
    -- history_year_open
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_year_open
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.opened_dimension_id_date = d.dimension_day_id)
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
     ON (f.closed_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_country_id
     AND f.action_comment = 'closed'
     AND EXTRACT(YEAR FROM d.date_id) = m_year;

    -- history_year_closed_with_comment
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_year_closed_with_comment
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.closed_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_country_id
     AND f.action_comment = 'closed'
     AND EXISTS (
      SELECT 1
      FROM dwh.facts f2
      JOIN dwh.dimension_days d2 ON f2.action_dimension_id_date = d2.dimension_day_id
      WHERE f2.id_note = f.id_note
       AND f2.dimension_id_country = m_dimension_country_id
       AND f2.action_comment = 'commented'
       AND EXTRACT(YEAR FROM d2.date_id) = m_year
     )
     AND EXTRACT(YEAR FROM d.date_id) = m_year;

    -- history_year_reopened
    SELECT /* Notes-datamartCountries */ COUNT(DISTINCT f.id_note)
     INTO m_history_year_reopened
    FROM dwh.facts f
     JOIN dwh.dimension_days d
     ON (f.action_dimension_id_date = d.dimension_day_id)
    WHERE f.dimension_id_country = m_dimension_country_id
     AND f.action_comment = 'reopened'
     AND EXTRACT(YEAR FROM d.date_id) = m_year;

    -- ranking_users_opening_year
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

    -- ranking_users_closing_year
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

  -- Update year-specific columns
  stmt := 'UPDATE dwh.datamartCountries SET '
    || 'history_' || m_year || '_open = ' || COALESCE(m_history_year_open::TEXT, 'NULL') || ', '
    || 'history_' || m_year || '_commented = '
    || COALESCE(m_history_year_commented::TEXT, 'NULL') || ', '
    || 'history_' || m_year || '_closed = ' || COALESCE(m_history_year_closed::TEXT, 'NULL') || ', '
    || 'history_' || m_year || '_closed_with_comment = '
    || COALESCE(m_history_year_closed_with_comment::TEXT, 'NULL') || ', '
    || 'history_' || m_year || '_reopened = '
    || COALESCE(m_history_year_reopened::TEXT, 'NULL') || ', '
    || 'ranking_users_opening_' || m_year || ' = '
    || QUOTE_NULLABLE(m_ranking_users_opening_year::TEXT) || ', '
    || 'ranking_users_closing_' || m_year || ' = '
    || QUOTE_NULLABLE(m_ranking_users_closing_year::TEXT) || ', '
    || 'last_year_processed = GREATEST(COALESCE(last_year_processed, 0), ' || m_year || ') '
    || 'WHERE dimension_country_id = ' || m_dimension_country_id;

  EXECUTE stmt;
END
$proc$;

COMMENT ON PROCEDURE dwh.update_datamart_country_activity_year_incremental IS
  'Processes country activity for a specific year, updating last_year_processed tracking';

-- Step 4: Modify update_datamart_country to use incremental processing
-- This will be done by modifying the procedure call in the main update procedure
-- For now, we create a helper function that determines which years to process

CREATE OR REPLACE FUNCTION dwh.get_years_to_process(
  p_dimension_country_id INTEGER
)
RETURNS TABLE(year INTEGER) AS $$
DECLARE
  v_last_processed INTEGER;
  v_current_year INTEGER;
BEGIN
  -- Get current year
  SELECT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER INTO v_current_year;

  -- Get last processed year for this country
  SELECT COALESCE(last_year_processed, 2012) INTO v_last_processed
  FROM dwh.datamartCountries
  WHERE dimension_country_id = p_dimension_country_id;

  -- Return years from last_processed+1 to current_year, plus current_year if it has changes
  -- Also include all years that have data (for initial processing)
  RETURN QUERY
  SELECT DISTINCT y.year
  FROM dwh.get_years_with_changes(p_dimension_country_id) y
  WHERE y.year > v_last_processed  -- Only process years after last processed
     OR y.year = v_current_year     -- Always process current year
  ORDER BY y.year DESC;             -- Process most recent first
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION dwh.get_years_to_process(INTEGER) IS
  'Returns list of years that need processing for a country based on last_year_processed tracking';

-- Summary
DO $$
BEGIN
  RAISE NOTICE 'Incremental year processing optimization installed';
  RAISE NOTICE 'Next step: Modify update_datamart_country to use get_years_to_process()';
  RAISE NOTICE 'This will reduce processing time by only recalculating changed years';
END $$;
