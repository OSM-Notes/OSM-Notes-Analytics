-- ============================================================================
-- Consolidation: Notes Age Metrics
-- ============================================================================
-- This function consolidates 2 separate queries that scan facts table
-- to get notes age-related statistics.
--
-- Original queries:
--   - notes_age_distribution: Distribution of open notes by age ranges
--   - notes_created_last_30_days: Count of notes created in the last 30 days
--
-- Both filter by: dimension_id_country, action_comment = 'opened'
--
-- Consolidated approach: Single scan with conditional aggregation
-- ============================================================================

CREATE OR REPLACE FUNCTION dwh.get_country_notes_age_metrics_consolidated(
  p_dimension_country_id INTEGER
) RETURNS TABLE (
  notes_age_distribution JSON,
  notes_created_last_30_days INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH opened_notes AS (
    SELECT
      f.id_note,
      dd.date_id AS opened_date
    FROM dwh.facts f
    JOIN dwh.dimension_days dd ON f.opened_dimension_id_date = dd.dimension_day_id
    WHERE f.dimension_id_country = p_dimension_country_id
      AND f.action_comment = 'opened'
  ),
  open_notes_without_close AS (
    SELECT
      id_note,
      opened_date,
      CASE
        WHEN CURRENT_DATE - opened_date <= 7 THEN '0-7 days'
        WHEN CURRENT_DATE - opened_date <= 30 THEN '8-30 days'
        WHEN CURRENT_DATE - opened_date <= 90 THEN '31-90 days'
        ELSE '90+ days'
      END AS age_range
    FROM opened_notes on1
    WHERE NOT EXISTS (
      SELECT 1
      FROM dwh.facts f2
      WHERE f2.id_note = on1.id_note
        AND f2.action_comment = 'closed'
        AND f2.dimension_id_country = p_dimension_country_id
    )
  ),
  age_distribution AS (
    SELECT
      age_range,
      COUNT(*) AS age_count
    FROM open_notes_without_close
    GROUP BY age_range
  ),
  notes_last_30_days AS (
    SELECT COUNT(DISTINCT id_note)::INTEGER AS count_30_days
    FROM opened_notes
    WHERE opened_date >= CURRENT_DATE - INTERVAL '30 days'
  ),
  aggregated_metrics AS (
    SELECT
      (SELECT json_agg(
         json_build_object(
           'age_range', age_range,
           'count', age_count
         ) ORDER BY age_range
       )
       FROM age_distribution) AS notes_age_distribution,
      (SELECT count_30_days FROM notes_last_30_days)::INTEGER AS notes_created_last_30_days
  )
  SELECT
    aggregated_metrics.notes_age_distribution,
    aggregated_metrics.notes_created_last_30_days
  FROM aggregated_metrics;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_notes_age_metrics_consolidated(INTEGER) IS
'Consolidates notes_age_distribution and notes_created_last_30_days metrics into a single query. Returns JSON distribution of open notes by age ranges and count of notes created in the last 30 days.';
