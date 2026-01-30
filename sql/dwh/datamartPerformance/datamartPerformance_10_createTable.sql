-- Creates table for datamart performance monitoring.
-- Stores timing information for datamart updates.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-14

CREATE TABLE IF NOT EXISTS dwh.datamart_performance_log (
  log_id BIGSERIAL PRIMARY KEY,
  datamart_type VARCHAR(20) NOT NULL, -- 'country', 'user', 'global'
  entity_id INTEGER, -- dimension_country_id, dimension_user_id, or dimension_global_id
  start_time TIMESTAMP NOT NULL,
  end_time TIMESTAMP NOT NULL,
  duration_seconds DECIMAL(10,3) NOT NULL, -- Duration in seconds (with milliseconds)
  records_processed INTEGER DEFAULT 1, -- Number of records processed (usually 1, but can be batch)
  facts_count INTEGER, -- Number of facts processed (for context)
  status VARCHAR(20) DEFAULT 'success', -- 'success', 'error', 'warning'
  error_message TEXT, -- Error message if status is 'error'
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_datamart_perf_log_type_date 
  ON dwh.datamart_performance_log(datamart_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_datamart_perf_log_entity 
  ON dwh.datamart_performance_log(datamart_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_datamart_perf_log_duration 
  ON dwh.datamart_performance_log(datamart_type, duration_seconds DESC);

-- Comments
COMMENT ON TABLE dwh.datamart_performance_log IS
  'Performance logs for datamart update operations. Tracks timing and status of updates.';

COMMENT ON COLUMN dwh.datamart_performance_log.datamart_type IS
  'Type of datamart: country, user, or global';

COMMENT ON COLUMN dwh.datamart_performance_log.entity_id IS
  'ID of the entity being updated (country_id, user_id, or global_id)';

COMMENT ON COLUMN dwh.datamart_performance_log.duration_seconds IS
  'Duration of the update operation in seconds (with millisecond precision)';

COMMENT ON COLUMN dwh.datamart_performance_log.facts_count IS
  'Number of facts processed (for context on why update took this long)';

COMMENT ON COLUMN dwh.datamart_performance_log.status IS
  'Status of the update: success, error, or warning';

-- Partition by month for better performance with large datasets
-- Note: Partitioning can be added later if needed when table grows large

