---
title: "Partitioning Strategy - dwh.facts"
description:
  "The `dwh.facts` table is partitioned by year using the `action_at` column as the partitioning
  key."
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "documentation"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Partitioning Strategy - dwh.facts

## 📊 Overview

The `dwh.facts` table is partitioned by year using the `action_at` column as the partitioning key.
This dramatically improves the performance of queries that filter by date.

---

## 🏗️ Partition Structure

```
dwh.facts (main table - PARTITIONED)
├── facts_2013 (2013-01-01 to 2013-12-31)
├── facts_2014 (2014-01-01 to 2014-12-31)
├── facts_2015 (2015-01-01 to 2015-12-31)
├── ...
├── facts_2024 (2024-01-01 to 2024-12-31)
├── facts_2025 (2025-01-01 to 2025-12-31)
├── facts_2026 (2026-01-01 to 2026-12-31) [created automatically]
└── facts_default (any future date beyond)
```

### Characteristics:

- **Partitioning type**: RANGE by `action_at`
- **Granularity**: Annual (one partition per year)
- **Range**: 2013 to current year + 1
- **DEFAULT partition**: Captures any future date not covered

---

## 🚀 Automatic Creation

Partitions are created automatically during the ETL process:

### First Execution (Auto-detected)

```bash
./bin/dwh/ETL.sh
```

The ETL automatically detects first execution and executes these steps:

1. `ETL_20_createDWHTables.sql` - Creates main partitioned table
2. `ETL_21_createFactPartitions.sql` - Creates partitions from 2013 to current_year + 1
3. Loads data directly into partitions

### Incremental Executions (Auto-detected)

```bash
./bin/dwh/ETL.sh
```

- Existing partitions are reused
- New data is inserted into the corresponding partition based on `action_at`
- PostgreSQL automatically routes each row to its partition

---

## ➕ Adding New Partitions

### 🎉 **NO MANUAL ACTION REQUIRED!**

The ETL **automatically verifies and creates** necessary partitions on each execution:

```bash
# Simply run the ETL (auto-detects mode)
./bin/dwh/ETL.sh

# The ETL automatically:
# ✅ Verifies if partition for current year exists
# ✅ Creates partition for current year if it doesn't exist
# ✅ Creates partition for next year (buffer)
# ✅ Creates partition for year + 2 (extra buffer)
# ✅ Never fails due to missing partitions
```

### Year Transition Scenario

**January 1st, 2026 - First execution of the year:**

```bash
./bin/dwh/ETL.sh

# ETL Output:
# "Verifying and creating partitions for dwh.facts"
# "Current year: 2026, ensuring partitions exist up to 2028"
# "✓ Created partition for CURRENT YEAR: facts_2026 [2026-01-01 to 2027-01-01)"
# "✓ Created partition for NEXT YEAR: facts_2027 [2027-01-01 to 2028-01-01)"
# "  Created partition: facts_2028 [2028-01-01 to 2029-01-01)"
# "==> Created 3 new partition(s)"
# "==> Partition verification completed successfully"
```

**Subsequent executions in 2026:**

```bash
./bin/dwh/ETL.sh

# ETL Output:
# "✓ Partition facts_2026 already exists"
# "✓ Partition facts_2027 already exists"
# "✓ Partition facts_2028 already exists"
# "==> All required partitions already exist"
```

### Manual Methods (Rarely Needed)

If for some reason you need to create partitions manually:

#### Method 1: Re-run partition script (Recommended)

```bash
psql -d notes -f sql/dwh/ETL_21_createFactPartitions.sql
```

This script is idempotent and only creates missing partitions.

#### Method 2: Direct SQL

```sql
-- Example: Create partition for 2027
CREATE TABLE dwh.facts_2027 PARTITION OF dwh.facts
  FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');

-- Verify creation
SELECT tablename FROM pg_tables
WHERE schemaname = 'dwh' AND tablename = 'facts_2027';
```

---

## 🔍 Verifying Partitions

### List all partitions

```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'dwh'
  AND tablename LIKE 'facts_%'
ORDER BY tablename;
```

### View partition definitions

```sql
SELECT
  parent.relname AS parent_table,
  child.relname AS partition_name,
  pg_get_expr(child.relpartbound, child.oid, true) AS partition_expression
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
WHERE parent.relname = 'facts'
ORDER BY partition_name;
```

### View partition statistics

```sql
SELECT
  schemaname,
  tablename,
  n_tup_ins as inserts,
  n_tup_upd as updates,
  n_tup_del as deletes,
  n_live_tup as live_rows,
  n_dead_tup as dead_rows,
  last_vacuum,
  last_autovacuum,
  last_analyze,
  last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'dwh'
  AND tablename LIKE 'facts_%'
ORDER BY tablename;
```

---

## 🎯 Performance: Partition Pruning

PostgreSQL automatically uses **partition pruning** to avoid scanning unnecessary partitions:

### Example: Query with date range

```sql
-- Only scans facts_2024
SELECT COUNT(*)
FROM dwh.facts
WHERE action_at BETWEEN '2024-01-01' AND '2024-12-31';

-- Verify partition pruning with EXPLAIN
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM dwh.facts
WHERE action_at >= '2024-01-01'
  AND action_at < '2025-01-01';
```

**Expected output:**

```
Aggregate  (actual time=123.456..123.457 rows=1 loops=1)
  ->  Seq Scan on facts_2024 facts  (actual time=0.015..98.765 rows=4000000 loops=1)
        Filter: ((action_at >= '2024-01-01'::date) AND (action_at < '2025-01-01'::date))
Planning Time: 0.123 ms
Execution Time: 123.678 ms
```

Note: **Only scans facts_2024**, not all partitions.

### Queries that DON'T use partition pruning

```sql
-- ❌ BAD: No filter on action_at
SELECT * FROM dwh.facts WHERE id_note = 12345;
-- Scans ALL partitions

-- ✅ GOOD: With filter on action_at
SELECT * FROM dwh.facts
WHERE id_note = 12345
  AND action_at >= '2024-01-01';
-- Only scans facts_2024
```

**Golden rule**: Always include filter on `action_at` for maximum performance.

---

## 🧹 Maintenance

### VACUUM by partition (Recommended)

```sql
-- VACUUM a specific partition (faster)
VACUUM ANALYZE dwh.facts_2024;

-- VACUUM all partitions (slower)
VACUUM ANALYZE dwh.facts;
```

### REINDEX by partition

```sql
-- Reindex a specific partition
REINDEX TABLE dwh.facts_2024;

-- Reindex all partitions
REINDEX TABLE dwh.facts;
```

### Autovacuum configuration by partition

```sql
-- Configure more aggressive autovacuum on recent partitions
ALTER TABLE dwh.facts_2024 SET (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_analyze_scale_factor = 0.02
);

-- Configure less frequent autovacuum on old partitions
ALTER TABLE dwh.facts_2013 SET (
  autovacuum_vacuum_scale_factor = 0.2,
  autovacuum_analyze_scale_factor = 0.1
);
```

---

## 📦 Archiving Historical Data

If you need to archive or remove old data:

### Option 1: DETACH partition (recommended)

```sql
-- Detach 2013 partition (not deleted)
ALTER TABLE dwh.facts DETACH PARTITION dwh.facts_2013;

-- Now facts_2013 is an independent table
-- You can export it, move it to another tablespace, or delete it

-- Export to file
COPY dwh.facts_2013 TO '/backups/facts_2013.csv' CSV HEADER;

-- Delete if necessary
DROP TABLE dwh.facts_2013;
```

### Option 2: DROP partition (faster)

```sql
-- Delete partition and its data directly
ALTER TABLE dwh.facts DROP PARTITION dwh.facts_2013;
-- ⚠️ WARNING: This deletes ALL 2013 data
```

---

## 🔧 Troubleshooting

### Problem: "no partition of relation for tuple"

**Error:**

```
ERROR: no partition of relation "facts" found for row
DETAIL: Partition key of the failing row contains (action_at) = (2030-05-15).
```

**Solution:**

```bash
# Create partition for 2030
./bin/dwh/addNewYearPartition.sh 2030
```

### Problem: Query still slow even with partitioning

**Check:**

1. Are you filtering by `action_at`?

   ```sql
   -- Check if it uses partition pruning
   EXPLAIN SELECT * FROM dwh.facts WHERE id_note = 123;
   ```

2. Do indexes exist on partitions?

   ```sql
   -- Verify indexes
   SELECT tablename, indexname
   FROM pg_indexes
   WHERE schemaname = 'dwh' AND tablename LIKE 'facts_%'
   ORDER BY tablename, indexname;
   ```

3. Are statistics up to date?
   ```sql
   ANALYZE dwh.facts;
   ```

---

## 📅 Maintenance Calendar

### Annual (January)

- [x] ~~Create partition for new year~~ **✅ AUTOMATIC** (ETL does it)
- [ ] Consider archiving partitions older than 5 years
- [ ] Review autovacuum configuration on old partitions

### Monthly

- [ ] Check partition sizes
  ```sql
  SELECT tablename, pg_size_pretty(pg_total_relation_size('dwh.'||tablename))
  FROM pg_tables
  WHERE schemaname = 'dwh' AND tablename LIKE 'facts_%'
  ORDER BY pg_total_relation_size('dwh.'||tablename) DESC;
  ```

### Weekly

- [ ] Review query performance
  ```sql
  SELECT query, calls, mean_exec_time, stddev_exec_time
  FROM pg_stat_statements
  WHERE query LIKE '%dwh.facts%'
  ORDER BY mean_exec_time DESC
  LIMIT 20;
  ```

### Automatic (Every ETL Execution)

- [x] **Verify current year partition** ✅ AUTOMATIC
- [x] **Create missing partitions** ✅ AUTOMATIC
- [x] **2-year future buffer** ✅ AUTOMATIC

---

## 🔗 References

- PostgreSQL Documentation:
  [Table Partitioning](https://www.postgresql.org/docs/current/ddl-partitioning.html)
- PostgreSQL Documentation:
  [Partition Pruning](https://www.postgresql.org/docs/current/ddl-partitioning.html#DDL-PARTITION-PRUNING)

---

## 📞 Support

For problems or questions about partitioning:

1. Review this documentation
2. Check ETL logs in `/tmp/ETL_*/ETL.log`
3. Verify existing partitions with verification queries
4. Open issue in the project repository

---

**Status**: ✅ Implemented
