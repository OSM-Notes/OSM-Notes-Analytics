---
title: "Hybrid ETL Execution Guide"
description:
  "Complete end-to-end testing and execution pipeline combining OSM Notes ingestion with analytics
  ETL, using real database operations and mocked downloads"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "etl"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Hybrid ETL Execution Guide

## Overview

The hybrid ETL execution scripts provide a complete end-to-end testing and execution pipeline that
combines the OSM Notes ingestion process (`processAPINotes.sh`) with the analytics ETL process
(`ETL.sh`). These scripts execute the ingestion process and then automatically run the ETL to update
the data warehouse after each ingestion execution.

**Key Feature:** The scripts use a **hybrid mode** that combines:

- **Real database operations** (PostgreSQL with actual data)
- **Mocked downloads** (simulated API/Planet downloads to avoid network dependencies)

This approach allows testing the complete data pipeline with realistic database operations while
avoiding slow and unreliable network downloads.

## Available Scripts

### 1. `run_processAPINotes_with_etl.sh` (Automatic Mode)

Executes the complete pipeline automatically with 4 sequential executions.

**Usage:**

```bash
cd tests
./run_processAPINotes_with_etl.sh
```

**Features:**

- Fully automated execution
- 4 complete cycles (planet + 3 API executions)
- ETL runs after each ingestion execution
- Automatic cleanup on exit

### 2. `run_processAPINotes_with_etl_controlled.sh` (Step-by-Step Mode)

Provides granular control over each step of the execution.

**Usage:**

```bash
cd tests
./run_processAPINotes_with_etl_controlled.sh [step]
```

**Steps:**

- `1` - Drop base tables and run processAPINotes.sh (planet/base)
- `2` - Run ETL after step 1
- `3` - Run processAPINotes.sh (API, 5 notes)
- `4` - Run ETL after step 3
- `5` - Run processAPINotes.sh (API, 20 notes)
- `6` - Run ETL after step 5
- `7` - Run processAPINotes.sh (API, 0 notes)
- `8` - Run ETL after step 7
- `all` - Run all steps sequentially

**Examples:**

```bash
# Run only step 1
./run_processAPINotes_with_etl_controlled.sh 1

# Run all steps
./run_processAPINotes_with_etl_controlled.sh all

# Run specific steps individually
./run_processAPINotes_with_etl_controlled.sh 3
./run_processAPINotes_with_etl_controlled.sh 4
```

## How It Works

### Architecture

The scripts orchestrate the interaction between two systems:

```mermaid
flowchart TD
    subgraph Ingestion["OSM-Notes-Ingestion"]
        API[processAPINotes.sh]
        PLANET[processPlanetNotes.sh]
        INGESTION_DESC[Populates base tables]
    end

    DB[(Database<br/>Real DB<br/>- notes<br/>- note_comments)]

    subgraph Analytics["OSM-Notes-Analytics"]
        ETL[ETL.sh]
        ETL_DESC[Transforms to star schema<br/>Updates DWH]
    end

    API -->|writes to| DB
    PLANET -->|writes to| DB
    INGESTION_DESC --> DB

    DB -->|reads from| ETL
    ETL --> ETL_DESC

    style Ingestion fill:#90EE90
    style DB fill:#E0F6FF
    style Analytics fill:#FFFFE0
```

### Hybrid Mode Configuration

The scripts configure a **hybrid environment** that:

1. **Uses Real PostgreSQL:**
   - Real `psql` client for database operations
   - Actual database connections and transactions
   - Real data persistence

2. **Mocks Network Downloads:**
   - Mock `aria2c` and `wget` for download simulation
   - Mock `pgrep` for process checking
   - Mock `ogr2ogr` for GIS operations (if needed)
   - Returns predefined test data instead of downloading from OSM

3. **Test Configuration:**
   - Uses `properties_test.sh` instead of production properties
   - Sets test database name (typically `osm-notes-test`)
   - Disables email alerts
   - Enables test mode flags

### PATH Configuration

The scripts carefully configure the `PATH` environment variable to ensure:

- Mock commands (`aria2c`, `wget`, `pgrep`, `ogr2ogr`) are found first
- Real `psql` is used (not mock)
- Real system commands (`gdalinfo`, etc.) are available

```mermaid
flowchart LR
    PATH[PATH Environment Variable]

    MOCK[hybrid_mock_dir<br/>Mock commands first]
    PSQL[real_psql_dir<br/>Real PostgreSQL]
    SYSTEM[system_paths<br/>System commands]
    REST[rest_of_path<br/>Other paths]

    PATH --> MOCK
    MOCK --> PSQL
    PSQL --> SYSTEM
    SYSTEM --> REST

    style PATH fill:#90EE90
    style MOCK fill:#FFE4B5
    style PSQL fill:#E0F6FF
    style SYSTEM fill:#FFFFE0
```

## Dependencies and Prerequisites

### Required Components

1. **OSM-Notes-Ingestion Repository:**
   - Must be located at `../OSM-Notes-Ingestion` (sibling directory)
   - Must contain:
     - `bin/process/processAPINotes.sh`
     - `tests/setup_hybrid_mock_environment.sh`
     - `tests/mock_commands/` directory
     - `etc/properties_test.sh`
     - `sql/process/processPlanetNotes_12_dropBaseTables.sql`

2. **OSM-Notes-Analytics Repository:**
   - Must contain:
     - `bin/dwh/ETL.sh`
     - `etc/properties.sh` (or `etc/properties.sh.local`)

3. **PostgreSQL Database:**
   - PostgreSQL 12+ installed and running
   - Database accessible via `psql`
   - User has permissions to create/drop tables

4. **Mock Commands:**
   - Created by `setup_hybrid_mock_environment.sh` in Ingestion repo
   - Located at `OSM-Notes-Ingestion/tests/mock_commands/`
   - Includes: `aria2c`, `wget`, `pgrep`, `ogr2ogr`

### Environment Variables

The scripts use and set these environment variables:

- `LOG_LEVEL` - Logging level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
- `DBNAME` - Database name (loaded from properties)
- `HYBRID_MOCK_MODE` - Set to `true` to enable hybrid mode
- `TEST_MODE` - Set to `true` for test execution
- `MOCK_NOTES_COUNT` - Number of notes to simulate (5, 20, 0, or unset for planet)
- `SEND_ALERT_EMAIL` - Set to `false` to disable email alerts
- `SKIP_XML_VALIDATION` - Set to `true` to skip XML validation in tests

### Database Configuration Synchronization

**Important:** Both `processAPINotes.sh` (from Ingestion) and `ETL.sh` (from Analytics) must use the
**same database**. The scripts handle this automatically:

1. **Ingestion Properties Setup:**
   - The script replaces `INGESTION_ROOT/etc/properties.sh` with `properties_test.sh`
   - This ensures `processAPINotes.sh` uses the test database configuration

2. **ETL Database Configuration:**
   - Before running ETL, the script loads database configuration from
     `INGESTION_ROOT/etc/properties.sh` (which is now the test properties)
   - It exports database variables for the ETL:
     ```bash
     export DBNAME="${DBNAME:-osm_notes}"           # Legacy: used when both DBs are same
     export DBNAME_INGESTION="${DBNAME:-osm_notes}"  # Ingestion database
     export DBNAME_DWH="${DBNAME:-osm_notes}"        # Analytics/DWH database
     ```
   - In hybrid test mode, both use the same database, so all three variables are set to the same
     value
   - This ensures the ETL uses the same database as the ingestion process

3. **Configuration Priority:**
   - Environment variables have the highest priority (see `bin/dwh/ENVIRONMENT_VARIABLES.md`)
   - The exported variables will override any values in `ANALYTICS_ROOT/etc/properties.sh`
   - For DWH operations, `DBNAME_INGESTION` and `DBNAME_DWH` are used when set
   - If `DBNAME_INGESTION` or `DBNAME_DWH` are not set, `DBNAME` is used as fallback
   - This guarantees both processes use the same database in hybrid test mode

4. **Automatic FDW Skip:**
   - When both processes use the same database, the ETL automatically detects this condition
   - The ETL compares `DBNAME_INGESTION` (or `DBNAME` if not set) with `DBNAME_DWH` (or `DBNAME` if
     not set)
   - If they are the same, FDW setup is **automatically skipped** since tables are directly
     accessible
   - The ETL logs: `"Ingestion and Analytics use same database, skipping FDW setup"`
   - This prevents SQL errors that would occur when trying to create foreign tables pointing to the
     same database

**Verification:**

```bash
# The script logs the database configuration being used:
log_info "ETL will use database: ${DBNAME}"
log_info "Configuration: DBNAME_INGESTION='${DBNAME_INGESTION}', DBNAME_DWH='${DBNAME_DWH}'"
```

**Database Variable Usage:**

- **Recommended**: Use `DBNAME_INGESTION` and `DBNAME_DWH` for DWH operations
- **Legacy/Compatibility**: `DBNAME` is maintained for backward compatibility when both databases
  are the same
- **Priority**: `DBNAME_INGESTION`/`DBNAME_DWH` > `DBNAME` (fallback)

**Current Implementation:** The `ANALYTICS_ROOT/etc/properties.sh.example` already uses the correct
pattern:

```bash
if [[ -z "${DBNAME:-}" ]]; then
 declare -r DBNAME="${DBNAME:-osm_notes}"
fi
```

This pattern respects environment variables: if `DBNAME` is already exported (as done by the hybrid
script), it will not be overridden. The variable is only set if it doesn't already exist.

**Verification:** To verify both processes use the same database, check the logs:

```bash
# Ingestion log (from processAPINotes.sh)
# Should show database from properties_test.sh

# ETL log (from ETL.sh)
log_info "ETL will use database: ${DBNAME}"
# Should show the same database name
```

## Execution Flow

### Complete Pipeline (4 Executions)

The automatic script executes 4 complete cycles:

````
```mermaid
flowchart TD
    subgraph EXEC1["EXECUTION #1: Planet/Base Load"]
        E1_1[1. Drop base tables<br/>countries, notes, note_comments]
        E1_2[2. Run processAPINotes.sh<br/>→ Detects missing tables<br/>→ Calls processPlanetNotes.sh --base<br/>→ Loads base data from mocked planet download]
        E1_3[3. Run ETL.sh<br/>→ Auto-detects first execution<br/>→ Creates DWH schema if needed<br/>→ Loads facts and dimensions from base tables<br/>→ Updates datamarts]

        E1_1 --> E1_2
        E1_2 --> E1_3
    end

    subgraph EXEC2["EXECUTION #2: API Sequential 5 notes"]
        E2_1[1. Base tables exist no drop]
        E2_2[2. Set MOCK_NOTES_COUNT=5]
        E2_3[3. Run processAPINotes.sh<br/>→ Uses API mode not planet<br/>→ Processes 5 notes sequentially < 10 notes<br/>→ Updates base tables with new notes]
        E2_4[4. Run ETL.sh<br/>→ Auto-detects incremental execution<br/>→ Processes only new data since last run<br/>→ Updates facts and dimensions<br/>→ Updates datamarts]

        E2_1 --> E2_2
        E2_2 --> E2_3
        E2_3 --> E2_4
    end

    style EXEC1 fill:#90EE90
    style EXEC2 fill:#FFFFE0
````

```mermaid
flowchart TD
    subgraph EXEC3["EXECUTION #3: API Parallel 20 notes"]
        E3_1[1. Base tables exist no drop]
        E3_2[2. Set MOCK_NOTES_COUNT=20]
        E3_3[3. Run processAPINotes.sh<br/>→ Uses API mode not planet<br/>→ Processes 20 notes in parallel >= 10 notes<br/>→ Updates base tables with new notes]
        E3_4[4. Run ETL.sh<br/>→ Auto-detects incremental execution<br/>→ Processes only new data since last run<br/>→ Updates facts and dimensions<br/>→ Updates datamarts]

        E3_1 --> E3_2
        E3_2 --> E3_3
        E3_3 --> E3_4
    end

    subgraph EXEC4["EXECUTION #4: API Empty 0 notes"]
        E4_1[1. Base tables exist no drop]
        E4_2[2. Set MOCK_NOTES_COUNT=0]
        E4_3[3. Run processAPINotes.sh<br/>→ Uses API mode not planet<br/>→ Receives empty response no new notes<br/>→ Handles gracefully no errors]
        E4_4[4. Run ETL.sh<br/>→ Processes only new data since last run<br/>→ No new data to process<br/>→ Updates datamarts may have no changes]

        E4_1 --> E4_2
        E4_2 --> E4_3
        E4_3 --> E4_4
    end

    style EXEC3 fill:#FFE4B5
    style EXEC4 fill:#FFB6C1
```

## Expected Behavior in Each Iteration

### Execution #1: Planet/Base Load

**Purpose:** Simulate initial data load from OSM Planet file.

**Setup:**

- Drops all base tables (`countries`, `notes`, `note_comments`, `logs`, `tries`)
- Unsets `MOCK_NOTES_COUNT` (triggers planet mode)
- Configures hybrid environment

**Expected Behavior:**

1. **processAPINotes.sh:**
   - Detects missing base tables
   - Calls `processPlanetNotes.sh --base`
   - Uses mocked `aria2c`/`wget` to "download" planet file
   - Mock returns predefined test data
   - Creates base tables: `countries`, `notes`, `note_comments`, `note_comments_text`
   - Populates tables with test data
   - **Expected Result:** Base tables created and populated

2. **ETL.sh:**
   - Auto-detects DWH schema doesn't exist (first run)
   - Creates DWH schema and all dimension tables
   - Creates partitioned facts table
   - Loads facts from `note_comments` table
   - Populates dimension tables (users, countries, dates, etc.)
   - Creates indexes and constraints
   - Updates datamarts (countries, users, global)
   - **Expected Result:** Complete DWH created with initial data

**Verification:**

```sql
-- Check base tables
SELECT COUNT(*) FROM notes;
SELECT COUNT(*) FROM note_comments;

-- Check DWH
SELECT COUNT(*) FROM dwh.facts;
SELECT COUNT(*) FROM dwh.dimension_users;
SELECT COUNT(*) FROM dwh.dimension_countries;
```

### Execution #2: API Sequential (5 notes)

**Purpose:** Test incremental API updates with small batch (sequential processing).

**Setup:**

- Base tables exist (from Execution #1)
- Sets `MOCK_NOTES_COUNT=5` (triggers API mode with 5 notes)
- No table drops

**Expected Behavior:**

1. **processAPINotes.sh:**
   - Detects base tables exist (no planet call)
   - Uses API mode
   - Mock API returns 5 notes
   - Processes notes sequentially (< 10 notes threshold)
   - Inserts/updates notes in base tables
   - **Expected Result:** 5 new/updated notes in base tables

2. **ETL.sh:**
   - Detects DWH exists (not first run)
   - Uses incremental mode
   - Processes only new/updated data since last ETL run
   - Updates facts table with new note comments
   - Updates dimension tables if needed (new users, etc.)
   - Updates datamarts incrementally
   - **Expected Result:** DWH updated with 5 new notes' data

**Verification:**

```sql
-- Check new notes added
SELECT COUNT(*) FROM notes WHERE created_at > (SELECT MAX(created_at) - INTERVAL '1 hour' FROM notes);

-- Check facts updated
SELECT COUNT(*) FROM dwh.facts WHERE action_at > (SELECT MAX(action_at) - INTERVAL '1 hour' FROM dwh.facts);
```

### Execution #3: API Parallel (20 notes)

**Purpose:** Test incremental API updates with larger batch (parallel processing).

**Setup:**

- Base tables exist
- Sets `MOCK_NOTES_COUNT=20` (triggers API mode with 20 notes)
- No table drops

**Expected Behavior:**

1. **processAPINotes.sh:**
   - Detects base tables exist (no planet call)
   - Uses API mode
   - Mock API returns 20 notes
   - Processes notes in parallel (>= 10 notes threshold)
   - Uses multiple worker processes
   - Inserts/updates notes in base tables
   - **Expected Result:** 20 new/updated notes in base tables

2. **ETL.sh:**
   - Uses incremental mode
   - Processes only new/updated data since last ETL run
   - Updates facts table with new note comments
   - Updates dimension tables if needed
   - Updates datamarts incrementally
   - **Expected Result:** DWH updated with 20 new notes' data

**Verification:**

```sql
-- Check parallel processing worked
SELECT COUNT(*) FROM notes WHERE created_at > (SELECT MAX(created_at) - INTERVAL '1 hour' FROM notes);
-- Should show ~20 new notes (may vary based on test data)
```

### Execution #4: API Empty (0 notes)

**Purpose:** Test handling of empty API responses (no new notes scenario).

**Setup:**

- Base tables exist
- Sets `MOCK_NOTES_COUNT=0` (triggers API mode with empty response)
- No table drops

**Expected Behavior:**

1. **processAPINotes.sh:**
   - Detects base tables exist (no planet call)
   - Uses API mode
   - Mock API returns empty response (0 notes)
   - Handles gracefully (no errors)
   - No database changes
   - **Expected Result:** No errors, graceful handling of empty response

2. **ETL.sh:**
   - Uses incremental mode
   - Detects no new data since last run
   - Skips data processing (no new facts)
   - May still update datamarts (to refresh aggregations)
   - **Expected Result:** ETL completes successfully with no new data

**Verification:**

```sql
-- Verify no new data
SELECT COUNT(*) FROM notes WHERE created_at > (SELECT MAX(created_at) - INTERVAL '1 hour' FROM notes);
-- Should be 0 or same as before
```

## Cleanup and Error Handling

### Automatic Cleanup

The scripts automatically clean up on exit (via trap handlers):

1. **Restore Properties:**
   - Restores original `properties.sh` from backup
   - Removes backup file

2. **Remove Mock Directories:**
   - Removes temporary hybrid mock directory (`/tmp/hybrid_mock_commands_*`)
   - Cleans up PATH environment variable

3. **Remove Lock Files:**
   - Removes process lock files:
     - `/tmp/processAPINotes.lock`
     - `/tmp/processPlanetNotes.lock`
     - `/tmp/updateCountries.lock`
   - Removes failed execution flags

4. **Unset Environment Variables:**
   - Unsets `HYBRID_MOCK_MODE`
   - Unsets `TEST_MODE`
   - Unsets `HYBRID_MOCK_DIR`

### Error Handling

- **Process Failures:** Scripts continue to next execution even if one fails
- **ETL Failures:** Logged but don't stop the pipeline
- **Cleanup on Interrupt:** Trap handlers ensure cleanup on SIGINT/SIGTERM
- **Exit Codes:** Script exits with non-zero code if any execution fails

## Troubleshooting

### Common Issues

#### 1. "OSM-Notes-Ingestion directory not found"

**Problem:** The script cannot find the Ingestion repository.

**Solution:**

```bash
# Verify directory structure
ls -la ../OSM-Notes-Ingestion

# Should show:
# ../OSM-Notes-Ingestion/
#   ├── bin/
#   ├── tests/
#   └── etc/
```

#### 2. "Hybrid setup script not found"

**Problem:** Missing `setup_hybrid_mock_environment.sh` in Ingestion repo.

**Solution:**

```bash
# Check if file exists
ls -la ../OSM-Notes-Ingestion/tests/setup_hybrid_mock_environment.sh

# If missing, it may need to be created in the Ingestion repository
```

#### 3. "Mock psql is being used instead of real psql"

**Problem:** PATH configuration is incorrect, mock psql is being used.

**Solution:**

```bash
# Verify real psql is available
which psql
# Should show: /usr/bin/psql or similar (not mock_commands/psql)

# Check PATH
echo $PATH | grep -o '[^:]*psql[^:]*'
```

#### 4. "ETL failed with exit code: 3"

**Problem:** ETL script encountered an error.

**Solution:**

```bash
# Check ETL logs
tail -50 $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log

# Check database connection
psql -d osm-notes-test -c "SELECT version();"

# Verify base tables have data
psql -d osm-notes-test -c "SELECT COUNT(*) FROM notes;"
```

#### 5. "processAPINotes.sh exited with code: 248"

**Problem:** Ingestion script failed (often related to missing dependencies or configuration).

**Solution:**

```bash
# Check Ingestion logs
# Logs are typically in /tmp/processAPINotes_* or similar

# Verify test properties file exists
ls -la ../OSM-Notes-Ingestion/etc/properties_test.sh

# Check mock commands exist
ls -la ../OSM-Notes-Ingestion/tests/mock_commands/
```

## Integration with CI/CD

These scripts are designed to be used in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Hybrid ETL Test
  run: |
    cd tests
    ./run_processAPINotes_with_etl.sh
  env:
    LOG_LEVEL: INFO
    DBNAME: osm-notes-test
```

## Best Practices

1. **Use Test Database:** Always use a test database (not production)
2. **Check Prerequisites:** Verify all dependencies before running
3. **Monitor Logs:** Watch logs during execution to catch issues early
4. **Clean State:** Start with a clean database state for consistent results
5. **Incremental Testing:** Use controlled mode for debugging specific steps
6. **Verify Results:** Always verify database state after each execution

## Related Documentation

- [ETL Enhanced Features](ETL_Enhanced_Features.md) - ETL capabilities and features
- [DWH Star Schema ERD](DWH_Star_Schema_ERD.md) - Data warehouse structure
- [Troubleshooting Guide](Troubleshooting_Guide.md) - Common issues and solutions
- [Execution Guide](Execution_Guide.md) - General execution documentation
