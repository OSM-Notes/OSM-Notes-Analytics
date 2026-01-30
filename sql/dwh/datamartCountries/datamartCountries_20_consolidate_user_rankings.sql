-- Consolidation of User Rankings Queries for datamartCountries
--
-- This script creates a function that consolidates multiple separate queries
-- for user rankings (opening/closing) into a single scan of the facts table.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-15
--
-- Performance Impact: Reduces 6+ separate table scans to 1 scan
-- Expected Reduction: 50-60% of time spent on user rankings calculation

-- Function to get consolidated user rankings for a country
-- This replaces 6+ separate SELECT queries with a single consolidated query
CREATE OR REPLACE FUNCTION dwh.get_country_user_rankings_consolidated(
  p_dimension_country_id INTEGER,
  p_current_year SMALLINT,
  p_current_month SMALLINT,
  p_current_day SMALLINT
)
RETURNS TABLE (
  -- Historical rankings (all time)
  users_open_notes JSON,
  users_solving_notes JSON,
  -- Current month rankings
  users_open_notes_current_month JSON,
  users_solving_notes_current_month JSON,
  -- Current day rankings
  users_open_notes_current_day JSON,
  users_solving_notes_current_day JSON
) AS $$
BEGIN
  RETURN QUERY
  WITH country_facts AS (
    -- Base CTE: Get all facts for the country with user and date information
    SELECT
      f.fact_id,
      f.opened_dimension_id_user,
      f.closed_dimension_id_user,
      f.opened_dimension_id_date,
      f.closed_dimension_id_date,
      f.action_dimension_id_date,
      d_opened.date_id AS opened_date,
      d_closed.date_id AS closed_date,
      d_action.date_id AS action_date,
      u_opened.username AS opened_username,
      u_closed.username AS closed_username,
      EXTRACT(YEAR FROM d_opened.date_id)::SMALLINT AS opened_year,
      EXTRACT(MONTH FROM d_opened.date_id)::SMALLINT AS opened_month,
      EXTRACT(DAY FROM d_opened.date_id)::SMALLINT AS opened_day,
      EXTRACT(YEAR FROM d_closed.date_id)::SMALLINT AS closed_year,
      EXTRACT(MONTH FROM d_closed.date_id)::SMALLINT AS closed_month,
      EXTRACT(DAY FROM d_closed.date_id)::SMALLINT AS closed_day
    FROM dwh.facts f
    LEFT JOIN dwh.dimension_days d_opened ON f.opened_dimension_id_date = d_opened.dimension_day_id
    LEFT JOIN dwh.dimension_days d_closed ON f.closed_dimension_id_date = d_closed.dimension_day_id
    LEFT JOIN dwh.dimension_days d_action ON f.action_dimension_id_date = d_action.dimension_day_id
    LEFT JOIN dwh.dimension_users u_opened ON f.opened_dimension_id_user = u_opened.dimension_user_id
    LEFT JOIN dwh.dimension_users u_closed ON f.closed_dimension_id_user = u_closed.dimension_user_id
    WHERE f.dimension_id_country = p_dimension_country_id
  ),
  opening_stats AS (
    SELECT
      opened_username AS username,
      COUNT(*) AS count_all,
      COUNT(*) FILTER (WHERE opened_year = p_current_year
                        AND opened_month = p_current_month) AS count_month,
      COUNT(*) FILTER (WHERE opened_year = p_current_year
                        AND opened_month = p_current_month
                        AND opened_day = p_current_day) AS count_day
    FROM country_facts
    WHERE opened_username IS NOT NULL
    GROUP BY opened_username
  ),
  closing_stats AS (
    SELECT
      closed_username AS username,
      COUNT(*) AS count_all,
      COUNT(*) FILTER (WHERE closed_year = p_current_year
                        AND closed_month = p_current_month) AS count_month,
      COUNT(*) FILTER (WHERE closed_year = p_current_year
                        AND closed_month = p_current_month
                        AND closed_day = p_current_day) AS count_day
    FROM country_facts
    WHERE closed_username IS NOT NULL
    GROUP BY closed_username
  ),
  opening_rankings AS (
    SELECT
      username,
      count_all,
      count_month,
      count_day,
      RANK() OVER (ORDER BY count_all DESC) AS rank_all,
      RANK() OVER (ORDER BY count_month DESC) AS rank_month,
      RANK() OVER (ORDER BY count_day DESC) AS rank_day
    FROM opening_stats
  ),
  closing_rankings AS (
    SELECT
      username,
      count_all,
      count_month,
      count_day,
      RANK() OVER (ORDER BY count_all DESC) AS rank_all,
      RANK() OVER (ORDER BY count_month DESC) AS rank_month,
      RANK() OVER (ORDER BY count_day DESC) AS rank_day
    FROM closing_stats
  ),
  aggregated_rankings AS (
    SELECT
      -- Historical opening rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_all, 'username', username, 'quantity', count_all))
        FROM (
          SELECT rank_all, username, count_all
          FROM opening_rankings
          ORDER BY count_all DESC
          LIMIT 50
        ) top_opening_all
      ) AS users_open_notes,

      -- Historical closing rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_all, 'username', username, 'quantity', count_all))
        FROM (
          SELECT rank_all, username, count_all
          FROM closing_rankings
          ORDER BY count_all DESC
          LIMIT 50
        ) top_closing_all
      ) AS users_solving_notes,

      -- Current month opening rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_month, 'username', username, 'quantity', count_month))
        FROM (
          SELECT rank_month, username, count_month
          FROM opening_rankings
          WHERE count_month > 0
          ORDER BY count_month DESC
          LIMIT 50
        ) top_opening_month
      ) AS users_open_notes_current_month,

      -- Current month closing rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_month, 'username', username, 'quantity', count_month))
        FROM (
          SELECT rank_month, username, count_month
          FROM closing_rankings
          WHERE count_month > 0
          ORDER BY count_month DESC
          LIMIT 50
        ) top_closing_month
      ) AS users_solving_notes_current_month,

      -- Current day opening rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_day, 'username', username, 'quantity', count_day))
        FROM (
          SELECT rank_day, username, count_day
          FROM opening_rankings
          WHERE count_day > 0
          ORDER BY count_day DESC
          LIMIT 50
        ) top_opening_day
      ) AS users_open_notes_current_day,

      -- Current day closing rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank_day, 'username', username, 'quantity', count_day))
        FROM (
          SELECT rank_day, username, count_day
          FROM closing_rankings
          WHERE count_day > 0
          ORDER BY count_day DESC
          LIMIT 50
        ) top_closing_day
      ) AS users_solving_notes_current_day
  )
  SELECT
    aggregated_rankings.users_open_notes,
    aggregated_rankings.users_solving_notes,
    aggregated_rankings.users_open_notes_current_month,
    aggregated_rankings.users_solving_notes_current_month,
    aggregated_rankings.users_open_notes_current_day,
    aggregated_rankings.users_solving_notes_current_day
  FROM aggregated_rankings;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_user_rankings_consolidated IS
  'Consolidates 6+ separate queries for user rankings into a single table scan. '
  'Calculates rankings for opening/closing users across historical, current month, and current day periods. '
  'Significantly improves performance by reducing multiple facts table scans to one.';

-- Verification query to test the function
-- Uncomment to test:
-- SELECT * FROM dwh.get_country_user_rankings_consolidated(42, 2026, 1, 15);

DO $$
BEGIN
  RAISE NOTICE 'Consolidated user rankings function created successfully';
  RAISE NOTICE 'This function reduces 6+ separate queries to 1 table scan';
  RAISE NOTICE 'Next step: Modify update_datamart_country to use this function';
END $$;
