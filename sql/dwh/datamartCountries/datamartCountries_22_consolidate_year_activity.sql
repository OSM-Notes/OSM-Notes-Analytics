-- Consolidation of Year Activity Metrics Queries for datamartCountries
--
-- This script creates a function that consolidates multiple separate queries
-- for year-specific activity metrics into a single scan of the facts table.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-15
--
-- Performance Impact: Reduces 7+ separate table scans to 1 scan per year
-- Expected Reduction: 60-70% of time spent on year activity calculation

-- Function to get consolidated year activity metrics for a country
-- This replaces 7+ separate SELECT queries with a single consolidated query
CREATE OR REPLACE FUNCTION dwh.get_country_year_activity_consolidated(
  p_dimension_country_id INTEGER,
  p_year SMALLINT
)
RETURNS TABLE (
  -- Year metrics
  history_year_open INTEGER,
  history_year_commented INTEGER,
  history_year_closed INTEGER,
  history_year_closed_with_comment INTEGER,
  history_year_reopened INTEGER,
  -- Year rankings
  ranking_users_opening_year JSON,
  ranking_users_closing_year JSON
) AS $$
BEGIN
  RETURN QUERY
  WITH year_facts AS (
    -- Base CTE: Get all facts for the country and year with user and date information
    SELECT
      f.fact_id,
      f.id_note,
      f.action_comment,
      f.action_dimension_id_date,
      f.opened_dimension_id_user,
      f.closed_dimension_id_user,
      f.opened_dimension_id_date,
      f.closed_dimension_id_date,
      d.date_id AS action_date,
      d_opened.date_id AS opened_date,
      d_closed.date_id AS closed_date,
      EXTRACT(YEAR FROM d.date_id)::SMALLINT AS action_year,
      EXTRACT(YEAR FROM d_opened.date_id)::SMALLINT AS opened_year,
      EXTRACT(YEAR FROM d_closed.date_id)::SMALLINT AS closed_year,
      u_opened.username AS opened_username,
      u_closed.username AS closed_username,
      -- Pre-join for closed_with_comment check (LEFT JOIN to avoid filtering)
      CASE WHEN nc.note_id IS NOT NULL AND nct.body IS NOT NULL
           AND LENGTH(TRIM(nct.body)) > 0 THEN 1 ELSE 0 END AS has_closed_comment
    FROM dwh.facts f
    JOIN dwh.dimension_days d ON f.action_dimension_id_date = d.dimension_day_id
    LEFT JOIN dwh.dimension_days d_opened ON f.opened_dimension_id_date = d_opened.dimension_day_id
    LEFT JOIN dwh.dimension_days d_closed ON f.closed_dimension_id_date = d_closed.dimension_day_id
    LEFT JOIN dwh.dimension_users u_opened ON f.opened_dimension_id_user = u_opened.dimension_user_id
    LEFT JOIN dwh.dimension_users u_closed ON f.closed_dimension_id_user = u_closed.dimension_user_id
    LEFT JOIN public.note_comments nc ON (
      f.id_note = nc.note_id
      AND nc.event = 'closed'
    )
    LEFT JOIN public.note_comments_text nct ON (
      nc.note_id = nct.note_id
      AND nc.sequence_action = nct.sequence_action
    )
    WHERE f.dimension_id_country = p_dimension_country_id
      AND EXTRACT(YEAR FROM d.date_id) = p_year
  ),
  year_metrics AS (
    SELECT
      -- Year metrics
      COUNT(*) FILTER (WHERE action_comment = 'opened') AS year_open,
      COUNT(*) FILTER (WHERE action_comment = 'commented') AS year_commented,
      COUNT(DISTINCT id_note) FILTER (WHERE action_comment = 'closed') AS year_closed,
      COUNT(*) FILTER (WHERE action_comment = 'closed' AND has_closed_comment = 1) AS year_closed_with_comment,
      COUNT(DISTINCT id_note) FILTER (WHERE action_comment = 'reopened') AS year_reopened
    FROM year_facts
  ),
  opening_user_stats AS (
    SELECT
      opened_username AS username,
      COUNT(*) AS count
    FROM year_facts
    WHERE opened_username IS NOT NULL
      AND opened_year = p_year
    GROUP BY opened_username
  ),
  closing_user_stats AS (
    SELECT
      closed_username AS username,
      COUNT(*) AS count
    FROM year_facts
    WHERE closed_username IS NOT NULL
      AND closed_year = p_year
    GROUP BY closed_username
  ),
  opening_rankings AS (
    SELECT
      username,
      count,
      RANK() OVER (ORDER BY count DESC) AS rank
    FROM opening_user_stats
  ),
  closing_rankings AS (
    SELECT
      username,
      count,
      RANK() OVER (ORDER BY count DESC) AS rank
    FROM closing_user_stats
  ),
  aggregated_metrics AS (
    SELECT
      -- Year metrics from year_metrics CTE
      (SELECT year_open FROM year_metrics) AS history_year_open,
      (SELECT year_commented FROM year_metrics) AS history_year_commented,
      (SELECT year_closed FROM year_metrics) AS history_year_closed,
      (SELECT year_closed_with_comment FROM year_metrics) AS history_year_closed_with_comment,
      (SELECT year_reopened FROM year_metrics) AS history_year_reopened,

      -- Opening rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username, 'quantity', count))
        FROM (
          SELECT rank, username, count
          FROM opening_rankings
          ORDER BY count DESC
          LIMIT 50
        ) top_opening
      ) AS ranking_users_opening_year,

      -- Closing rankings (top 50)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'username', username, 'quantity', count))
        FROM (
          SELECT rank, username, count
          FROM closing_rankings
          ORDER BY count DESC
          LIMIT 50
        ) top_closing
      ) AS ranking_users_closing_year
  )
  SELECT
    am.history_year_open::INTEGER,
    am.history_year_commented::INTEGER,
    am.history_year_closed::INTEGER,
    am.history_year_closed_with_comment::INTEGER,
    am.history_year_reopened::INTEGER,
    am.ranking_users_opening_year,
    am.ranking_users_closing_year
  FROM aggregated_metrics am;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_year_activity_consolidated IS
  'Consolidates 7+ separate queries for year activity metrics into a single table scan. '
  'Calculates all year-specific metrics (opened, commented, closed, reopened, rankings) in one query. '
  'Significantly improves performance by reducing multiple facts table scans to one per year.';

-- Verification query to test the function
-- Uncomment to test:
-- SELECT * FROM dwh.get_country_year_activity_consolidated(42, 2025);

DO $$
BEGIN
  RAISE NOTICE 'Consolidated year activity function created successfully';
  RAISE NOTICE 'This function reduces 7+ separate queries to 1 table scan per year';
  RAISE NOTICE 'Next step: Modify update_datamart_country_activity_year to use this function';
END $$;
