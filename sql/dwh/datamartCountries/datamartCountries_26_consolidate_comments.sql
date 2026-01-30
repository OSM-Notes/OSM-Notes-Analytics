-- ============================================================================
-- Consolidation: Comments Metrics
-- ============================================================================
-- This function consolidates 4 separate queries that scan facts table
-- to get comment-related statistics.
--
-- Original queries:
--   - avg_comment_length: Average length of comments
--   - comments_with_url_count/pct: Count and percentage of comments with URLs
--   - comments_with_mention_count/pct: Count and percentage of comments with mentions
--   - avg_comments_per_note: Average number of comments per note
--
-- All filter by: dimension_id_country, action_comment = 'commented'
--
-- Consolidated approach: Single scan with conditional aggregation
-- ============================================================================

CREATE OR REPLACE FUNCTION dwh.get_country_comments_metrics_consolidated(
  p_dimension_country_id INTEGER
) RETURNS TABLE (
  avg_comment_length DECIMAL,
  comments_with_url_count INTEGER,
  comments_with_url_pct DECIMAL,
  comments_with_mention_count INTEGER,
  comments_with_mention_pct DECIMAL,
  avg_comments_per_note DECIMAL
) AS $$
BEGIN
  RETURN QUERY
  WITH country_comments AS (
    SELECT
      f.comment_length,
      f.has_url,
      f.has_mention,
      f.id_note,
      f.opened_dimension_id_user
    FROM dwh.facts f
    WHERE f.dimension_id_country = p_dimension_country_id
      AND f.action_comment = 'commented'
  ),
  comment_stats AS (
    SELECT
      COUNT(*) AS total_comments,
      COUNT(DISTINCT id_note) AS distinct_notes,
      COALESCE(AVG(comment_length), 0) AS avg_length,
      COUNT(*) FILTER (WHERE has_url = TRUE) AS url_count,
      COUNT(*) FILTER (WHERE has_mention = TRUE) AS mention_count
    FROM country_comments
  ),
  aggregated_metrics AS (
    SELECT
      (SELECT avg_length FROM comment_stats) AS avg_comment_length,
      (SELECT url_count::INTEGER FROM comment_stats) AS comments_with_url_count,
      CASE
        WHEN (SELECT total_comments FROM comment_stats) > 0
        THEN ((SELECT url_count FROM comment_stats)::DECIMAL / (SELECT total_comments FROM comment_stats) * 100)
        ELSE 0
      END AS comments_with_url_pct,
      (SELECT mention_count::INTEGER FROM comment_stats) AS comments_with_mention_count,
      CASE
        WHEN (SELECT total_comments FROM comment_stats) > 0
        THEN ((SELECT mention_count FROM comment_stats)::DECIMAL / (SELECT total_comments FROM comment_stats) * 100)
        ELSE 0
      END AS comments_with_mention_pct,
      CASE
        WHEN (SELECT distinct_notes FROM comment_stats) > 0
        THEN (SELECT total_comments FROM comment_stats)::DECIMAL / (SELECT distinct_notes FROM comment_stats)
        ELSE 0
      END AS avg_comments_per_note
  )
  SELECT
    aggregated_metrics.avg_comment_length,
    aggregated_metrics.comments_with_url_count,
    aggregated_metrics.comments_with_url_pct,
    aggregated_metrics.comments_with_mention_count,
    aggregated_metrics.comments_with_mention_pct,
    aggregated_metrics.avg_comments_per_note
  FROM aggregated_metrics;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION dwh.get_country_comments_metrics_consolidated(INTEGER) IS
'Consolidates avg_comment_length, comments_with_url_count/pct, comments_with_mention_count/pct, and avg_comments_per_note metrics into a single query. Returns average comment length, URL/mention counts and percentages, and average comments per note.';
