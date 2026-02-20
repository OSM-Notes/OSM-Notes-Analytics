# Datamart Performance Monitoring

This module provides performance monitoring for datamart update operations. It tracks timing
information, identifies slow updates, and helps optimize datamart performance.

## Overview

The performance monitoring system:

- **Tracks timing**: Records start time, end time, and duration for each datamart update
- **Stores context**: Captures facts count, records processed, and status
- **Enables analysis**: Provides queries to identify performance bottlenecks
- **Supports optimization**: Helps identify which countries/users take longest to process

## Setup

### 1. Create Performance Log Table

Run the table creation script:

```bash
psql -d "${DBNAME:-notes_dwh}" -f sql/dwh/datamartPerformance/datamartPerformance_11_createTable.sql
```

Or include it in your ETL setup process.

### 2. Automatic Logging

Once the table is created, timing is automatically logged when:

- `dwh.update_datamart_country()` is called
- `dwh.update_datamart_user()` is called

No additional configuration is needed.

**Note**: If the table doesn't exist, the procedures will still work but won't log performance data.
This ensures backward compatibility.

### 3. Testing

Run the performance monitoring tests:

```bash
bats tests/unit/bash/datamart_performance_monitoring.test.bats
```

The tests verify:

- Table creation works correctly
- Performance logging functions correctly
- Data quality (durations are positive, times are correct)
- Backward compatibility (procedures work even without the table)

## Usage

### View Recent Performance

```sql
-- Summary of last 24 hours
SELECT
  datamart_type,
  COUNT(*) as updates,
  ROUND(AVG(duration_seconds), 3) as avg_seconds,
  ROUND(MAX(duration_seconds), 3) as max_seconds
FROM dwh.datamart_performance_log
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '24 hours'
  AND status = 'success'
GROUP BY datamart_type;
```

### Identify Slow Updates

```sql
-- Slowest country updates (last 7 days)
SELECT
  entity_id,
  duration_seconds,
  facts_count,
  start_time
FROM dwh.datamart_performance_log
WHERE datamart_type = 'country'
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND status = 'success'
ORDER BY duration_seconds DESC
LIMIT 20;
```

### Performance Analysis Queries

See `datamartPerformance_21_analysisQueries.sql` for comprehensive analysis queries including:

- Summary statistics
- Slow updates identification
- Performance trends
- Entity-specific analysis
- Throughput analysis
- Error analysis
- Performance comparison

## Table Schema

### dwh.datamart_performance_log

| Column              | Type          | Description                    |
| ------------------- | ------------- | ------------------------------ |
| `log_id`            | BIGSERIAL     | Primary key                    |
| `datamart_type`     | VARCHAR(20)   | 'country', 'user', or 'global' |
| `entity_id`         | INTEGER       | Country/user/global ID         |
| `start_time`        | TIMESTAMP     | When update started            |
| `end_time`          | TIMESTAMP     | When update completed          |
| `duration_seconds`  | DECIMAL(10,3) | Duration in seconds            |
| `records_processed` | INTEGER       | Records processed (usually 1)  |
| `facts_count`       | INTEGER       | Number of facts processed      |
| `status`            | VARCHAR(20)   | 'success', 'error', 'warning'  |
| `error_message`     | TEXT          | Error message if failed        |
| `created_at`        | TIMESTAMP     | When log entry was created     |

## Indexes

The table has indexes on:

- `(datamart_type, created_at DESC)` - For time-based queries
- `(datamart_type, entity_id, created_at DESC)` - For entity-specific queries
- `(datamart_type, duration_seconds DESC)` - For finding slow updates

## Maintenance

### Cleanup Old Logs

To prevent the table from growing indefinitely, periodically clean old logs:

```sql
-- Delete logs older than 90 days
DELETE FROM dwh.datamart_performance_log
WHERE created_at < CURRENT_TIMESTAMP - INTERVAL '90 days';
```

### Partitioning (Future)

For very large deployments, consider partitioning by month:

```sql
-- Example: Partition by month (requires PostgreSQL 10+)
CREATE TABLE dwh.datamart_performance_log_2025_01
  PARTITION OF dwh.datamart_performance_log
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

## Performance Impact

The logging adds minimal overhead:

- **Insert time**: < 1ms per update
- **Storage**: ~100 bytes per log entry
- **Index maintenance**: Negligible for typical volumes

For 1000 updates per day:

- **Daily storage**: ~100 KB
- **Monthly storage**: ~3 MB
- **Yearly storage**: ~36 MB

## Troubleshooting

### No Logs Being Created

1. Check if table exists:

   ```sql
   SELECT * FROM information_schema.tables
   WHERE table_schema = 'dwh'
     AND table_name = 'datamart_performance_log';
   ```

2. Check if procedures are being called:

   ```sql
   SELECT * FROM dwh.datamart_performance_log
   ORDER BY created_at DESC
   LIMIT 10;
   ```

3. Check for errors in procedure execution (look for 'error' status)

### High Log Volume

If logging is creating too many entries:

- Consider increasing cleanup frequency
- Consider partitioning the table
- Consider sampling (log only every Nth update)

## Testing

### Running Tests

```bash
# Run all performance monitoring tests
bats tests/unit/bash/datamart_performance_monitoring.test.bats

# Run with database configured
export DBNAME=notes_dwh
bats tests/unit/bash/datamart_performance_monitoring.test.bats
```

### Test Coverage

The test suite (`datamart_performance_monitoring.test.bats`) covers:

- ✅ Table creation and schema validation
- ✅ Integration with `update_datamart_country()` procedure
- ✅ Integration with `update_datamart_user()` procedure
- ✅ Data quality checks (positive durations, correct timestamps)
- ✅ Backward compatibility (graceful degradation if table missing)
- ✅ Index verification

### Integration with Existing Tests

The performance monitoring system is designed to:

- **Not break existing functionality**: All existing datamart tests should still pass
- **Work transparently**: Procedures work the same way, just with added logging
- **Fail gracefully**: If the table doesn't exist, procedures still work (no logging)

## Related Documentation

- [Performance Baselines](docs/Performance_Baselines.md) - Query performance expectations
- [Troubleshooting Guide](docs/Troubleshooting_Guide.md) - Common issues and solutions
- [Testing Guide](docs/Testing_Guide.md) - How to run all tests

---

**Last Updated**: 2025-12-14  
**Version**: 1.0
