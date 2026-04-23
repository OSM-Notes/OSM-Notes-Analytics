# Etc Directory

This directory contains configuration files that control the behavior of the OSM-Notes-Analytics
system.

## Overview

Configuration files in this directory define database connections, processing parameters, and system
behavior. These files should be customized for your specific environment before running the ETL and
datamart scripts.

## Configuration Files

### Main Configuration Files

**Configuration files are created from templates and contain your credentials:**

```bash
# Copy example files to create your configuration
cp etc/properties.sh.example etc/properties.sh
cp etc/etl.properties.example etc/etl.properties

# Edit with your specific settings and credentials
nano etc/properties.sh
nano etc/etl.properties
```

**Configuration files are automatically ignored by Git** (see `.gitignore`):

- `etc/properties.sh` - **NOT in Git** (contains your credentials)
- `etc/etl.properties` - **NOT in Git** (contains your settings)
- `etc/properties.sh.local` - Optional override (also ignored)
- `etc/etl.properties.local` - Optional override (also ignored)
- `etc/*.local` - All local overrides ignored
- `etc/*_local` - All local overrides ignored

**Only template files are versioned:**

- `etc/properties.sh.example` - Template (safe to version)
- `etc/etl.properties.example` - Template (safe to version)

### Cron and log configuration

- **`etc/cron.example`** – Example crontab for ETL, export, maintenance. Copy, edit paths, then
  `crontab /tmp/your-file`. Includes notes for logging to
  `/var/log/osm-notes-analytics/analytics.log` (same layout as sibling projects osm-notes-ingestion,
  osm-notes-monitoring).
- **`etc/logrotate.osm-analytics.conf`** – Logrotate config for
  `/var/log/osm-notes-analytics/analytics.log`. Install with:
  `sudo cp etc/logrotate.osm-analytics.conf /etc/logrotate.d/osm-analytics`. Ensures daily rotation
  and 14 days retention (rotated files: `analytics.log-YYYYMMDD.gz`).

### Schema compatibility (DWH)

- **`etc/schema_compatibility.sh`** – Declares the acceptable SemVer **range** for
  `public.schema_version` where `component = dwh` (e.g. for OSM-Notes-API). See
  [docs/Schema_Versioning_DWH.md](../docs/Schema_Versioning_DWH.md). Ingestion’s `core` contract
  remains documented in OSM-Notes-Ingestion.

**Priority order:**

1. Environment variables (highest)
2. Local override files (`*.local`) - **loaded automatically if they exist**
3. Main configuration files (`properties.sh`, `etl.properties`)
4. Script defaults (lowest)

**Security:** Your credentials in `properties.sh` and `etl.properties` will never be committed to
Git. Only the `.example` template files are versioned in the repository.

### properties.sh

**Purpose:** Main configuration file for database connection and Analytics-specific parameters.

**Location:** `etc/properties.sh`

**Configuration Sections:**

#### 1. Database Configuration

```bash
# Ingestion (source) and Analytics (DWH) databases — often the same DB in simple setups
DBNAME_INGESTION="notes"
DBNAME_DWH="notes_dwh"

# PostgreSQL users for each database
DB_USER_INGESTION="notes"
DB_USER_DWH="notes"
```

**Foreign Data Wrapper (FDW):** When `DBNAME_INGESTION` and `DBNAME_DWH` differ, ETL configures an
FDW from the Analytics database to the Ingestion database. Set `FDW_INGESTION_HOST`,
`FDW_INGESTION_PORT`, `FDW_INGESTION_USER`, and `FDW_INGESTION_PASSWORD` as needed.

On the **DWH** database, a superuser must install `CREATE EXTENSION postgres_fdw` and grant the ETL
role usage of the wrapper:  
`GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO <DB_USER_DWH>;`  
Otherwise setup fails with `permission denied for foreign-data wrapper postgres_fdw`. See
[Hybrid Strategy Guide](../docs/Hybrid_Strategy_Copy_FDW.md) and
[Installation Dependencies](../docs/Installation_Dependencies.md).

**Important Notes:**

- Base tables must exist (populated by OSM-Notes-Ingestion).
- The DWH user needs permission to read base tables and create objects in `dwh` and `staging`.

#### 2. Parallel Processing

```bash
# Maximum parallel threads (auto-detected from CPU cores, capped at 16)
MAX_THREADS="4"
```

**Auto-detection:** Uses `nproc`, caps at 16, falls back to 4 if detection fails.

**Tuning:** Batch sizing and ETL parallelism are controlled in `etc/etl.properties`
(`ETL_BATCH_SIZE`, `ETL_MAX_PARALLEL_JOBS`). Match `ETL_MAX_PARALLEL_JOBS` to your CPU budget.

#### 3. Cleanup Configuration

```bash
# Clean up temporary files after successful execution
CLEAN="true"
```

- **true**: Delete temporary files (recommended for production)
- **false**: Keep temporary files (useful for debugging)

#### 4. JSON Export

```bash
JSON_OUTPUT_DIR="./output/json"
```

Used by `bin/dwh/exportDatamartsToJSON.sh` (and related export scripts).

#### 5. PostgreSQL Timeouts (ETL)

```bash
PSQL_STATEMENT_TIMEOUT="2h"
PSQL_LOCK_TIMEOUT="10s"
PSQL_IDLE_IN_TRANSACTION_TIMEOUT="10min"
```

Used by `bin/dwh/ETL.sh` when building `psql` session settings.

#### 6. Datamart Users (ETL)

```bash
MAX_USERS_PER_CYCLE="4000"
CATCHUP_THRESHOLD="10000"
# Optional: MAX_USERS_PER_CYCLE_CATCHUP=...  CATCHUP_MULTIPLIER=...
```

See `bin/dwh/datamartUsers/datamartUsers.sh` and
[Environment Variables](../bin/dwh/Environment_Variables.md).

### etl.properties

**Purpose:** ETL-specific configuration for performance, recovery, and validation.

**Location:** `etc/etl.properties`

**Configuration Sections:**

#### 1. Performance Configuration

```bash
# Number of records to process in each batch
ETL_BATCH_SIZE=1000

# Commit transaction every N records
ETL_COMMIT_INTERVAL=100

# Run VACUUM after data load
ETL_VACUUM_AFTER_LOAD=true

# Run ANALYZE after data load
ETL_ANALYZE_AFTER_LOAD=true
```

**Tuning Guide:**

- **Increase ETL_BATCH_SIZE** (5000-10000) for faster processing on powerful systems
- **Decrease ETL_BATCH_SIZE** (500-1000) for systems with limited memory
- **Keep VACUUM/ANALYZE enabled** for optimal query performance

#### 2. Resource Control

```bash
# Maximum memory usage percentage before pausing
MAX_MEMORY_USAGE=80

# Maximum disk usage percentage before stopping
MAX_DISK_USAGE=90

# ETL execution timeout in seconds (2 hours)
ETL_TIMEOUT=7200
```

**Safety Features:**

- Monitors system resources during execution
- Pauses processing if memory exceeds threshold
- Stops execution if disk usage is critical
- Times out if ETL takes too long (prevents runaway processes)

#### 3. Recovery Configuration

```bash
# Enable recovery checkpoints for resuming after failure
ETL_RECOVERY_ENABLED=true
```

**Features:**

- Saves progress at key steps
- Allows resuming with `--resume` flag
- Stores recovery state in JSON format

#### 4. Data Integrity Validation

```bash
# Enable comprehensive data validation
ETL_VALIDATE_INTEGRITY=true

# Validate dimension tables are populated
ETL_VALIDATE_DIMENSIONS=true

# Validate fact table references
ETL_VALIDATE_FACTS=true
```

**Validation Checks:**

- Dimension tables contain data
- Fact table foreign keys are valid
- No orphaned records
- Data consistency across tables

**Ingestion readiness:** The ETL always verifies `public.properties.base_load_complete = true` on
`DBNAME_INGESTION` before proceeding. OSM-Notes-Ingestion sets this after a successful
`processPlanetNotes.sh --base` (`__record_base_load_complete`). API-only deployments must insert the
same key/value when data is ready.

#### 5. Notification Configuration

```bash
# Enable email notifications
ETL_NOTIFICATION_ENABLED=false

# Email address for notifications
ETL_NOTIFICATION_EMAIL=""
```

**Future Feature:** Email notifications for ETL completion and errors.

#### 6. Parallel Processing variables

```bash
# Enable parallel ETL processing by year
ETL_PARALLEL_ENABLED=true

# Maximum parallel jobs to run simultaneously
ETL_MAX_PARALLEL_JOBS=4
```

**How It Works:**

- Processes each year (2013-present) in parallel
- Each year runs as a separate background process
- Results merged after all years complete

**Tuning Guide:**

- Match `ETL_MAX_PARALLEL_JOBS` with `MAX_THREADS` in `properties.sh`
- Increase for multi-core systems (8-16)
- Decrease if experiencing memory issues (2-4)

#### 7. Logging Configuration

```bash
# Logging level: TRACE, DEBUG, INFO, WARN, ERROR, FATAL
ETL_LOG_LEVEL="INFO"

# Enable audit logging
ETL_AUDIT_ENABLED=true
```

**Log Levels:**

- **TRACE**: Very detailed debugging info
- **DEBUG**: Detailed debugging info
- **INFO**: General information (recommended)
- **WARN**: Warnings and potential issues
- **ERROR**: Errors only
- **FATAL**: Fatal errors only

#### 8. Database Configuration

```bash
# Database query timeout in seconds
ETL_DB_TIMEOUT=300

# Number of retry attempts for failed queries
ETL_DB_RETRY_ATTEMPTS=3
```

**Resilience:**

- Retries failed database operations
- Times out long-running queries
- Prevents hanging on network issues

#### 9. Monitoring Configuration

```bash
# Enable resource monitoring during execution
ETL_MONITOR_RESOURCES=true

# Check resources every N seconds
ETL_MONITOR_INTERVAL=30
```

Continuously monitors:

- Memory usage
- Disk usage
- CPU usage
- Execution time

#### 10. Large File Processing

```bash
# File size thresholds in MB
ETL_LARGE_FILE_THRESHOLD_MB=500
ETL_VERY_LARGE_FILE_THRESHOLD_MB=1000

# XML processing configuration
ETL_XML_VALIDATION_TIMEOUT=300
ETL_XML_BATCH_SIZE=1000
ETL_XML_MAX_BATCHES=10
ETL_XML_SAMPLE_SIZE=50
ETL_XML_MEMORY_LIMIT_MB=2048
```

**Optimizations for Large Files:**

- Batch processing for huge XML files
- Sampling for validation
- Memory limits to prevent OOM errors

#### 11. XSLT Processing

```bash
# Maximum recursion depth for XSLT transformations
ETL_XSLT_MAX_DEPTH=4000
```

Used by ETL XML/XSLT paths when enabled in `etl.properties`.

## Customization Guide

### Initial Setup

1. **Copy and edit properties.sh:**

   ```bash
   cd etc/
   nano properties.sh
   ```

1. **Set database credentials:**

   ```bash
   DBNAME_INGESTION="notes"
   DBNAME_DWH="notes_dwh"
   DB_USER_INGESTION="notes"
   DB_USER_DWH="notes"
   ```

1. **Adjust parallel processing:**

   ```bash
   # For 8-core system:
   MAX_THREADS="8"
   ```

1. **Save and test connection:**

```bash
psql -d your_database_name -U your_username -c "SELECT version();"
```

### Performance Optimization

#### For High-Performance Systems (16+ cores, 32GB+ RAM)

**properties.sh:**

```bash
MAX_THREADS="16"
```

**etl.properties:**

```bash
ETL_BATCH_SIZE=10000
ETL_MAX_PARALLEL_JOBS=16
MAX_MEMORY_USAGE=90
```

#### For Limited Resources (4 cores, 8GB RAM)

**properties.sh:**

```bash
MAX_THREADS="2"
```

**etl.properties:**

```bash
ETL_BATCH_SIZE=500
ETL_MAX_PARALLEL_JOBS=2
MAX_MEMORY_USAGE=70
```

### Development vs Production

#### Development Settings

**etl.properties:**

```bash
ETL_LOG_LEVEL="DEBUG"
CLEAN="false"  # Keep files for debugging
ETL_VALIDATE_INTEGRITY=true
ETL_VALIDATE_DIMENSIONS=true
ETL_VALIDATE_FACTS=true
```

#### Production Settings

**etl.properties:**

```bash
ETL_LOG_LEVEL="INFO"
CLEAN="true"  # Remove temporary files
ETL_VALIDATE_INTEGRITY=true
ETL_NOTIFICATION_ENABLED=true
ETL_NOTIFICATION_EMAIL="notes@osm.lat"
```

## Environment Variables

Configuration can be overridden with environment variables:

```bash
# Override database name (recommended: use DBNAME_INGESTION and DBNAME_DWH)
export DBNAME_INGESTION="notes_dwh"
export DBNAME_DWH="notes_dwh"
# Or use DBNAME for same database (legacy/compatibility)
export DBNAME="osm_notes_analytics_test"

# Override log level
export LOG_LEVEL="DEBUG"

# Run ETL
./bin/dwh/ETL.sh
```

**Priority Order:**

1. Environment variables (highest)
2. Configuration files
3. Script defaults (lowest)

## Security Considerations

### Database Credentials

**Do NOT commit sensitive credentials to Git:**

```bash
# Add to .gitignore (already done)
etc/properties.sh.local
```

**Use local override file:**

```bash
# Create local override
cp etc/properties.sh etc/properties.sh.local
nano etc/properties.sh.local

# Modify scripts to source local file first
```

### PostgreSQL Authentication

**Recommended: Use .pgpass file:**

```bash
# Create .pgpass in home directory
echo "localhost:5432:notes_dwh:notes:mypassword" >> ~/.pgpass
chmod 600 ~/.pgpass
```

**Or use PostgreSQL environment variables:**

```bash
export PGDATABASE="notes_dwh"
export PGUSER="notes"
export PGPASSWORD="mypassword"
```

## Validation

### Test Configuration

```bash
# Test database connection
psql -d "${DBNAME}" -U "${DB_USER}" -c "SELECT version();"

# Test properties.sh
bash -c "source etc/properties.sh && echo 'MAX_THREADS: ${MAX_THREADS}'"

# Test ETL help
./bin/dwh/ETL.sh --help
```

### Verify Settings

```bash
# Show current configuration
grep -v "^#" etc/properties.sh | grep -v "^$"
grep -v "^#" etc/etl.properties | grep -v "^$"
```

## Troubleshooting

### "Database does not exist"

Create database:

```bash
createdb "${DBNAME}"
```

### "Permission denied"

Grant permissions:

```bash
psql -d "${DBNAME}" -c "GRANT ALL ON SCHEMA dwh TO ${DB_USER};"
```

### "Out of memory" during ETL

Reduce resource usage:

```bash
# Edit etc/etl.properties
ETL_BATCH_SIZE=500
ETL_MAX_PARALLEL_JOBS=2
```

### Configuration not taking effect

Check environment variables:

```bash
env | grep -E '(DBNAME|ETL_|MAX_THREADS)'
```

Unset conflicting variables:

```bash
unset DBNAME
unset ETL_BATCH_SIZE
```

## Best Practices

1. **Always backup** configuration files before modifying
2. **Use environment-specific** settings (dev/staging/prod)
3. **Monitor resource usage** in logs during first runs
4. **Start with conservative** settings and tune gradually
5. **Document custom changes** in comments
6. **Test configuration** with `--dry-run` before full execution

## Related Documentation

### Essential Reading

- **[Main README](../README.md)** - Project overview and quick start guide
- **[bin/dwh/ENVIRONMENT_VARIABLES.md](../bin/dwh/Environment_Variables.md)** - Complete environment
  variable reference
- **[bin/dwh/ENTRY_POINTS.md](../bin/dwh/Entry_Points.md)** - Script entry points and usage

### Technical Documentation

- **[ETL Enhanced Features](../docs/ETL_Enhanced_Features.md)** - ETL capabilities and configuration
- **[DWH Maintenance Guide](../docs/DWH_Maintenance_Guide.md)** - Maintenance procedures
- **[Troubleshooting Guide](../docs/Troubleshooting_Guide.md)** - Common configuration issues

### Testing and Development

- **[Testing Guide](../tests/README.md)** - Test execution and writing tests
- **[CI/CD Guide](../docs/CI_CD_Guide.md)** - CI/CD workflows and validation
- **[Contributing Guide](../CONTRIBUTING.md)** - Development standards

## References

- [Main README](../README.md)
- [ETL Enhanced Features](../docs/ETL_Enhanced_Features.md)
- [Testing Guide](../tests/README.md)

## Support

For configuration issues:

1. Validate syntax: `bash -n etc/properties.sh`
2. Test database connection
3. Check log files for configuration errors
4. Create an issue with your (sanitized) configuration
