-- Optimize Indexes for CSV Export Performance
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-17
--
-- This script creates specialized indexes to optimize the exportClosedNotesByCountry.sql query.
-- These indexes target the specific query patterns used in CSV export.
--
-- IMPORTANT: Run this script after ETL_40_addConstraintsIndexesTriggers.sql
-- These indexes are complementary to existing indexes and focus on export-specific patterns.

-- Index 1: Optimize latest_closes CTE
-- Used for: Finding the most recent close fact per note by country
-- This index allows efficient DISTINCT ON (id_note) ... ORDER BY id_note, fact_id DESC
CREATE INDEX IF NOT EXISTS idx_facts_export_latest_close
  ON dwh.facts(id_note, fact_id DESC)
  WHERE action_comment = 'closed';

COMMENT ON INDEX dwh.idx_facts_export_latest_close IS
  'Optimizes finding latest close fact per note. Used by CSV export query.';

-- Index 2: Optimize country filter + latest close
-- Used for: Filtering by country and finding latest close in one pass
CREATE INDEX IF NOT EXISTS idx_facts_export_country_latest_close
  ON dwh.facts(dimension_id_country, id_note, fact_id DESC)
  WHERE action_comment = 'closed' AND dimension_id_country IS NOT NULL;

COMMENT ON INDEX dwh.idx_facts_export_country_latest_close IS
  'Optimizes country-filtered latest close queries. Used by CSV export query.';

-- Index 3: Optimize note_metrics aggregation
-- Used for: Counting comments and checking reopen status efficiently
CREATE INDEX IF NOT EXISTS idx_facts_export_note_metrics
  ON dwh.facts(id_note, action_comment)
  INCLUDE (fact_id)
  WHERE action_comment IN ('commented', 'opened', 'closed', 'reopened');

COMMENT ON INDEX dwh.idx_facts_export_note_metrics IS
  'Optimizes comment counting and reopen detection. Used by CSV export query.';

-- Index 4: Optimize FDW queries for opening comments
-- Note: This index should exist in the Ingestion database, not DWH
-- This is a reminder to create it in the Ingestion DB if it doesn't exist
-- CREATE INDEX IF NOT EXISTS idx_note_comments_opened
--   ON public.note_comments(note_id, sequence_action)
--   WHERE event = 'opened';
--
-- CREATE INDEX IF NOT EXISTS idx_note_comments_text_opened
--   ON public.note_comments_text(note_id, sequence_action);

-- Index 5: Optimize FDW queries for closing comments
-- Note: This index should exist in the Ingestion database, not DWH
-- This is a reminder to create it in the Ingestion DB if it doesn't exist
-- CREATE INDEX IF NOT EXISTS idx_note_comments_closed
--   ON public.note_comments(note_id, sequence_action DESC)
--   WHERE event = 'closed';
--
-- CREATE INDEX IF NOT EXISTS idx_note_comments_text_closed
--   ON public.note_comments_text(note_id, sequence_action DESC);

-- Update statistics for better query planning
ANALYZE dwh.facts;

-- Create a function to monitor export query performance
CREATE OR REPLACE FUNCTION dwh.monitor_export_index_usage()
RETURNS TABLE (
  index_name TEXT,
  table_name TEXT,
  index_scans BIGINT,
  tuples_read BIGINT,
  tuples_fetched BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    schemaname || '.' || indexrelname AS index_name,
    schemaname || '.' || relname AS table_name,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched
  FROM pg_stat_user_indexes
  WHERE indexrelname LIKE 'idx_facts_export%'
  ORDER BY idx_scan DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION dwh.monitor_export_index_usage() IS
  'Monitors usage of export-specific indexes to verify they are being used by the query planner.';

-- Create a view for easy monitoring
CREATE OR REPLACE VIEW dwh.v_export_index_performance AS
SELECT
  schemaname || '.' || indexrelname AS index_name,
  schemaname || '.' || relname AS table_name,
  idx_scan AS index_scans,
  idx_tup_read AS tuples_read,
  idx_tup_fetch AS tuples_fetched,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE indexrelname LIKE 'idx_facts_export%'
ORDER BY idx_scan DESC;

COMMENT ON VIEW dwh.v_export_index_performance IS
  'View showing performance metrics for export-specific indexes.';
