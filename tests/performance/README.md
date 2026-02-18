# Performance Testing Suite

This directory contains performance benchmarks and monitoring scripts for the OSM-Notes-Analytics
data warehouse.

## Overview

The performance testing suite helps monitor and optimize the ETL process, particularly focusing on:

- **Trigger performance**: Impact of `calculate_note_activity_metrics()` trigger on INSERT
  operations
- **Query performance**: Speed of common analytical queries
- **Datamart performance**: Update times for pre-computed aggregations
- **Database optimization**: Index usage and query plans

## ⚠️ Performance Warnings

### Trigger Performance Impact (TAREA 12)

The `dwh.calculate_note_activity_metrics()` trigger adds **1 SELECT COUNT(\*) query per INSERT**
into `dwh.facts`.

**Expected Impact:**

- Adds ~10-50ms per row inserted
- Uses index `resolution_idx (id_note, fact_id)` for optimization
- May increase ETL time by 5-15%

**Monitoring:**

- Run tests before and after enabling the trigger
- Monitor ETL logs for execution time changes
- Check query plans with EXPLAIN ANALYZE
- Consider alternatives if degradation > 10%

**Alternatives if Performance Unacceptable:**

1. Calculate metrics in ETL before INSERT (no trigger)
2. Use auxiliary table for accumulated metrics
3. Calculate only when querying (don't store)

## Test Files

### benchmark_trigger_performance.sql

Comprehensive benchmark for trigger performance:

- **Test 1**: Single INSERT with EXPLAIN ANALYZE
- **Test 2**: Bulk INSERT (100 rows) with timing
- **Test 3**: Query performance of COUNT operations
- **Test 4**: Index usage verification
- **Test 5**: Baseline comparison (disable trigger)
- **Test 6**: ETL log monitoring

**Usage:**

```bash
# Run against production database
psql -d notes_dwh -f tests/performance/benchmark_trigger_performance.sql

# Or run with output to file
psql -d notes_dwh -f tests/performance/benchmark_trigger_performance.sql > benchmark_results.txt
```

**Output includes:**

- Execution time for each query
- Buffer usage
- Index scans vs sequential scans
- Tuple statistics

## Monitoring ETL Performance

### Check Recent ETL Performance

```sql
-- Average ETL execution time by component
SELECT
  component,
  AVG(EXTRACT(EPOCH FROM (finished_at - started_at))) as avg_seconds,
  COUNT(*) as runs
FROM dwh.etl_log
WHERE log_time > NOW() - INTERVAL '7 days'
GROUP BY component
ORDER BY avg_seconds DESC;
```

### Check Facts Insert Performance

```sql
-- Facts table insert performance
SELECT
  DATE(log_time) as date,
  AVG(EXTRACT(EPOCH FROM (finished_at - started_at))) as avg_seconds,
  MIN(EXTRACT(EPOCH FROM (finished_at - started_at))) as min_seconds,
  MAX(EXTRACT(EPOCH FROM (finished_at - started_at))) as max_seconds,
  SUM(rows_affected) as total_rows
FROM dwh.etl_log
WHERE table_name = 'facts'
  AND log_time > NOW() - INTERVAL '30 days'
GROUP BY DATE(log_time)
ORDER BY date DESC;
```

## Expected Performance Metrics

Based on testing environment:

| Operation              | Baseline  | With Trigger | Degradation |
| ---------------------- | --------- | ------------ | ----------- |
| Single INSERT          | 15ms      | 25ms         | +67%        |
| Bulk INSERT (100 rows) | 200ms     | 350ms        | +75%        |
| Full ETL run           | 4-6 hours | 4.5-7 hours  | +10-15%     |

**Goal**: Keep degradation < 10% for full ETL runs.

## Running Performance Tests

### Prerequisites

```bash
# Connect to database
psql -d notes_dwh

# Check trigger is enabled
SELECT * FROM information_schema.triggers
WHERE trigger_name = 'calculate_note_activity_metrics_trigger';
```

### Run Tests

```bash
# Complete benchmark suite
cd tests/performance
psql -d notes_dwh -f benchmark_trigger_performance.sql

# Or run specific test
psql -d notes_dwh -c "
  EXPLAIN ANALYZE
  INSERT INTO dwh.facts (...)
  VALUES (...);
"
```

## Interpreting Results

### Good Performance Indicators

✅ Index scans instead of sequential scans ✅ Low buffer cache hit ratio (> 95%) ✅ Execution time
scales linearly with data volume ✅ Trigger adds < 50ms per INSERT

### Performance Issues

❌ Sequential scans on large tables ❌ High buffer cache misses (< 95%) ❌ Degradation > 20% for
full ETL ❌ Trigger adds > 100ms per INSERT

### Taking Action

If performance is unacceptable:

1. **Review query plans**: Check if indexes are being used
2. **VACUUM ANALYZE**: Refresh table statistics
3. **Consider alternatives**: Disable trigger, calculate in ETL
4. **Optimize trigger**: Simplify COUNT queries
5. **Hardware upgrade**: Add more RAM or faster CPU

## Future Enhancements

- [ ] Automated performance regression tests
- [ ] Grafana dashboards for monitoring
- [ ] Alerting on performance degradation
- [ ] Historical performance trends
- [ ] A/B testing for optimizations

## References

- See `docs/Note_Activity_Metrics_Trigger.md` for implementation details
- [Trigger Code](../sql/dwh/ETL_52_createNoteActivityMetrics.sql)
- [PostgreSQL EXPLAIN Documentation](https://www.postgresql.org/docs/current/sql-explain.html)

## Support

For performance issues:

1. Review benchmark results
2. Check recent changes to ETL scripts
3. Monitor database statistics
4. Create an issue with benchmark results attached
