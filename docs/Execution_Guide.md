---
title: "Execution Guide - OSM Notes Analytics"
description: "The OSM Notes Analytics system consists of several components:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Execution Guide - OSM Notes Analytics

Complete guide for executing all components of the OSM Notes Analytics system.

## 📋 Table of Contents

- [Overview](#overview)
- [ETL Process](#etl-process)
- [Profile Generation](#profile-generation)
- [Datamart Management](#datamart-management)
- [Utility Scripts](#utility-scripts)
- [Environment Variables](#environment-variables)
- [Troubleshooting](#troubleshooting)

---

## Overview

The OSM Notes Analytics system consists of several components:

| Component     | Script                             | Purpose                                  |
| ------------- | ---------------------------------- | ---------------------------------------- |
| **ETL**       | `bin/dwh/ETL.sh`                   | Transform raw notes into star schema DWH |
| **Profiles**  | `bin/dwh/profile.sh`               | Generate user/country profiles           |
| **Datamarts** | `bin/dwh/datamart*/datamart*.sh`   | Pre-compute aggregations                 |
| **Export**    | `bin/dwh/exportDatamartsToJSON.sh` | Export to JSON for web viewer            |
| **Cleanup**   | `bin/dwh/cleanupDWH.sh`            | Remove DWH objects                       |

---

## ETL Process

The ETL process transforms OSM notes from base tables into a star schema data warehouse.

### Quick Start

#### Initial Load (First Time Setup)

```bash
# Complete initial load with all data
./bin/dwh/ETL.sh
```

This will:

1. Create DWH schema and tables
2. Create partitions for facts table
3. Populate dimension tables
4. Load all facts from base tables
5. Create indexes and constraints
6. Update datamarts

**Expected Duration**: ~1-1.5 hours for typical production dataset (~5-6M facts)

**Carga inicial (Initial Load)**: ~25 minutes

- Copy base tables: 6 minutes (363 seconds)
- Create base objects: < 1 second
- Creating procedures: 1 second
- **Phase 1 - Parallel load by year**: 12 minutes (718 seconds) - **longest stage**
- Phase 2 - Update recent_opened: 3 minutes (186 seconds)
- Constraints/indexes: 3.4 minutes (203 seconds)
- Automation/Experience systems: < 1 second
- Note current status: 17 seconds
- Database maintenance (VACUUM ANALYZE): 40 seconds
- **Total initial load**: ~25 minutes (1,487 seconds)

**Datamarts**: 10-20 minutes total (with parallel processing)

- **datamartCountries**: 5-10 minutes (parallel processing with work queue, nproc-2 threads)
  - **Sequential mode (legacy)**: 30-45 minutes
  - **Parallel mode (default)**: 5-10 minutes (3-6x faster)
  - Processing time per country varies by fact count:
    - Countries with < 100K facts: ~1.5-2 minutes (e.g., 58K facts = 1.6 min)
    - Countries with 100K-500K facts: ~2-2.5 minutes (e.g., 164K facts = 1.8 min, 394K facts = 2.1
      min)
    - Countries with 500K-1M facts: ~2.5-4 minutes (e.g., 748K facts = 3.3 min, 949K facts = 2.4
      min)
    - Countries with > 1M facts: ~3-6 minutes (e.g., 1.49M facts = 2.9 min, 924K facts = 5.7 min)
  - See `bin/dwh/datamartCountries/PARALLEL_PROCESSING.md` for details
- **datamartUsers**: 15-20 minutes (parallel processing with prioritization, nproc-1 threads)
  - See `bin/dwh/datamartUsers/PARALLEL_PROCESSING.md` for details
- **datamartGlobal**: < 1 minute

**Total ETL time**: ~1-1.5 hours for typical production dataset (~5-6M facts)

#### Incremental Update (Regular Operations)

```bash
# Update with only new data since last run (auto-detected)
./bin/dwh/ETL.sh
```

This will:

1. Auto-detect that DWH already exists
2. Process only new notes/comments since last run
3. Update affected datamarts
4. Much faster than initial load

**Expected Duration**: 5-15 minutes (normal) to 30-60 minutes (large updates)

- **Normal**: Processes only new data since last run
- **Large updates**: When significant backlog exists (> 100K facts)
- **Timeout note**: Large incrementals may require `PSQL_STATEMENT_TIMEOUT=2h` (see
  [Environment Variables](../bin/dwh/Environment_Variables.md))

### ETL Process Types

| Type            | Command            | Description                                                             |
| --------------- | ------------------ | ----------------------------------------------------------------------- |
| **Auto-detect** | `./bin/dwh/ETL.sh` | Automatically detects first execution (full load) or incremental update |
| **Validation**  | Built-in           | Automatic validation after each run                                     |

### Environment Variables

```bash
# Logging level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
export LOG_LEVEL="INFO"

# Enable/disable parallel processing
export ETL_PARALLEL_ENABLED="true"

# Batch size for processing
export ETL_BATCH_SIZE="1000"

# Database configuration (recommended: use DBNAME_INGESTION and DBNAME_DWH)
# Option 1: Separate databases (recommended for production)
export DBNAME_INGESTION="notes_dwh"
export DBNAME_DWH="notes_dwh"
export DBHOST="localhost"
export DBPORT="5432"
export DBUSER="notes"

# Option 2: Same database (DBNAME is legacy, but still supported for compatibility)
# When DBNAME_INGESTION and DBNAME_DWH are not set, DBNAME is used for both
export DBNAME="notes_dwh"  # Legacy: used when both databases are the same
```

**Note:** For DWH operations, use `DBNAME_INGESTION` and `DBNAME_DWH`. The `DBNAME` variable is
maintained for backward compatibility when both Ingestion and Analytics use the same database.

### Monitoring ETL Progress

```bash
# Real-time log monitoring
tail -40f $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log

# Check last execution status
ls -ltr /tmp/ETL_*/
```

### Recovery

The ETL has built-in recovery mechanisms:

- **Lock Files**: Prevents concurrent executions
- **JSON Recovery File**: Tracks last successful step
- **Automatic Resumption**: Can resume from last checkpoint

---

## Profile Generation

Generate profiles for users or countries with detailed analytics.

### Generate User Profile

```bash
# Basic usage
./bin/dwh/profile.sh user angoca

# With custom output
./bin/dwh/profile.sh user angoca json > angoca_profile.json
```

**Example Output**:

```json
{
  "type": "user",
  "username": "angoca",
  "experience_level": "expert",
  "total_notes_opened": 1523,
  "total_notes_closed": 892,
  "countries_activity": [...],
  "top_hashtags": [...]
}
```

### Generate Country Profile

```bash
# Basic usage
./bin/dwh/profile.sh country Colombia

# Export to JSON
./bin/dwh/profile.sh country Colombia json > colombia_profile.json
```

**Example Output**:

```json
{
  "type": "country",
  "country_name": "Colombia",
  "total_notes": 15234,
  "active_users": 456,
  "top_hashtags": [...],
  "activity_timeline": [...]
}
```

### Profile Output Formats

| Format   | Description           | File Extension |
| -------- | --------------------- | -------------- |
| **json** | JSON format (default) | `.json`        |
| **html** | HTML report           | `.html`        |
| **csv**  | CSV format            | `.csv`         |

---

## Datamart Management

Datamarts are pre-computed aggregations that speed up queries.

### Automated Update

Datamarts are **automatically updated** during ETL execution. No manual intervention needed.

### Manual Update (If Needed)

```bash
# Update country datamart (parallel processing with work queue, nproc-2 threads)
./bin/dwh/datamartCountries/datamartCountries.sh

# Update user datamart (parallel processing with prioritization, nproc-1 threads)
./bin/dwh/datamartUsers/datamartUsers.sh
```

### What Gets Updated

- **Country Datamart**: All countries marked as `modified = TRUE`
- **User Datamart**: All users marked as `modified = TRUE`
- **Smart Incremental**: Only processes changed entities

---

## Utility Scripts

### Export Datamarts to JSON

```bash
# Export all datamarts to JSON
./bin/dwh/exportDatamartsToJSON.sh

# Output goes to output/ directory
ls output/*.json
```

### Push to GitHub Pages

Automatically export JSON files and push them to the GitHub Pages data repository:

```bash
# Export and push to GitHub Pages
./bin/dwh/exportAndPushJSONToGitHub.sh
```

This script will:

1. Export all datamarts to JSON using `exportDatamartsToJSON.sh`
2. Copy files to the GitHub Pages data repository
3. Commit and push changes to GitHub
4. Data becomes available at the GitHub Pages URL

**Prerequisites:**

- The `OSM-Notes-Data` repository must be cloned to `~/github/OSM-Notes-Data`
- Git credentials must be configured for the push operation

### Cleanup DWH

**⚠️ WARNING**: This removes all DWH objects!

```bash
# Remove all DWH objects (facts, dimensions, datamarts)
./bin/dwh/cleanupDWH.sh
```

Use case: Fresh start or reset after schema changes.

---

## Environment Variables

### Common Variables

| Variable           | Description                          | Default     | Used By                |
| ------------------ | ------------------------------------ | ----------- | ---------------------- |
| `LOG_LEVEL`        | Logging verbosity                    | `ERROR`     | All scripts            |
| `CLEAN`            | Clean temporary files                | `true`      | All scripts            |
| `DBNAME_INGESTION` | Ingestion database name              | `notes_dwh` | DWH scripts            |
| `DBNAME_DWH`       | Analytics/DWH database name          | `notes_dwh` | DWH scripts            |
| `DBNAME`           | Database name (legacy/compatibility) | `notes_dwh` | All scripts (fallback) |
| `DBHOST`           | Database host                        | `localhost` | All scripts            |
| `DBPORT`           | Database port                        | `5432`      | All scripts            |
| `DBUSER`           | Database user                        | `postgres`  | All scripts            |

**Note:** `DBNAME_INGESTION` and `DBNAME_DWH` are the recommended variables for DWH operations.
`DBNAME` is maintained for backward compatibility when both databases are the same. If
`DBNAME_INGESTION` or `DBNAME_DWH` are not set, `DBNAME` is used as a fallback.

### ETL-Specific Variables

| Variable                 | Description                | Default | Used By |
| ------------------------ | -------------------------- | ------- | ------- |
| `ETL_BATCH_SIZE`         | Records per batch          | `1000`  | ETL.sh  |
| `ETL_PARALLEL_ENABLED`   | Enable parallel processing | `true`  | ETL.sh  |
| `ETL_VACUUM_AFTER_LOAD`  | Vacuum after load          | `true`  | ETL.sh  |
| `ETL_ANALYZE_AFTER_LOAD` | Analyze after load         | `true`  | ETL.sh  |

### Profile-Specific Variables

| Variable        | Description   | Default | Used By    |
| --------------- | ------------- | ------- | ---------- |
| `OUTPUT_FORMAT` | Output format | `json`  | profile.sh |

### Configuration File

Most variables can be set in `etc/properties.sh`:

```bash
# Load configuration
source etc/properties.sh

# Execute scripts
./bin/dwh/ETL.sh
```

---

## Troubleshooting

### Common Issues

#### 1. ETL Fails with "Lock File Exists"

**Problem**: Another ETL process is running

**Solution**:

```bash
# Check for running processes
ps aux | grep ETL.sh

# If no process running, remove lock file
rm /tmp/ETL_*/ETL.lock
```

#### 2. Out of Memory During ETL

**Problem**: Large dataset causes memory issues

**Solution**:

```bash
# Reduce batch size
export ETL_BATCH_SIZE="500"

# Disable parallel processing
export ETL_PARALLEL_ENABLED="false"

# Re-run ETL (auto-detects incremental mode)
./bin/dwh/ETL.sh
```

#### 3. Database Connection Issues

**Problem**: Cannot connect to database

**Solution**:

```bash
# Verify connection
psql -h $DBHOST -p $DBPORT -U $DBUSER -d $DBNAME -c "SELECT 1"

# Check properties file
cat etc/properties.sh
```

#### 4. Slow Query Performance

**Problem**: Queries are slow

**Solution**:

```bash
# Run VACUUM ANALYZE
psql -d $DBNAME -c "VACUUM ANALYZE dwh.facts"

# Rebuild indexes if needed
psql -d $DBNAME -c "REINDEX SCHEMA dwh"
```

### Getting Help

1. Check logs: `/tmp/ETL_*/ETL.log`
2. Review documentation: `docs/`
3. Check GitHub Issues:
   [https://github.com/OSM-Notes/OSM-Notes-Analytics/issues](https://github.com/OSM-Notes/OSM-Notes-Analytics/issues)

---

## Best Practices

### Daily Operations

```bash
# Incremental update (recommended every 15 minutes, auto-detects mode)
# Production configuration: LOG_LEVEL=INFO, CLEAN=false (keeps logs for debugging)
*/15 * * * * export CLEAN=false ; export LOG_LEVEL=INFO ; export DBNAME=notes ; export DB_USER=notes ; /home/notes/OSM-Notes-Analytics/bin/dwh/ETL.sh

# Alternative: Production mode (less verbose, cleans temporary files)
# */15 * * * * export CLEAN=true ; export LOG_LEVEL=ERROR ; export DBNAME=notes ; export DB_USER=notes ; /home/notes/OSM-Notes-Analytics/bin/dwh/ETL.sh
```

### Weekly Maintenance

```bash
# VACUUM ANALYZE (recommended weekly)
psql -d $DBNAME -c "VACUUM ANALYZE dwh.facts"
```

### Monthly Tasks

```bash
# Export CSV files (15th day of month at 2 AM)
# 0 2 15 * * /home/notes/OSM-Notes-Analytics/bin/dwh/exportAndPushCSVToGitHub.sh

# ML model training/retraining (1st day of month at 4 AM)
# Script automatically detects if training or retraining is needed
# 0 4 1 * * /home/notes/OSM-Notes-Analytics/bin/dwh/ml_retrain.sh >> /tmp/ml-retrain.log 2>&1

# Check index usage
psql -d $DBNAME -c "SELECT * FROM pg_stat_user_indexes WHERE schemaname = 'dwh'"

# Review disk usage
psql -d $DBNAME -c "SELECT pg_size_pretty(pg_database_size('notes_dwh'))"
```

---

## Additional Resources

- [DWH Data Dictionary](DWH_Star_Schema_Data_Dictionary.md)
- [ETL Enhanced Features](ETL_Enhanced_Features.md)
- [DWH Maintenance Guide](DWH_Maintenance_Guide.md)
- [Partitioning Strategy](Partitioning_Strategy.md)
