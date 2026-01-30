-- Consolidation of Hashtag Metrics Queries for datamartCountries
--
-- This script creates a function that consolidates multiple separate queries
-- for hashtag metrics into a single scan of the fact_hashtags and facts tables.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-15
--
-- Performance Impact: Reduces 7+ separate table scans to 1 scan
-- Expected Reduction: 50-60% of time spent on hashtag metrics calculation

-- Function to get consolidated hashtag metrics for a country
-- This replaces 7+ separate SELECT queries with a single consolidated query
CREATE OR REPLACE FUNCTION dwh.get_country_hashtag_metrics_consolidated(
  p_dimension_country_id INTEGER
)
RETURNS TABLE (
  -- Hashtag rankings (top 10 each)
  hashtags_opening JSON,
  hashtags_resolution JSON,
  hashtags_comments JSON,
  -- Top hashtags (single values)
  top_opening_hashtag VARCHAR(50),
  top_resolution_hashtag VARCHAR(50),
  -- Hashtag counts
  opening_hashtag_count INTEGER,
  resolution_hashtag_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH country_hashtags AS (
    -- Base CTE: Get all hashtags for the country with their metadata
    SELECT
      fh.fact_id,
      fh.dimension_hashtag_id,
      h.description AS hashtag,
      fh.is_opening_hashtag,
      fh.is_resolution_hashtag,
      fh.used_in_action
    FROM dwh.fact_hashtags fh
    JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
    JOIN dwh.facts f ON fh.fact_id = f.fact_id
    WHERE f.dimension_id_country = p_dimension_country_id
  ),
  hashtag_stats AS (
    SELECT
      hashtag,
      COUNT(*) FILTER (WHERE is_opening_hashtag = TRUE) AS opening_count,
      COUNT(*) FILTER (WHERE is_resolution_hashtag = TRUE) AS resolution_count,
      COUNT(*) FILTER (WHERE used_in_action = 'commented') AS comment_count,
      COUNT(DISTINCT fact_id) FILTER (WHERE is_opening_hashtag = TRUE) AS opening_fact_count,
      COUNT(DISTINCT fact_id) FILTER (WHERE is_resolution_hashtag = TRUE) AS resolution_fact_count
    FROM country_hashtags
    GROUP BY hashtag
  ),
  opening_rankings AS (
    SELECT
      hashtag,
      opening_count AS count,
      RANK() OVER (ORDER BY opening_count DESC) AS rank
    FROM hashtag_stats
    WHERE opening_count > 0
  ),
  resolution_rankings AS (
    SELECT
      hashtag,
      resolution_count AS count,
      RANK() OVER (ORDER BY resolution_count DESC) AS rank
    FROM hashtag_stats
    WHERE resolution_count > 0
  ),
  comment_rankings AS (
    SELECT
      hashtag,
      comment_count AS count,
      RANK() OVER (ORDER BY comment_count DESC) AS rank
    FROM hashtag_stats
    WHERE comment_count > 0
  ),
  aggregated_metrics AS (
    SELECT
      -- Opening hashtags rankings (top 10)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
        FROM (
          SELECT rank, hashtag, count
          FROM opening_rankings
          ORDER BY count DESC
          LIMIT 10
        ) top_opening
      ) AS hashtags_opening,

      -- Resolution hashtags rankings (top 10)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
        FROM (
          SELECT rank, hashtag, count
          FROM resolution_rankings
          ORDER BY count DESC
          LIMIT 10
        ) top_resolution
      ) AS hashtags_resolution,

      -- Comment hashtags rankings (top 10)
      (
        SELECT JSON_AGG(JSON_BUILD_OBJECT('rank', rank, 'hashtag', hashtag, 'count', count))
        FROM (
          SELECT rank, hashtag, count
          FROM comment_rankings
          ORDER BY count DESC
          LIMIT 10
        ) top_comments
      ) AS hashtags_comments,

      -- Top opening hashtag (single value)
      (
        SELECT hashtag::VARCHAR(50)
        FROM opening_rankings
        WHERE rank = 1
        LIMIT 1
      ) AS top_opening_hashtag,

      -- Top resolution hashtag (single value)
      (
        SELECT hashtag::VARCHAR(50)
        FROM resolution_rankings
        WHERE rank = 1
        LIMIT 1
      ) AS top_resolution_hashtag,

      -- Opening hashtag count (distinct facts)
      (
        SELECT COUNT(DISTINCT fact_id)
        FROM country_hashtags
        WHERE is_opening_hashtag = TRUE
      ) AS opening_hashtag_count,

      -- Resolution hashtag count (distinct facts)
      (
        SELECT COUNT(DISTINCT fact_id)
        FROM country_hashtags
        WHERE is_resolution_hashtag = TRUE
      ) AS resolution_hashtag_count
  )
  SELECT
    aggregated_metrics.hashtags_opening,
    aggregated_metrics.hashtags_resolution,
    aggregated_metrics.hashtags_comments,
    aggregated_metrics.top_opening_hashtag,
    aggregated_metrics.top_resolution_hashtag,
    aggregated_metrics.opening_hashtag_count::INTEGER,
    aggregated_metrics.resolution_hashtag_count::INTEGER
  FROM aggregated_metrics;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_hashtag_metrics_consolidated IS
  'Consolidates 7+ separate queries for hashtag metrics into a single table scan. '
  'Calculates rankings, top hashtags, and counts for opening, resolution, and comment hashtags. '
  'Significantly improves performance by reducing multiple fact_hashtags table scans to one.';

-- Verification query to test the function
-- Uncomment to test:
-- SELECT * FROM dwh.get_country_hashtag_metrics_consolidated(42);

DO $$
BEGIN
  RAISE NOTICE 'Consolidated hashtag metrics function created successfully';
  RAISE NOTICE 'This function reduces 7+ separate queries to 1 table scan';
  RAISE NOTICE 'Next step: Modify update_datamart_country to use this function';
END $$;
