-- Performance analysis queries for datamart updates.
-- Useful queries for monitoring and optimizing datamart update performance.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-14

-- ============================================================================
-- Summary Statistics
-- ============================================================================

-- Average update time by datamart type (last 24 hours)
SELECT 
  datamart_type,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(MIN(duration_seconds), 3) as min_duration_seconds,
  ROUND(MAX(duration_seconds), 3) as max_duration_seconds,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_seconds), 3) as median_duration_seconds,
  ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds), 3) as p95_duration_seconds,
  SUM(records_processed) as total_records_processed,
  ROUND(SUM(records_processed) / NULLIF(SUM(duration_seconds), 0), 2) as records_per_second
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
  AND status = 'success'
GROUP BY datamart_type
ORDER BY datamart_type;

-- ============================================================================
-- Slow Updates (Top 20)
-- ============================================================================

-- Slowest country updates (last 7 days)
SELECT 
  entity_id,
  duration_seconds,
  facts_count,
  records_per_second,
  start_time,
  end_time
FROM (
  SELECT 
    entity_id,
    duration_seconds,
    facts_count,
    ROUND(records_processed / NULLIF(duration_seconds, 0), 2) as records_per_second,
    start_time,
    end_time
  FROM dwh.datamart_performance_log
  WHERE datamart_type = 'country'
    AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    AND status = 'success'
) sub
ORDER BY duration_seconds DESC
LIMIT 20;

-- Slowest user updates (last 7 days)
SELECT 
  entity_id,
  duration_seconds,
  facts_count,
  records_per_second,
  start_time,
  end_time
FROM (
  SELECT 
    entity_id,
    duration_seconds,
    facts_count,
    ROUND(records_processed / NULLIF(duration_seconds, 0), 2) as records_per_second,
    start_time,
    end_time
  FROM dwh.datamart_performance_log
  WHERE datamart_type = 'user'
    AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    AND status = 'success'
) sub
ORDER BY duration_seconds DESC
LIMIT 20;

-- ============================================================================
-- Performance Trends
-- ============================================================================

-- Average update time by hour of day (last 7 days)
SELECT 
  EXTRACT(HOUR FROM start_time) as hour_of_day,
  datamart_type,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds), 3) as p95_duration_seconds
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND status = 'success'
GROUP BY EXTRACT(HOUR FROM start_time), datamart_type
ORDER BY hour_of_day, datamart_type;

-- Average update time by day (last 30 days)
SELECT 
  DATE(start_time) as update_date,
  datamart_type,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(MAX(duration_seconds), 3) as max_duration_seconds,
  SUM(records_processed) as total_records_processed
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
  AND status = 'success'
GROUP BY DATE(start_time), datamart_type
ORDER BY update_date DESC, datamart_type;

-- ============================================================================
-- Entity-Specific Analysis
-- ============================================================================

-- Countries with consistently slow updates (average > 5 seconds, last 7 days)
SELECT 
  entity_id,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(MAX(duration_seconds), 3) as max_duration_seconds,
  AVG(facts_count) as avg_facts_count,
  MAX(facts_count) as max_facts_count
FROM dwh.datamart_performance_log
WHERE datamart_type = 'country'
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND status = 'success'
GROUP BY entity_id
HAVING AVG(duration_seconds) > 5.0
ORDER BY avg_duration_seconds DESC;

-- Users with consistently slow updates (average > 2 seconds, last 7 days)
SELECT 
  entity_id,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(MAX(duration_seconds), 3) as max_duration_seconds,
  AVG(facts_count) as avg_facts_count,
  MAX(facts_count) as max_facts_count
FROM dwh.datamart_performance_log
WHERE datamart_type = 'user'
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND status = 'success'
GROUP BY entity_id
HAVING AVG(duration_seconds) > 2.0
ORDER BY avg_duration_seconds DESC;

-- ============================================================================
-- Throughput Analysis
-- ============================================================================

-- Records processed per minute (last 24 hours, by hour)
SELECT 
  DATE_TRUNC('hour', start_time) as hour,
  datamart_type,
  COUNT(*) as updates_count,
  SUM(records_processed) as total_records,
  ROUND(SUM(records_processed) / 60.0, 2) as records_per_minute,
  ROUND(SUM(duration_seconds) / 60.0, 2) as total_minutes_processing
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
  AND status = 'success'
GROUP BY DATE_TRUNC('hour', start_time), datamart_type
ORDER BY hour DESC, datamart_type;

-- ============================================================================
-- Error Analysis
-- ============================================================================

-- Errors in last 7 days
SELECT 
  datamart_type,
  COUNT(*) as error_count,
  COUNT(DISTINCT entity_id) as affected_entities,
  MAX(created_at) as last_error_time
FROM dwh.datamart_performance_log
WHERE status = 'error'
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY datamart_type
ORDER BY error_count DESC;

-- Recent errors with details
SELECT 
  log_id,
  datamart_type,
  entity_id,
  start_time,
  duration_seconds,
  error_message,
  created_at
FROM dwh.datamart_performance_log
WHERE status = 'error'
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
ORDER BY created_at DESC
LIMIT 20;

-- ============================================================================
-- Performance Comparison
-- ============================================================================

-- Compare current week vs previous week
SELECT 
  datamart_type,
  CASE 
    WHEN DATE(start_time) >= CURRENT_DATE - INTERVAL '7 days' THEN 'Current Week'
    WHEN DATE(start_time) >= CURRENT_DATE - INTERVAL '14 days' THEN 'Previous Week'
  END as week_period,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds), 3) as p95_duration_seconds
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '14 days'
  AND status = 'success'
GROUP BY datamart_type, 
  CASE 
    WHEN DATE(start_time) >= CURRENT_DATE - INTERVAL '7 days' THEN 'Current Week'
    WHEN DATE(start_time) >= CURRENT_DATE - INTERVAL '14 days' THEN 'Previous Week'
  END
ORDER BY datamart_type, week_period;

-- ============================================================================
-- Facts Count vs Duration Correlation
-- ============================================================================

-- Correlation between facts count and duration (for identifying optimization opportunities)
SELECT 
  datamart_type,
  CASE 
    WHEN facts_count < 100 THEN '0-100'
    WHEN facts_count < 1000 THEN '100-1K'
    WHEN facts_count < 10000 THEN '1K-10K'
    WHEN facts_count < 100000 THEN '10K-100K'
    ELSE '100K+'
  END as facts_range,
  COUNT(*) as update_count,
  ROUND(AVG(duration_seconds), 3) as avg_duration_seconds,
  ROUND(AVG(duration_seconds / NULLIF(facts_count, 0)) * 1000, 3) as avg_ms_per_fact,
  ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_seconds), 3) as p95_duration_seconds
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND status = 'success'
  AND facts_count IS NOT NULL
GROUP BY datamart_type,
  CASE 
    WHEN facts_count < 100 THEN '0-100'
    WHEN facts_count < 1000 THEN '100-1K'
    WHEN facts_count < 10000 THEN '1K-10K'
    WHEN facts_count < 100000 THEN '10K-100K'
    ELSE '100K+'
  END
ORDER BY datamart_type, facts_range;

