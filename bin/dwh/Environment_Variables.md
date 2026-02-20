# Environment Variables Documentation

**Purpose:** Define standard environment variables for OSM-Notes-Analytics DWH system

## Overview

This document defines all environment variables used across the OSM-Notes-Analytics DWH system,
categorized as:

- **Common**: Used by all scripts
- **ETL-Specific**: Specific to ETL process
- **Per-Script**: Specific to individual entry points
- **Properties File**: Defined in configuration files (can be overridden by environment)
- **Internal**: Used internally (do not modify)

## ✅ Common Variables

These variables are used across **all scripts** and should be standardized:

### `LOG_LEVEL`

- **Purpose**: Controls logging verbosity
- **Values**: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`
- **Default**: `ERROR`
- **Usage**: Set higher for debugging, lower for production
- **Example**:
  ```bash
  export LOG_LEVEL=DEBUG
  ./bin/dwh/ETL.sh
  ```

### `CLEAN`

- **Purpose**: Whether to delete temporary files after processing
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Set to `false` to keep files for debugging
- **Example**:
  ```bash
  export CLEAN=false
  ./bin/dwh/ETL.sh
  # Files will remain in /tmp/ETL_*/
  ```

### Database Name Variables

#### `DBNAME_INGESTION` (Recommended)

- **Purpose**: PostgreSQL database name for Ingestion system
- **Values**: String (e.g., `notes_dwh`)
- **Default**: `notes_dwh` (from `etc/properties.sh`, or `DBNAME` if not set)
- **Usage**: Specify the Ingestion database when it differs from Analytics database
- **Example**:
  ```bash
  export DBNAME_INGESTION=notes
  export DBNAME_DWH=notes_dwh
  ./bin/dwh/ETL.sh
  ```

#### `DBNAME_DWH` (Recommended)

- **Purpose**: PostgreSQL database name for Analytics/DWH system
- **Values**: String (e.g., `notes_dwh`)
- **Default**: `notes_dwh` (from `etc/properties.sh`, or `DBNAME` if not set)
- **Usage**: Specify the Analytics database when it differs from Ingestion database
- **Example**:
  ```bash
  export DBNAME_INGESTION=notes
  export DBNAME_DWH=notes_dwh
  ./bin/dwh/ETL.sh
  ```

#### `DBNAME` (Legacy/Compatibility)

- **Purpose**: PostgreSQL database name (legacy variable for backward compatibility)
- **Values**: String (e.g., `notes_dwh`, `osm_notes_analytics_test`)
- **Default**: `notes_dwh` (from `etc/properties.sh`)
- **Usage**: Use when both Ingestion and Analytics use the same database. This is a fallback if
  `DBNAME_INGESTION` or `DBNAME_DWH` are not set.
- **Example**:
  ```bash
  export DBNAME=osm_notes_analytics_test
  ./bin/dwh/ETL.sh
  ```

**Note:** For DWH operations, `DBNAME_INGESTION` and `DBNAME_DWH` are recommended. The `DBNAME`
variable is maintained for backward compatibility and is used as a fallback when the specific
variables are not set.

### `DB_USER`

- **Purpose**: PostgreSQL database user
- **Values**: String (e.g., `notes`, `postgres`)
- **Default**: `notes` (from `etc/properties.sh`)
- **Usage**: Override for different database users
- **Example**:
  ```bash
  export DB_USER=postgres
  ./bin/dwh/ETL.sh
  ```

## 📝 ETL-Specific Variables

These variables control the ETL process behavior:

### Performance Configuration

#### `ETL_BATCH_SIZE`

- **Purpose**: Number of records processed per batch
- **Values**: Integer (e.g., `1000`, `5000`)
- **Default**: `1000`
- **Usage**: Increase for better throughput on powerful systems
- **Example**:
  ```bash
  export ETL_BATCH_SIZE=5000
  ./bin/dwh/ETL.sh
  ```

#### `ETL_COMMIT_INTERVAL`

- **Purpose**: Commit every N records during batch processing
- **Values**: Integer (e.g., `100`, `500`)
- **Default**: `100`
- **Usage**: Balance between performance and transaction safety
- **Example**:
  ```bash
  export ETL_COMMIT_INTERVAL=500
  ./bin/dwh/ETL.sh
  ```

#### `ETL_MAX_PARALLEL_JOBS`

- **Purpose**: Maximum number of parallel jobs for year-based processing
- **Values**: Integer (e.g., `4`, `8`, `16`)
- **Default**: `4`
- **Usage**: Increase for multi-core systems (should be less than CPU cores)
- **Example**:
  ```bash
  export ETL_MAX_PARALLEL_JOBS=8
  ./bin/dwh/ETL.sh
  ```

#### `ETL_PARALLEL_ENABLED`

- **Purpose**: Enable/disable parallel processing
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for debugging or single-core systems
- **Example**:
  ```bash
  export ETL_PARALLEL_ENABLED=false
  ./bin/dwh/ETL.sh
  ```

### Resource Control

#### `MAX_MEMORY_USAGE`

- **Purpose**: Memory usage threshold percentage (alert when exceeded)
- **Values**: Integer 0-100 (e.g., `80`, `90`)
- **Default**: `80`
- **Usage**: Adjust based on available system memory
- **Example**:
  ```bash
  export MAX_MEMORY_USAGE=90
  ./bin/dwh/ETL.sh
  ```

#### `MAX_DISK_USAGE`

- **Purpose**: Disk usage threshold percentage (alert when exceeded)
- **Values**: Integer 0-100 (e.g., `85`, `95`)
- **Default**: `90`
- **Usage**: Adjust based on available disk space
- **Example**:
  ```bash
  export MAX_DISK_USAGE=85
  ./bin/dwh/ETL.sh
  ```

#### `ETL_TIMEOUT`

- **Purpose**: Maximum execution time in seconds (process will timeout if exceeded)
- **Values**: Integer in seconds (e.g., `3600`, `7200`)
- **Default**: `7200` (2 hours)
- **Usage**: Increase for initial loads, decrease for quick validations
- **Recommendations**:
  - **Incremental updates**: 2 hours (default OK)
  - **Initial load**: 36 hours (`export ETL_TIMEOUT=129600`)
- **Example**:
  ```bash
  export ETL_TIMEOUT=129600  # 36 hours for initial load
  ./bin/dwh/ETL.sh
  ```

#### `PSQL_STATEMENT_TIMEOUT`

- **Purpose**: Maximum time a single SQL statement can run (prevents long-running queries from
  hanging)
- **Values**: PostgreSQL interval format (e.g., `30min`, `2h`, `4h`)
- **Default**: `30min` (configured in `etc/properties.sh`)
- **Usage**: Critical for preventing timeout errors during ETL execution
- **Recommendations**:
  - **Normal incremental**: 30 minutes (default OK)
  - **Large incremental** (> 10M facts): 2 hours (`export PSQL_STATEMENT_TIMEOUT=2h`)
  - **Initial load**: 4 hours (`export PSQL_STATEMENT_TIMEOUT=4h`)
- **Common issue**: Large incremental updates can exceed 30min timeout, causing
  `canceling statement due to statement timeout` errors
- **Example**:

  ```bash
  # For large incremental updates
  export PSQL_STATEMENT_TIMEOUT=2h
  ./bin/dwh/ETL.sh

  # For initial load
  export PSQL_STATEMENT_TIMEOUT=4h
  ./bin/dwh/ETL.sh
  ```

### Database Maintenance

#### `ETL_VACUUM_AFTER_LOAD`

- **Purpose**: Run VACUUM after loading data
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for faster execution (not recommended for production)
- **Example**:
  ```bash
  export ETL_VACUUM_AFTER_LOAD=false
  ./bin/dwh/ETL.sh
  ```

#### `ETL_ANALYZE_AFTER_LOAD`

- **Purpose**: Run ANALYZE after loading data
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for faster execution (not recommended for production)
- **Example**:
  ```bash
  export ETL_ANALYZE_AFTER_LOAD=false
  ./bin/dwh/ETL.sh
  ```

### Recovery and Validation

#### `ETL_RECOVERY_ENABLED`

- **Purpose**: Enable recovery mode (resume from last checkpoint)
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for testing or if recovery causes issues
- **Example**:
  ```bash
  export ETL_RECOVERY_ENABLED=false
  ./bin/dwh/ETL.sh
  ```

#### `ETL_VALIDATE_INTEGRITY`

- **Purpose**: Validate data integrity after processing
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for faster execution (not recommended)
- **Example**:
  ```bash
  export ETL_VALIDATE_INTEGRITY=false
  ./bin/dwh/ETL.sh
  ```

#### `ETL_VALIDATE_DIMENSIONS`

- **Purpose**: Validate dimension table integrity
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for faster execution during development
- **Example**:
  ```bash
  export ETL_VALIDATE_DIMENSIONS=false
  ./bin/dwh/ETL.sh
  ```

#### `ETL_VALIDATE_FACTS`

- **Purpose**: Validate fact table integrity
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for faster execution during development
- **Example**:
  ```bash
  export ETL_VALIDATE_FACTS=false
  ./bin/dwh/ETL.sh
  ```

### Monitoring

#### `ETL_MONITOR_RESOURCES`

- **Purpose**: Enable resource monitoring during execution
- **Values**: `true`, `false`
- **Default**: `true`
- **Usage**: Disable for minimal overhead (not recommended)
- **Example**:
  ```bash
  export ETL_MONITOR_RESOURCES=false
  ./bin/dwh/ETL.sh
  ```

#### `ETL_MONITOR_INTERVAL`

- **Purpose**: Resource monitoring check interval in seconds
- **Values**: Integer in seconds (e.g., `30`, `60`)
- **Default**: `30`
- **Usage**: Adjust based on monitoring needs
- **Example**:
  ```bash
  export ETL_MONITOR_INTERVAL=60
  ./bin/dwh/ETL.sh
  ```

### Test Mode

#### `ETL_TEST_MODE`

- **Purpose**: Test mode - processes only years 2013-2014 for faster testing
- **Values**: `true`, `false`
- **Default**: `false`
- **Usage**: Enable for quick testing, then use incremental mode for remaining years
- **Example**:
  ```bash
  export ETL_TEST_MODE=true
  ./bin/dwh/ETL.sh
  # Processes only 2013-2014
  # Then run incremental to process 2015+
  ```

## 📋 Properties File Variables

Defined in `etc/properties.sh` (created from `etc/properties.sh.example`, can be overridden by
environment):

### Database Configuration

- **`DBNAME`**: PostgreSQL database name (default: `notes_dwh`)
- **`DB_USER`**: PostgreSQL user (default: `notes`)

### Processing Configuration

- **`MAX_THREADS`**: Parallel processing threads (auto-calculated from CPU cores, max 16)
- **`LOOP_SIZE`**: Notes processed per loop (default: `10000`)
- **`MAX_NOTES`**: Max notes from API (default: `10000`)
- **`MIN_NOTES_FOR_PARALLEL`**: Minimum notes for parallel processing (default: `10`)

### Export Configuration

- **`JSON_OUTPUT_DIR`**: Output directory for JSON exports (default: `./output/json`)

### Other Configuration

- **`CLEAN`**: Clean temporary files (default: `true`)
- **`EMAILS`**: Email addresses for reports (default: `username@domain.com`)

Defined in `etc/etl.properties` (created from `etc/etl.properties.example`):

All ETL-specific variables listed above can be set in `etc/etl.properties` instead of environment
variables. The properties file is loaded first, then environment variables override if set.

## 🎯 Standard Usage Patterns

### Development/Debugging

```bash
export LOG_LEVEL=DEBUG
export CLEAN=false
export ETL_VALIDATE_INTEGRITY=true
export ETL_VALIDATE_DIMENSIONS=true
export ETL_VALIDATE_FACTS=true
export ETL_TEST_MODE=true
./bin/dwh/ETL.sh
```

### Production

```bash
export LOG_LEVEL=ERROR
export CLEAN=true
export ETL_BATCH_SIZE=1000
export ETL_MAX_PARALLEL_JOBS=4
export ETL_RECOVERY_ENABLED=true
export ETL_VALIDATE_INTEGRITY=true
./bin/dwh/ETL.sh
```

### Testing

```bash
export DBNAME=osm_notes_analytics_test
export LOG_LEVEL=INFO
export CLEAN=true
export ETL_TEST_MODE=true
./bin/dwh/ETL.sh
```

### High-Performance System

```bash
export ETL_BATCH_SIZE=5000
export ETL_MAX_PARALLEL_JOBS=8
export ETL_COMMIT_INTERVAL=500
export MAX_MEMORY_USAGE=90
./bin/dwh/ETL.sh
```

### Low-Resource System

```bash
export ETL_BATCH_SIZE=500
export ETL_MAX_PARALLEL_JOBS=2
export ETL_PARALLEL_ENABLED=false
export MAX_MEMORY_USAGE=70
./bin/dwh/ETL.sh
```

## 🔧 Internal Variables (Do Not Modify)

These variables are used internally and should **never** be set manually:

- **`SCRIPT_BASE_DIRECTORY`**: Base directory (auto-detected)
- **`BASENAME`**: Script name (auto-detected)
- **`TMP_DIR`**: Temporary directory (auto-created)
- **`LOCK`**: Lock file path (auto-created)
- **`LOG_FILENAME`**: Log file path (auto-created)
- **`ONLY_EXECUTION`**: Execution mode flag (internal)
- **`SKIP_MAIN`**: Skip main execution flag (for testing)

## 📝 Recommendations

### For Users

1. **Never** set internal variables manually
2. Create `etc/properties.sh` from `etc/properties.sh.example` for local customization
3. Create `etc/etl.properties` from `etc/etl.properties.example` for ETL-specific settings
4. Only override environment variables when necessary
5. Document any custom configuration

### For Developers

1. Add new variables to this documentation
2. Use descriptive names in UPPERCASE
3. Always provide defaults via `${VAR:-default}` syntax
4. Document in script header comments
5. Support both properties file and environment variable override

## 🔄 Configuration Priority

Configuration is loaded in this order (later values override earlier ones):

1. **Default values** (hardcoded in scripts)
2. **`etc/properties.sh`** (if exists)
3. **`etc/properties.sh.local`** (if exists, overrides properties.sh)
4. **`etc/etl.properties`** (if exists, for ETL-specific variables)
5. **`etc/etl.properties.local`** (if exists, overrides etl.properties)
6. **Environment variables** (highest priority, overrides all)

Example:

```bash
# etc/properties.sh sets DBNAME=notes
# etc/etl.properties sets ETL_BATCH_SIZE=1000
# Environment variable overrides:
export DBNAME=osm_notes_analytics_test
export ETL_BATCH_SIZE=5000
# Result: DBNAME=osm_notes_analytics_test, ETL_BATCH_SIZE=5000
```

## See Also

- `bin/dwh/ENTRY_POINTS.md` - Allowed entry points
- `etc/properties.sh.example` - Configuration template
- `etc/etl.properties.example` - ETL configuration template
- `README.md` - General usage guide
- `bin/README.md` - Script documentation
