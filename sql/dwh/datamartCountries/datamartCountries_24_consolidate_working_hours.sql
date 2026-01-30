-- ============================================================================
-- Consolidation: Working Hours of Week Metrics
-- ============================================================================
-- This function consolidates 3 separate queries that scan facts table
-- to get working hours statistics for opening, commenting, and closing notes.
--
-- Original queries:
--   - working_hours_of_week_opening: Groups by opened_dimension_id_hour_of_week where action_comment = 'opened'
--   - working_hours_of_week_commenting: Groups by action_dimension_id_hour_of_week where action_comment = 'commented'
--   - working_hours_of_week_closing: Groups by closed_dimension_id_hour_of_week
--
-- All require: action_dimension_id_season IS NOT NULL
--
-- Consolidated approach: Single scan with conditional aggregation
-- ============================================================================

CREATE OR REPLACE FUNCTION dwh.get_country_working_hours_consolidated(
  p_dimension_country_id INTEGER
) RETURNS TABLE (
  working_hours_of_week_opening JSON,
  working_hours_of_week_commenting JSON,
  working_hours_of_week_closing JSON
) AS $$
BEGIN
  RETURN QUERY
  WITH country_facts AS (
    SELECT
      f.action_comment,
      f.opened_dimension_id_hour_of_week,
      f.action_dimension_id_hour_of_week,
      f.closed_dimension_id_hour_of_week,
      f.action_dimension_id_season,
      t_opened.day_of_week AS opened_day_of_week,
      t_opened.hour_of_day AS opened_hour_of_day,
      t_action.day_of_week AS action_day_of_week,
      t_action.hour_of_day AS action_hour_of_day,
      t_closed.day_of_week AS closed_day_of_week,
      t_closed.hour_of_day AS closed_hour_of_day
    FROM dwh.facts f
    LEFT JOIN dwh.dimension_time_of_week t_opened ON f.opened_dimension_id_hour_of_week = t_opened.dimension_tow_id
    LEFT JOIN dwh.dimension_time_of_week t_action ON f.action_dimension_id_hour_of_week = t_action.dimension_tow_id
    LEFT JOIN dwh.dimension_time_of_week t_closed ON f.closed_dimension_id_hour_of_week = t_closed.dimension_tow_id
    WHERE f.dimension_id_country = p_dimension_country_id
      AND f.action_dimension_id_season IS NOT NULL
  ),
  opening_hours AS (
    SELECT
      opened_day_of_week AS day_of_week,
      opened_hour_of_day AS hour_of_day,
      COUNT(*) AS count
    FROM country_facts
    WHERE action_comment = 'opened'
      AND opened_day_of_week IS NOT NULL
      AND opened_hour_of_day IS NOT NULL
    GROUP BY opened_day_of_week, opened_hour_of_day
    ORDER BY opened_day_of_week, opened_hour_of_day
  ),
  commenting_hours AS (
    SELECT
      action_day_of_week AS day_of_week,
      action_hour_of_day AS hour_of_day,
      COUNT(*) AS count
    FROM country_facts
    WHERE action_comment = 'commented'
      AND action_day_of_week IS NOT NULL
      AND action_hour_of_day IS NOT NULL
    GROUP BY action_day_of_week, action_hour_of_day
    ORDER BY action_day_of_week, action_hour_of_day
  ),
  closing_hours AS (
    SELECT
      closed_day_of_week AS day_of_week,
      closed_hour_of_day AS hour_of_day,
      COUNT(*) AS count
    FROM country_facts
    WHERE closed_day_of_week IS NOT NULL
      AND closed_hour_of_day IS NOT NULL
    GROUP BY closed_day_of_week, closed_hour_of_day
    ORDER BY closed_day_of_week, closed_hour_of_day
  ),
  aggregated_metrics AS (
    SELECT
      (SELECT JSON_AGG(row_to_json(opening_hours))
       FROM opening_hours) AS working_hours_of_week_opening,
      (SELECT JSON_AGG(row_to_json(commenting_hours))
       FROM commenting_hours) AS working_hours_of_week_commenting,
      (SELECT JSON_AGG(row_to_json(closing_hours))
       FROM closing_hours) AS working_hours_of_week_closing
  )
  SELECT
    aggregated_metrics.working_hours_of_week_opening,
    aggregated_metrics.working_hours_of_week_commenting,
    aggregated_metrics.working_hours_of_week_closing
  FROM aggregated_metrics;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_working_hours_consolidated(INTEGER) IS
'Consolidates working_hours_of_week_opening, working_hours_of_week_commenting, and working_hours_of_week_closing metrics into a single query. Returns JSON arrays with day_of_week, hour_of_day, and count for each action type.';
