---
title: "Troubleshooting Guide"
description:
  "This comprehensive troubleshooting guide consolidates common problems and solutions for the"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "troubleshooting"
  - "guide"
audience:
  - "users"
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Troubleshooting Guide

This comprehensive troubleshooting guide consolidates common problems and solutions for the
OSM-Notes-Analytics system. Problems are organized by category for easy navigation.

## Database Configuration

**Note:** For DWH operations, use `DBNAME_INGESTION` and `DBNAME_DWH` variables. The examples in
this guide uses `${DBNAME:-notes_dwh}` as a fallback for simplicity, but in production you should use
the specific variables:

```bash
# Recommended configuration
export DBNAME_INGESTION="notes"
export DBNAME_DWH="notes_dwh"

# For commands checking Ingestion tables, use DBNAME_INGESTION or DBNAME
# For commands checking DWH tables, use DBNAME_DWH or DBNAME
```

The `DBNAME` variable is maintained for backward compatibility when both databases are the same.

## Table of Contents

- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [ETL Issues](#etl-issues)
- [Database Issues](#database-issues)
- [Datamart Issues](#datamart-issues)
- [Performance Issues](#performance-issues)
- [Export Issues](#export-issues)
- [Profile Generation Issues](#profile-generation-issues)
- [Configuration Issues](#configuration-issues)
- [Integration Issues](#integration-issues)
- [Recovery Procedures](#recovery-procedures)
- [Getting Help](#getting-help)

---

## Quick Diagnostic Commands

Use these commands to quickly assess system health:

```bash
# Check if ETL is running
ps aux | grep -E "ETL\.sh|datamart"

# Check lock files
ls -la /tmp/ETL_*.lock 2>/dev/null
ls -la /tmp/datamart*_*.lock 2>/dev/null

# Find latest logs
LATEST_ETL=$(ls -1rtd /tmp/ETL_* 2>/dev/null | tail -1)
LATEST_DATAMART=$(ls -1rtd /tmp/datamart*_* 2>/dev/null | tail -1)
echo "ETL log: $LATEST_ETL"
echo "Datamart log: $LATEST_DATAMART"

# Check database connection
psql -d "${DBNAME:-notes_dwh}" -c "SELECT version();"

# Check DWH schema exists
psql -d "${DBNAME:-notes_dwh}" -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'dwh';"

# Check base tables (from ingestion)
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM notes;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM note_comments;"

# Check DWH tables
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartusers;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartcountries;"

# Check disk space
df -h

# Check memory
free -h
```

---

## ETL Issues

### Problem: "Schema 'dwh' does not exist"

**Symptoms:**

- Error: `schema "dwh" does not exist`
- ETL fails immediately
- Cannot find DWH tables

**Diagnosis:**

```bash
# Check if schema exists
psql -d "${DBNAME:-notes_dwh}" -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'dwh';"

# Check if ETL has been run
psql -d "${DBNAME:-notes_dwh}" -c "SELECT tablename FROM pg_tables WHERE schemaname = 'dwh' LIMIT 1;"
```

**Solutions:**

1. **Run initial ETL:**

   ```bash
   ./bin/dwh/ETL.sh
   ```

2. **Verify base tables exist first:**
   ```bash
   psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM notes;"
   # If empty or doesn't exist, run OSM-Notes-Ingestion first
   ```

### Problem: ETL Fails to Start

**Symptoms:**

- ETL script exits immediately
- No logs generated
- Error messages about prerequisites

**Diagnosis:**

```bash
# Check prerequisites
./bin/dwh/ETL.sh --help

# Check base tables exist
psql -d "${DBNAME:-notes_dwh}" -c "\dt notes"
psql -d "${DBNAME:-notes_dwh}" -c "\dt note_comments"

# Check database connection
psql -d "${DBNAME:-notes_dwh}" -c "SELECT 1;"

# Check configuration files
ls -la etc/properties.sh
ls -la etc/etl.properties
```

**Solutions:**

1. **Verify base tables exist:**

   ```bash
   # Base tables must be populated by OSM-Notes-Ingestion
   psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM notes;"
   psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM note_comments;"

   # If empty, run ingestion system first
   # See: https://github.com/OSM-Notes/OSM-Notes-Ingestion
   ```

2. **Create configuration files:**

   ```bash
   cp etc/properties.sh.example etc/properties.sh
   cp etc/etl.properties.example etc/etl.properties
   nano etc/properties.sh  # Edit with your database credentials
   ```

3. **Check PostgreSQL is running:**
   ```bash
   sudo systemctl status postgresql
   sudo systemctl start postgresql  # If not running
   ```

### Problem: ETL Takes Too Long

**Symptoms:**

- ETL runs for hours without progress
- System becomes unresponsive
- Timeout errors

**Diagnosis:**

```bash
# Check current ETL progress
tail -f $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log

# Check system resources
top
free -h
df -h

# Check database activity
# All scripts now use descriptive application names for better identification
# This makes it easy to identify which script is running each query
psql -d "${DBNAME:-notes_dwh}" -c "SELECT pid, application_name, state, query FROM pg_stat_activity WHERE application_name IN ('ETL', 'datamartUsers', 'datamartCountries', 'datamartGlobal') OR application_name LIKE 'ETL-year-%' OR application_name LIKE 'datamartUsers-%';"

# Monitor specific ETL year processes
psql -d "${DBNAME:-notes_dwh}" -c "SELECT pid, application_name, state, now() - state_change AS duration, query FROM pg_stat_activity WHERE application_name LIKE 'ETL-year-%' ORDER BY application_name;"

# Monitor datamart user processing
psql -d "${DBNAME:-notes_dwh}" -c "SELECT pid, application_name, state, now() - state_change AS duration, query FROM pg_stat_activity WHERE application_name LIKE 'datamartUsers-%' ORDER BY application_name;"
```

**Solutions:**

1. **Increase timeouts for large operations:**

   ```bash
   # For large incremental updates (> 100K facts)
   export PSQL_STATEMENT_TIMEOUT=2h

   # For initial load
   export PSQL_STATEMENT_TIMEOUT=4h
   export ETL_TIMEOUT=129600  # 36 hours

   # See ../bin/dwh/ENVIRONMENT_VARIABLES.md for details
   ```

2. **Increase parallelism:**

   ```bash
   # Edit etc/etl.properties
   ETL_MAX_PARALLEL_JOBS=8  # Increase for more CPU cores
   ETL_BATCH_SIZE=5000     # Increase for better throughput
   ```

3. **Optimize base tables:**

   ```bash
   # Run VACUUM ANALYZE on base tables
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE notes;"
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE note_comments;"
   ```

4. **Check for missing indexes:**

   ```bash
   # Verify indexes exist on base tables
   psql -d "${DBNAME:-notes_dwh}" -c "\d notes"
   psql -d "${DBNAME:-notes_dwh}" -c "\d note_comments"
   ```

5. **Run ETL for updates (auto-detects mode):**
   ```bash
   # Same command works for both initial setup and incremental updates
   ./bin/dwh/ETL.sh
   ```

### Problem: Statement Timeout Error

**Symptoms:**

- Error: `canceling statement due to statement timeout`
- ETL fails during `process_notes_actions_into_dwh()` stage
- Process runs for ~30 minutes then fails

**Diagnosis:**

```bash
# Check current timeout setting
grep PSQL_STATEMENT_TIMEOUT etc/properties.sh

# Check how many facts are being processed
psql -d "${DBNAME_DWH:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"

# Check latest processed timestamp
psql -d "${DBNAME_DWH:-notes_dwh}" -c "SELECT MAX(action_at) FROM dwh.facts;"
```

**Solutions:**

1. **Increase statement timeout for large operations:**

   ```bash
   # For large incremental updates (> 100K facts)
   export PSQL_STATEMENT_TIMEOUT=2h
   ./bin/dwh/ETL.sh

   # For initial load
   export PSQL_STATEMENT_TIMEOUT=4h
   export ETL_TIMEOUT=129600  # 36 hours
   ./bin/dwh/ETL.sh
   ```

2. **Configure permanently in properties file:**

   ```bash
   # Edit etc/properties.sh
   export PSQL_STATEMENT_TIMEOUT=2h  # For large incrementals
   # or
   export PSQL_STATEMENT_TIMEOUT=4h  # For initial loads
   ```

3. **Check if this should be an initial load instead:**
   - If processing > 1M facts, consider doing initial load
   - Initial load has longer timeouts and better parallelization

**See also:** [Environment Variables](../bin/dwh/Environment_Variables.md) for timeout configuration
details.

### Problem: ETL Fails Mid-Execution

**Symptoms:**

- ETL starts but fails partway through
- Error messages in logs
- Partial data loaded

**Diagnosis:**

```bash
# Check latest ETL log
LATEST_ETL=$(ls -1rtd /tmp/ETL_* | tail -1)
tail -100 "$LATEST_ETL/ETL.log"

# Check for specific errors
grep -i "error\|fatal\|failed" "$LATEST_ETL/ETL.log" | tail -20

# Check database state
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"
```

**Solutions:**

1. **Check error messages:**

   ```bash
   # Review full error in log
   cat "$LATEST_ETL/ETL.log" | grep -A 10 -B 10 "ERROR"
   ```

2. **Fix underlying issue:**
   - Database connection problems → Check PostgreSQL
   - Out of memory → Reduce ETL_MAX_PARALLEL_JOBS
   - Disk full → Free up space
   - Base table issues → Check ingestion system

3. **Resume from checkpoint (if recovery enabled):**

   ```bash
   # ETL recovery should automatically resume from last checkpoint
   ./bin/dwh/ETL.sh
   ```

4. **Clean and restart (if needed):**
   ```bash
   # Use cleanup script (WARNING: removes data)
   ./bin/dwh/cleanupDWH.sh --dry-run  # Preview first
   ./bin/dwh/cleanupDWH.sh --remove-all-data
   ./bin/dwh/ETL.sh  # Will auto-detect and recreate DWH
   ```

---

## Database Issues

### Problem: Cannot Connect to Database

**Symptoms:**

- Error: "could not connect to server"
- Scripts fail immediately
- Database operations timeout

**Diagnosis:**

```bash
# Check PostgreSQL service
sudo systemctl status postgresql

# Test connection
psql -d "${DBNAME:-notes_dwh}" -c "SELECT 1;"

# Check credentials
cat etc/properties.sh | grep -E "DBNAME|DB_USER"

# Verify database exists
psql -l | grep "${DBNAME:-notes_dwh}"
```

**Solutions:**

1. **Start PostgreSQL:**

   ```bash
   sudo systemctl start postgresql
   sudo systemctl enable postgresql
   ```

2. **Verify credentials:**

   ```bash
   # Create properties file if missing
   cp etc/properties.sh.example etc/properties.sh
   nano etc/properties.sh  # Edit with correct credentials
   ```

3. **Create database if missing:**
   ```bash
   createdb "${DBNAME:-notes_dwh}"
   psql -d "${DBNAME:-notes_dwh}" -c "CREATE EXTENSION IF NOT EXISTS postgis;"
   ```

### Problem: Database Out of Space

**Symptoms:**

- Error: "No space left on device"
- Database operations fail
- Disk usage at 100%

**Diagnosis:**

```bash
# Check disk space
df -h

# Check database size
psql -d "${DBNAME:-notes_dwh}" -c "SELECT pg_size_pretty(pg_database_size('${DBNAME:-notes_dwh}'));"

# Check table sizes
psql -d "${DBNAME:-notes_dwh}" -c "
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'dwh'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
"

# Check temporary files
du -sh /tmp/ETL_* 2>/dev/null
```

**Solutions:**

1. **Free up disk space:**

   ```bash
   # Remove old log directories
   find /tmp -name "ETL_*" -type d -mtime +7 -exec rm -rf {} \;
   find /tmp -name "datamart*_*" -type d -mtime +7 -exec rm -rf {} \;
   ```

2. **Vacuum database:**

   ```bash
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE dwh.facts;"
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE dwh.datamartusers;"
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE dwh.datamartcountries;"
   ```

3. **Archive old partitions:**
   ```bash
   # Detach old year partitions if needed
   psql -d "${DBNAME:-notes_dwh}" -c "ALTER TABLE dwh.facts DETACH PARTITION dwh.facts_2013;"
   ```

---

## Datamart Issues

### Problem: "Table 'dwh.datamartusers' does not exist"

**Symptoms:**

- Error: `relation "dwh.datamartusers" does not exist`
- Profile generation fails
- Export fails

**Diagnosis:**

```bash
# Check if datamart tables exist
psql -d "${DBNAME:-notes_dwh}" -c "SELECT tablename FROM pg_tables WHERE schemaname = 'dwh' AND tablename LIKE 'datamart%';"

# Check if ETL has completed
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"
```

**Solutions:**

1. **Run datamart scripts:**

   ```bash
   ./bin/dwh/datamartUsers/datamartUsers.sh
   ./bin/dwh/datamartCountries/datamartCountries.sh
   ./bin/dwh/datamartGlobal/datamartGlobal.sh
   ```

2. **Or run ETL (which updates datamarts automatically):**
   ```bash
   ./bin/dwh/ETL.sh
   ```

### Problem: Datamart Not Fully Populated

**Symptoms:**

- Datamart tables exist but have few rows
- Missing users or countries
- Incomplete data

**Diagnosis:**

```bash
# Check datamart counts
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartusers;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartcountries;"

# Check dimension counts
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.dimension_users;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.dimension_countries;"

# Check for users that need processing
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.dimension_users WHERE modified = TRUE;"
```

**Solutions:**

1. **For users datamart (incremental processing):**

   ```bash
   # Run multiple times until all users processed
   while true; do
     ./bin/dwh/datamartUsers/datamartUsers.sh
     sleep 5
     # Check if done
     COUNT=$(psql -d "${DBNAME:-notes_dwh}" -t -c "SELECT COUNT(*) FROM dwh.dimension_users WHERE modified = TRUE;")
     if [[ "$COUNT" -eq 0 ]]; then
       echo "All users processed"
       break
     fi
   done
   ```

2. **For countries datamart:**

   ```bash
   # Countries datamart processes all at once
   ./bin/dwh/datamartCountries/datamartCountries.sh
   ```

3. **Check ETL completed:**
   ```bash
   # Ensure ETL has processed all facts
   psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"
   ```

---

## Performance Issues

### Problem: Slow Queries

**Symptoms:**

- Queries take very long
- Timeouts
- High CPU usage

**Diagnosis:**

```bash
# Analyze query performance
psql -d "${DBNAME:-notes_dwh}" -c "EXPLAIN ANALYZE SELECT COUNT(*) FROM dwh.facts;"

# Check table statistics
psql -d "${DBNAME:-notes_dwh}" -c "SELECT schemaname, tablename, last_analyze FROM pg_stat_user_tables WHERE schemaname = 'dwh';"

# Check index usage
psql -d "${DBNAME:-notes_dwh}" -c "SELECT schemaname, tablename, indexname, idx_scan FROM pg_stat_user_indexes WHERE schemaname = 'dwh' ORDER BY idx_scan;"
```

**Solutions:**

1. **Update statistics:**

   ```bash
   psql -d "${DBNAME:-notes_dwh}" -c "ANALYZE dwh.facts;"
   psql -d "${DBNAME:-notes_dwh}" -c "ANALYZE dwh.datamartusers;"
   psql -d "${DBNAME:-notes_dwh}" -c "ANALYZE dwh.datamartcountries;"
   ```

2. **Vacuum tables:**

   ```bash
   psql -d "${DBNAME:-notes_dwh}" -c "VACUUM ANALYZE dwh.facts;"
   ```

3. **Check partition pruning:**
   ```bash
   # Ensure queries filter by year for partition pruning
   psql -d "${DBNAME:-notes_dwh}" -c "EXPLAIN SELECT * FROM dwh.facts WHERE action_at >= '2024-01-01' AND action_at < '2025-01-01';"
   ```

### Problem: Out of Memory

**Symptoms:**

- ETL fails with memory errors
- System becomes unresponsive
- OOM killer terminates processes

**Diagnosis:**

```bash
# Check memory usage
free -h
top

# Check ETL configuration
cat etc/etl.properties | grep -E "ETL_MAX_PARALLEL_JOBS|ETL_BATCH_SIZE"
```

**Solutions:**

1. **Reduce parallelism:**

   ```bash
   # Edit etc/etl.properties
   ETL_MAX_PARALLEL_JOBS=2  # Reduce from default 4
   ETL_BATCH_SIZE=500       # Reduce from default 1000
   ```

2. **Disable parallel processing:**

   ```bash
   export ETL_PARALLEL_ENABLED=false
   ./bin/dwh/ETL.sh
   ```

3. **Increase system memory** or use swap space

---

## Export Issues

### Problem: JSON Export is Empty

**Symptoms:**

- Export completes but no files created
- Empty JSON files
- Export fails silently

**Diagnosis:**

```bash
# Check datamart counts
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartusers;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartcountries;"

# Check output directory
ls -lh ./output/json/

# Check export logs
tail -f $(ls -1rtd /tmp/exportDatamartsToJSON_* | tail -1)/exportDatamartsToJSON.log
```

**Solutions:**

1. **Ensure datamarts are populated:**

   ```bash
   # Re-run datamart scripts
   ./bin/dwh/datamartUsers/datamartUsers.sh
   ./bin/dwh/datamartCountries/datamartCountries.sh
   ```

2. **Check output directory permissions:**

   ```bash
   mkdir -p ./output/json
   chmod 755 ./output/json
   ```

3. **Run export with debug logging:**
   ```bash
   export LOG_LEVEL=DEBUG
   ./bin/dwh/exportDatamartsToJSON.sh
   ```

### Problem: JSON Export Validation Fails

**Symptoms:**

- Export fails with validation errors
- Schema validation errors
- Files not moved to final location

**Diagnosis:**

```bash
# Check validation errors
tail -100 $(ls -1rtd /tmp/exportDatamartsToJSON_* | tail -1)/exportDatamartsToJSON.log | grep -i "valid\|error"

# Check if ajv is installed
which ajv
ajv --version
```

**Solutions:**

1. **Install validation tools:**

   ```bash
   sudo npm install -g ajv-cli
   ```

2. **Check schema files:**

   ```bash
   ls -la lib/osm-common/schemas/
   ```

3. **Skip validation (not recommended):**
   ```bash
   # Only if absolutely necessary
   # Modify export script to skip validation
   ```

---

## Profile Generation Issues

### Problem: "Profile not found"

**Symptoms:**

- Error: User or country not found
- Profile script returns empty results
- No data displayed

**Diagnosis:**

```bash
# Check if user exists in datamart
psql -d "${DBNAME:-notes_dwh}" -c "SELECT username FROM dwh.datamartusers WHERE username = 'AngocA';"

# Check if country exists
psql -d "${DBNAME:-notes_dwh}" -c "SELECT country_name_en FROM dwh.datamartcountries WHERE country_name_en = 'Colombia';"

# Check datamart has data
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.datamartusers;"
```

**Solutions:**

1. **Use exact name as stored in database:**

   ```bash
   # Check exact spelling
   psql -d "${DBNAME:-notes_dwh}" -c "SELECT username FROM dwh.datamartusers WHERE username ILIKE '%angoca%';"

   # Try both English and Spanish for countries
   ./bin/dwh/profile.sh --country Colombia
   ./bin/dwh/profile.sh --pais Colombia
   ```

2. **Ensure datamart is populated:**
   ```bash
   ./bin/dwh/datamartUsers/datamartUsers.sh
   ./bin/dwh/datamartCountries/datamartCountries.sh
   ```

---

## Configuration Issues

### Problem: Configuration Not Found

**Symptoms:**

- Error: "properties.sh not found"
- Scripts fail to start
- Default values used incorrectly

**Diagnosis:**

```bash
# Check if configuration files exist
ls -la etc/properties.sh
ls -la etc/etl.properties

# Check if example files exist
ls -la etc/properties.sh.example
ls -la etc/etl.properties.example
```

**Solutions:**

1. **Create configuration files:**

   ```bash
   cp etc/properties.sh.example etc/properties.sh
   cp etc/etl.properties.example etc/etl.properties
   nano etc/properties.sh  # Edit with your settings
   ```

2. **Verify configuration is loaded:**
   ```bash
   # Test with debug logging
   export LOG_LEVEL=DEBUG
   ./bin/dwh/ETL.sh --help
   ```

---

## Integration Issues

### Problem: Base Tables Missing

**Symptoms:**

- Error: "relation 'notes' does not exist"
- ETL cannot find base tables
- Integration with ingestion system broken

**Diagnosis:**

```bash
# Check base tables exist
psql -d "${DBNAME:-notes_dwh}" -c "\dt notes"
psql -d "${DBNAME:-notes_dwh}" -c "\dt note_comments"

# Check table counts
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM notes;"
```

**Solutions:**

1. **Run ingestion system first:**

   ```bash
   # See: https://github.com/OSM-Notes/OSM-Notes-Ingestion
   # Follow ingestion setup instructions
   ```

2. **Verify same database:**
   ```bash
   # Ensure both systems use same database
   # Check etc/properties.sh in both repos
   ```

---

## Recovery Procedures

### Recovering from Failed ETL

1. **Check logs:**

   ```bash
   LATEST_ETL=$(ls -1rtd /tmp/ETL_* | tail -1)
   tail -100 "$LATEST_ETL/ETL.log"
   ```

2. **Fix underlying issue** (database, memory, disk, etc.)

3. **Resume ETL:**
   ```bash
   # Recovery should automatically resume from checkpoint
   ./bin/dwh/ETL.sh
   ```

### Recovering from Corrupted Data

1. **Backup current data:**

   ```bash
   pg_dump -d "${DBNAME:-notes_dwh}" -n dwh > dwh_backup.sql
   ```

2. **Clean and restart:**
   ```bash
   ./bin/dwh/cleanupDWH.sh --dry-run  # Preview
   ./bin/dwh/cleanupDWH.sh --remove-all-data
   ./bin/dwh/ETL.sh
   ```

---

## Getting Help

### Before Asking for Help

1. **Check logs:**

   ```bash
   # Find latest logs
   ls -1rtd /tmp/ETL_* | tail -1
   ls -1rtd /tmp/datamart*_* | tail -1
   ```

2. **Run diagnostics:**

   ```bash
   # Use quick diagnostic commands above
   ```

3. **Review documentation:**
   - [README.md](../README.md)
   - [bin/README.md](../bin/README.md)
   - [Entry Points](../bin/dwh/Entry_Points.md)
   - [Environment Variables](../bin/dwh/Environment_Variables.md)

### Creating an Issue

When creating an issue, include:

1. **Error messages** (full text)
2. **Log files** (relevant sections)
3. **System information:**
   - PostgreSQL version
   - OS version
   - Available memory/disk
4. **Steps to reproduce**
5. **Configuration** (sanitized, no passwords)

### Useful Commands for Issue Reports

```bash
# System info
uname -a
psql --version
free -h
df -h

# Database info
psql -d "${DBNAME:-notes_dwh}" -c "SELECT version();"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM notes;"
psql -d "${DBNAME:-notes_dwh}" -c "SELECT COUNT(*) FROM dwh.facts;"

# Latest logs
tail -50 $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log
```

---

## See Also

- [README.md](../README.md) - Project overview
- [bin/README.md](../bin/README.md) - Script documentation
- [Entry Points](../bin/dwh/Entry_Points.md) - Script entry points
- [Environment Variables](../bin/dwh/Environment_Variables.md) - Configuration
- [ETL Enhanced Features](ETL_Enhanced_Features.md) - ETL capabilities
- [DWH Maintenance Guide](DWH_Maintenance_Guide.md) - Maintenance procedures
