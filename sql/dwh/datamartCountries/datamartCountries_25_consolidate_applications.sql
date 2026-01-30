-- ============================================================================
-- Consolidation: Applications Metrics
-- ============================================================================
-- This function consolidates 4 separate queries that scan facts table
-- to get application-related statistics.
--
-- Original queries:
--   - applications_used: JSON array with all applications and their counts
--   - most_used_application_id: The most frequently used application
--   - mobile_apps_count: Count of distinct mobile applications
--   - desktop_apps_count: Count of distinct desktop applications
--
-- All filter by: dimension_id_country, dimension_application_creation IS NOT NULL, action_comment = 'opened'
--
-- Consolidated approach: Single scan with conditional aggregation
-- ============================================================================

CREATE OR REPLACE FUNCTION dwh.get_country_applications_metrics_consolidated(
  p_dimension_country_id INTEGER
) RETURNS TABLE (
  applications_used JSON,
  most_used_application_id INTEGER,
  mobile_apps_count INTEGER,
  desktop_apps_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH country_apps AS (
    SELECT
      f.dimension_application_creation AS app_id,
      a.application_name AS app_name,
      a.platform,
      a.category,
      COUNT(*) AS app_count
    FROM dwh.facts f
    JOIN dwh.dimension_applications a ON a.dimension_application_id = f.dimension_application_creation
    WHERE f.dimension_id_country = p_dimension_country_id
      AND f.dimension_application_creation IS NOT NULL
      AND f.action_comment = 'opened'
    GROUP BY f.dimension_application_creation, a.application_name, a.platform, a.category
  ),
  app_stats AS (
    SELECT
      app_id,
      app_name,
      app_count,
      platform,
      category,
      ROW_NUMBER() OVER (ORDER BY app_count DESC) AS rank
    FROM country_apps
  ),
  aggregated_metrics AS (
    SELECT
      (SELECT json_agg(
         json_build_object(
           'app_id', app_id,
           'app_name', app_name,
           'count', app_count
         ) ORDER BY app_count DESC
       )
       FROM app_stats) AS applications_used,
      (SELECT app_id FROM app_stats WHERE rank = 1 LIMIT 1) AS most_used_application_id,
      (SELECT COUNT(DISTINCT app_id)::INTEGER
       FROM country_apps
       WHERE platform IN ('android', 'ios')
          OR platform LIKE 'mobile%'
          OR category = 'mobile') AS mobile_apps_count,
      (SELECT COUNT(DISTINCT app_id)::INTEGER
       FROM country_apps
       WHERE platform = 'web'
          OR platform IN ('desktop', 'windows', 'linux', 'macos')) AS desktop_apps_count
  )
  SELECT
    am.applications_used,
    am.most_used_application_id,
    am.mobile_apps_count,
    am.desktop_apps_count
  FROM aggregated_metrics am;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_applications_metrics_consolidated(INTEGER) IS
'Consolidates applications_used, most_used_application_id, mobile_apps_count, and desktop_apps_count metrics into a single query. Returns JSON array of applications, most used app ID, and counts for mobile/desktop platforms.';
