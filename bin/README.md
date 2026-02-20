# Bin Directory

This directory contains the executable scripts for the OSM-Notes-Analytics project, primarily
focused on ETL (Extract, Transform, Load) processes and datamart generation.

## Overview

The `bin/` directory houses the main operational scripts that transform raw OSM notes data into a
comprehensive data warehouse with pre-computed analytics datamarts.

## Quick Reference

**New to the project?** Start here:

- **[Entry Points Documentation](dwh/Entry_Points.md)** - Which scripts can be called directly
- **[Environment Variables](dwh/Environment_Variables.md)** - Configuration via environment
  variables
- **[DWH README](dwh/README.md)** - Detailed DWH documentation

**Key Entry Points:**

1. `bin/dwh/ETL.sh` - Main ETL process (creates/updates data warehouse)
2. `bin/dwh/datamartCountries/datamartCountries.sh` - Country datamart
3. `bin/dwh/datamartUsers/datamartUsers.sh` - User datamart
4. `bin/dwh/profile.sh` - Profile generator
5. `bin/dwh/exportDatamartsToJSON.sh` - Export to JSON
6. `bin/dwh/cleanupDWH.sh` - Cleanup script

See [Entry Points Documentation](dwh/Entry_Points.md) for complete details.

## Directory Structure

```text
bin/
└── dwh/                           # data warehouse scripts
    ├── ETL.sh                     # Main ETL orchestration script
    ├── profile.sh                 # Profile generator for users and countries
    ├── cleanupDWH.sh              # Cleanup DWH objects and temp files
    ├── README.md                  # DWH documentation
    ├── datamartCountries/         # Country datamart scripts
    │   └── datamartCountries.sh
    └── datamartUsers/             # User datamart scripts
        └── datamartUsers.sh
```

## Main Scripts

### 1. ETL.sh - Main ETL Process

**Location:** `bin/dwh/ETL.sh`

**Purpose:** Orchestrates the complete ETL process to populate the data warehouse from base tables.

**Features:**

- Creates star schema dimensions and fact tables
- Supports initial load and incremental updates
- Parallel processing by year (2013-present)
- Recovery and resume capabilities
- Resource monitoring and validation
- Comprehensive logging

**Usage:**

```bash
# ETL execution (auto-detects first run vs incremental)
./bin/dwh/ETL.sh

# Show help
./bin/dwh/ETL.sh --help
```

**Auto-detection:**

- **First execution**: Automatically detects if DWH doesn't exist or is empty, creates all DWH
  objects and performs initial load
- **Subsequent runs**: Automatically detects existing data and processes only incremental updates
- **Perfect for cron**: Same command works for both scenarios

**Configuration:**

- Database connection: `etc/properties.sh`
- ETL settings: `etc/etl.properties`

**Logging:**

```bash
# Follow ETL progress in real-time
tail -40f $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log
```

**Performance:**

- Initial load: ~30 hours (with parallel processing)
- Incremental update: 5-15 minutes (depends on new data volume)
- Resource requirements: 4GB+ RAM, multi-core CPU recommended

### 2. profile.sh - Profile Generator

**Location:** `bin/dwh/profile.sh`

**Purpose:** Generates detailed profiles for users and countries based on datamart data.

**Usage:**

```bash
# User profile
./bin/dwh/profile.sh --user AngocA

# Country profile (English name)
./bin/dwh/profile.sh --country Colombia
./bin/dwh/profile.sh --country "United States of America"

# Country profile (Spanish name)
./bin/dwh/profile.sh --pais Colombia
./bin/dwh/profile.sh --pais "Estados Unidos"

# General notes statistics
./bin/dwh/profile.sh
```

**Output includes:**

- Historical activity timeline
- Geographic distribution
- Working hours heatmap
- Rankings and leaderboards
- Activity patterns
- First and most recent actions

**Prerequisites:**

- Datamarts must be populated first
- Run `datamartCountries.sh` and `datamartUsers.sh` before generating profiles

### 3. datamartCountries.sh - Country Datamart

**Location:** `bin/dwh/datamartCountries/datamartCountries.sh`

**Purpose:** Populates the country-level datamart with pre-computed analytics.

**Usage:**

```bash
./bin/dwh/datamartCountries/datamartCountries.sh
```

**Features:**

- Aggregates note statistics by country
- Computes yearly historical data (2013-present)
- Generates user rankings per country
- Calculates working hours patterns
- Tracks first and latest activities

**Execution time:** ~20 minutes

**Prerequisites:**

- ETL must be completed
- DWH fact and dimension tables must exist

**Output:**

- Populates `dwh.datamartCountries` table
- One row per country with comprehensive metrics

### 4. cleanupDWH.sh - Cleanup Script

**Location:** `bin/dwh/cleanupDWH.sh`

**Purpose:** Removes data warehouse objects from the database and cleans up temporary files. Uses
database configuration from `etc/properties.sh`.

**⚠️ WARNING:** This script can permanently delete data! Always use `--dry-run` first to see what
will be removed.

**Usage:**

```bash
# Safe operations (no confirmation required):
./bin/dwh/cleanupDWH.sh --remove-temp-files    # Remove only temporary files
./bin/dwh/cleanupDWH.sh --dry-run              # Show what would be done (safe)

# Destructive operations (require confirmation):
./bin/dwh/cleanupDWH.sh                        # Full cleanup - REMOVES ALL DATA!
./bin/dwh/cleanupDWH.sh --remove-all-data      # Remove DWH schema and data only

# Help:
./bin/dwh/cleanupDWH.sh --help                # Show detailed help
```

**What it removes:**

**DWH Objects** (`--remove-all-data` or default behavior):

- Staging schema and all objects
- Datamart tables (countries and users)
- DWH schema with all dimensions and facts
- All functions, procedures, and triggers
- **⚠️ PERMANENT DATA LOSS - requires confirmation**

**Temporary Files** (`--remove-temp-files` or default behavior):

- `/tmp/ETL_*` directories
- `/tmp/datamartCountries_*` directories
- `/tmp/datamartUsers_*` directories
- `/tmp/profile_*` directories
- `/tmp/cleanupDWH_*` directories
- **✅ Safe operation - no confirmation required**

**When to use:**

- **Development/Testing:** Use `--remove-temp-files` to clean temporary files
- **Complete Reset:** Use default behavior to remove everything (with confirmation)
- **DWH Only:** Use `--remove-all-data` to remove only database objects
- **Safety First:** Always use `--dry-run` to preview operations

**Prerequisites:**

- Database configured in `etc/properties.sh`
- User must have DROP privileges on target database
- PostgreSQL client tools installed (`psql`)
- Script must be run from project root directory

**Use cases:**

- **Development:** Clean temporary files with `--remove-temp-files`
- **Testing:** Reset environment with `--dry-run` first, then full cleanup
- **Troubleshooting:** Remove corrupted DWH objects with `--remove-all-data`
- **Clean restart:** Remove all objects before running `ETL.sh`
- **Maintenance:** Regular cleanup of temporary files

### 5. datamartUsers.sh - User Datamart

**Location:** `bin/dwh/datamartUsers/datamartUsers.sh`

**Purpose:** Populates the user-level datamart with pre-computed analytics.

**Usage:**

```bash
./bin/dwh/datamartUsers/datamartUsers.sh
```

**Features:**

- Aggregates note statistics by user
- Processes incrementally (MAX_USERS_PER_CYCLE per run, default 5000; fits in 15 min on typical prod)
- Computes yearly historical data
- Generates country rankings per user
- Tracks contribution patterns
- Classifies contributor types

**Execution time:**

- Per run: ~3–5 minutes for 1000 users on typical production; ~5000 users fit in a 15-minute ETL window
- Full initial load: incremental over multiple ETL cycles (use catch-up mode for large backlogs)

**Prerequisites:**

- ETL must be completed
- DWH fact and dimension tables must exist

**Output:**

- Populates `dwh.datamartUsers` table
- One row per active user with comprehensive metrics

**Note:** This script is designed to run incrementally to avoid overwhelming the database. Schedule
it to run regularly until all users are processed.

### 6. datamartGlobal.sh - Global Datamart

**Location:** `bin/dwh/datamartGlobal/datamartGlobal.sh`

**Purpose:** Populates the global-level datamart with aggregated statistics.

**Usage:**

```bash
./bin/dwh/datamartGlobal/datamartGlobal.sh
```

**Features:**

- Aggregates global note statistics
- Computes worldwide metrics
- Provides system-wide analytics

**Prerequisites:**

- ETL must be completed
- DWH fact and dimension tables must exist

**Output:**

- Populates `dwh.datamartGlobal` table
- Global statistics and aggregated metrics

**Note:** This script is automatically called by `ETL.sh` after processing. Manual execution is
usually not needed.

### 7. exportDatamartsToJSON.sh - Export to JSON

**Location:** `bin/dwh/exportDatamartsToJSON.sh`

**Purpose:** Exports datamart data to JSON files for web viewer consumption.

**Usage:**

```bash
./bin/dwh/exportDatamartsToJSON.sh
```

**Features:**

- Exports user datamarts to individual JSON files
- Exports country datamarts to individual JSON files
- Creates index files for efficient lookup
- Generates metadata file
- **Atomic writes**: Files generated in temporary directory, validated, then moved atomically
- **Schema validation**: Each JSON file validated against schemas before export
- **Fail-safe**: On validation failure, keeps existing files and exits with error

**Output:**

Creates JSON files in `./output/json/`:

- Individual files per user: `users/{user_id}.json`
- Individual files per country: `countries/{country_id}.json`
- Index files: `indexes/users.json`, `indexes/countries.json`
- Metadata: `metadata.json`

**Prerequisites:**

- Datamarts must be populated
- `jq` and `ajv-cli` recommended for validation

**Example:**

```bash
# Export all datamarts to JSON
./bin/dwh/exportDatamartsToJSON.sh

# Verify export
ls -lh ./output/json/users/ | head -10
ls -lh ./output/json/countries/ | head -10
```

**See also:** [JSON Export Documentation](dwh/Export_JSON_README.md)

### 8. exportAndPushJSONToGitHub.sh - Export and Deploy

**Location:** `bin/dwh/exportAndPushJSONToGitHub.sh`

**Purpose:** Exports JSON files and automatically deploys them to GitHub Pages using intelligent
incremental mode.

**Usage:**

```bash
./bin/dwh/exportAndPushJSONToGitHub.sh
```

**Features:**

- **Intelligent incremental export**: Exports countries one by one and pushes immediately
- **Automatic detection**: Identifies missing, outdated (default: 30 days), or not exported
  countries
- **Cleanup**: Removes countries from GitHub that no longer exist in local database
- **Documentation**: Auto-generates README.md with alphabetical list of countries
- **Resilient**: Continues processing even if one country fails
- **Progress tracking**: Shows which countries are being processed
- **Schema validation**: Validates each JSON file before pushing

**Prerequisites:**

- Datamarts must be populated
- Git repository configured (`OSM-Notes-Data` cloned to `~/OSM-Notes-Data` or
  `~/github/OSM-Notes-Data`)
- GitHub Pages enabled
- Git credentials configured

**Environment variables:**

- `MAX_AGE_DAYS`: Maximum age in days before regeneration (default: 30, matches monthly cron)
- `COUNTRIES_PER_BATCH`: Number of countries to process before break (default: 10)
- `DBNAME_DWH`: Database name (default: from etc/properties.sh)

**Example:**

```bash
# Default: monthly refresh (30 days)
./bin/dwh/exportAndPushJSONToGitHub.sh

# Custom age threshold for testing
MAX_AGE_DAYS=7 ./bin/dwh/exportAndPushJSONToGitHub.sh
```

**Note:** This script is typically scheduled to run monthly via cron after datamart updates.

## Workflow

### Initial Setup (First Time)

```bash
# 1. Configure database connection
cp etc/properties.sh.example etc/properties.sh
nano etc/properties.sh

# 2. Configure ETL settings (optional, defaults work for most cases)
cp etc/etl.properties.example etc/etl.properties
nano etc/etl.properties

# 3. Verify base tables exist (from OSM-Notes-Ingestion)
psql -d notes_dwh -c "SELECT COUNT(*) FROM notes;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM note_comments;"

# 4. Run initial ETL (creates DWH, populates facts/dimensions, updates datamarts)
./bin/dwh/ETL.sh
# Wait ~30 hours for completion
# Note: ETL.sh automatically updates datamarts, so steps 5-6 are optional

# 5. Verify DWH creation
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.facts;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartcountries;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartusers;"

# 6. (Optional) Manually update datamarts if needed
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/datamartUsers/datamartUsers.sh

# 7. Generate a test profile
./bin/dwh/profile.sh --user AngocA

# 8. Export to JSON (optional, for web viewer)
./bin/dwh/exportDatamartsToJSON.sh
```

### Regular Updates (Scheduled)

```bash
# Crontab example (add with: crontab -e):

# Incremental ETL every 15 minutes (automatically updates datamarts)
*/15 * * * * cd ~/OSM-Notes-Analytics && ./bin/dwh/ETL.sh >> /var/log/osm-analytics-etl.log 2>&1

# Export to JSON and push to GitHub Pages (after datamarts update)
45 * * * * cd ~/OSM-Notes-Analytics && ./bin/dwh/exportAndPushJSONToGitHub.sh >> /var/log/osm-analytics-export.log 2>&1

# Optional: Manual datamart updates (usually not needed, ETL does this automatically)
# Update country datamart daily at 2 AM
# 0 2 * * * cd ~/OSM-Notes-Analytics && ./bin/dwh/datamartCountries/datamartCountries.sh >> /var/log/osm-analytics-datamart-countries.log 2>&1

# Update user datamart daily at 2:30 AM (processes MAX_USERS_PER_CYCLE per run, default 5000)
# 30 2 * * * cd ~/OSM-Notes-Analytics && ./bin/dwh/datamartUsers/datamartUsers.sh >> /var/log/osm-analytics-datamart-users.log 2>&1
```

**Note:** `ETL.sh` automatically updates all datamarts, so separate datamart cron jobs are usually
not needed.

### Generating Profiles

```bash
# After datamarts are populated, generate profiles:

# User profile
./bin/dwh/profile.sh --user AngocA

# Country profile
./bin/dwh/profile.sh --country Colombia

# General statistics
./bin/dwh/profile.sh
```

## Configuration Files

### Database Configuration

Create `etc/properties.sh` from the example:

```bash
cp etc/properties.sh.example etc/properties.sh
nano etc/properties.sh
```

**Key settings:**

```bash
DBNAME="notes_dwh"    # Database name
DB_USER="notes"       # Database user
MAX_THREADS="4"       # Parallel processing threads (auto-calculated from CPU cores)
CLEAN="true"          # Clean temporary files after processing
```

**Override via environment:**

```bash
export DBNAME=osm_notes_analytics_test
export DB_USER=postgres
./bin/dwh/ETL.sh
```

### ETL Configuration

Create `etc/etl.properties` from the example (optional):

```bash
cp etc/etl.properties.example etc/etl.properties
nano etc/etl.properties
```

**Key settings:**

```bash
ETL_BATCH_SIZE=1000              # Records per batch
ETL_PARALLEL_ENABLED=true        # Enable parallel processing
ETL_MAX_PARALLEL_JOBS=4          # Max parallel jobs
ETL_RECOVERY_ENABLED=true        # Enable recovery
ETL_VALIDATE_INTEGRITY=true      # Validate data integrity
MAX_MEMORY_USAGE=80              # Memory usage threshold (%)
MAX_DISK_USAGE=90                # Disk usage threshold (%)
ETL_TIMEOUT=7200                 # Execution timeout (seconds)
```

**Override via environment:**

```bash
export ETL_BATCH_SIZE=5000
export ETL_MAX_PARALLEL_JOBS=8
./bin/dwh/ETL.sh
```

**See also:** [Environment Variables Documentation](dwh/Environment_Variables.md) for complete
variable reference.

## Logging and Monitoring

All scripts create detailed logs in `/tmp/`:

```bash
# ETL logs (follow latest)
tail -40f $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log

# Country datamart logs
tail -f $(ls -1rtd /tmp/datamartCountries_* | tail -1)/datamartCountries.log

# User datamart logs
tail -f $(ls -1rtd /tmp/datamartUsers_* | tail -1)/datamartUsers.log

# Profile logs
tail -f $(ls -1rtd /tmp/profile_* | tail -1)/profile.log

# Export logs
tail -f $(ls -1rtd /tmp/exportDatamartsToJSON_* | tail -1)/exportDatamartsToJSON.log
```

**Set log level:**

```bash
# Debug mode (verbose)
export LOG_LEVEL=DEBUG
./bin/dwh/ETL.sh

# Info mode (moderate)
export LOG_LEVEL=INFO
./bin/dwh/ETL.sh

# Error mode (minimal, default)
export LOG_LEVEL=ERROR
./bin/dwh/ETL.sh
```

**Keep temporary files for inspection:**

```bash
export CLEAN=false
export LOG_LEVEL=DEBUG
./bin/dwh/ETL.sh

# Files will remain in /tmp/ETL_*/
# Inspect logs, CSV files, etc.
```

## Error Handling

### ETL Failures

If ETL fails:

1. Check logs in `/tmp/ETL_*/ETL.log`
2. Review error messages
3. Fix underlying issue
4. Restart: `./bin/dwh/ETL.sh`

### Resource Monitoring

Scripts monitor system resources:

- Memory usage (default: alert at 80%)
- Disk usage (default: alert at 90%)
- Execution timeout (default: 2 hours)

## Dependencies

### Required

- PostgreSQL 12+
- Bash 4.0+
- Base tables populated by OSM-Notes-Ingestion system

### Optional

- `jq` for JSON parsing (for recovery features)
- `parallel` for enhanced parallel processing

## Integration

These scripts integrate with:

1. **OSM-Notes-Ingestion** (upstream)
   - Reads base tables: `notes`, `note_comments`, `users`, `countries`
   - Requires ingestion system to run first

2. **OSM-Notes-Viewer** (sister project - downstream)
   - Web application that consumes JSON exports
   - Interactive dashboards and visualizations
   - User and country profiles
   - Reads JSON files exported by this analytics system

## Performance Tuning

### Increase Parallel Jobs

```bash
# Edit etc/etl.properties
ETL_MAX_PARALLEL_JOBS=8  # Increase for more cores
```

### Adjust Batch Size

```bash
# Edit etc/etl.properties
ETL_BATCH_SIZE=5000  # Increase for better throughput
```

### Database Optimization

```bash
# After initial load
psql -d notes_dwh -c "VACUUM ANALYZE dwh.facts;"
psql -d notes_dwh -c "REINDEX TABLE dwh.facts;"
```

## Troubleshooting

### "Base tables do not exist"

**Problem:** ETL cannot find base tables populated by OSM-Notes-Ingestion.

**Solution:**

```bash
# Verify base tables exist
psql -d notes_dwh -c "SELECT COUNT(*) FROM notes;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM note_comments;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM users;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM countries;"

# If tables are empty or don't exist, run OSM-Notes-Ingestion first
# See: https://github.com/OSM-Notes/OSM-Notes-Ingestion
```

### "Schema 'dwh' does not exist"

**Problem:** DWH schema not created yet.

**Solution:**

```bash
# Run initial ETL to create schema
./bin/dwh/ETL.sh
```

### "Lock file exists"

**Problem:** Another instance is running or previous execution crashed.

**Solution:**

```bash
# Check if process is actually running
ps aux | grep ETL.sh

# If no process found, remove lock file
rm /tmp/ETL_*.lock

# Or remove all lock files (use with caution)
find /tmp -name "*ETL*.lock" -delete
```

### "Out of memory"

**Problem:** System running out of memory during processing.

**Solution:**

```bash
# Reduce parallel jobs
export ETL_MAX_PARALLEL_JOBS=2

# Reduce batch size
export ETL_BATCH_SIZE=500

# Disable parallel processing
export ETL_PARALLEL_ENABLED=false

# Or edit etc/etl.properties
nano etc/etl.properties
# Set: ETL_MAX_PARALLEL_JOBS=2
# Set: ETL_BATCH_SIZE=500
```

### "ETL takes too long"

**Problem:** ETL process is slow.

**Solution:**

```bash
# Increase parallel jobs (if you have more CPU cores)
export ETL_MAX_PARALLEL_JOBS=8

# Increase batch size (if you have more memory)
export ETL_BATCH_SIZE=5000

# Check if base tables have indexes
psql -d notes_dwh -c "\d notes"
psql -d notes_dwh -c "\d note_comments"

# Run VACUUM ANALYZE on base tables
psql -d notes_dwh -c "VACUUM ANALYZE notes;"
psql -d notes_dwh -c "VACUUM ANALYZE note_comments;"
```

### "Datamart not fully populated"

**Problem:** Datamart tables are empty or incomplete.

**Solution:**

```bash
# Check datamart counts
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartcountries;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartusers;"

# Re-run datamart scripts
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/datamartUsers/datamartUsers.sh

# For users datamart, run multiple times (processes MAX_USERS_PER_CYCLE per run, default 5000)
# Keep running until it says "0 users processed"
while true; do
  ./bin/dwh/datamartUsers/datamartUsers.sh
  sleep 5
done
```

### "JSON export is empty"

**Problem:** JSON export produces no files or empty files.

**Solution:**

```bash
# Verify datamarts have data
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartusers;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartcountries;"

# If counts are 0, re-run datamart population
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/datamartUsers/datamartUsers.sh

# Check export output directory
ls -lh ./output/json/

# Run export with debug logging
export LOG_LEVEL=DEBUG
./bin/dwh/exportDatamartsToJSON.sh
```

### Database Connection Issues

**Problem:** Cannot connect to database.

**Solution:**

```bash
# Test connection
psql -d notes_dwh -c "SELECT version();"

# Verify database name in properties
cat etc/properties.sh | grep DBNAME

# Check PostgreSQL is running
sudo systemctl status postgresql

# Verify user permissions
psql -d notes_dwh -c "SELECT current_user;"
```

### "Profile not found"

**Problem:** Profile script cannot find user or country.

**Solution:**

```bash
# Check if user exists in datamart
psql -d notes_dwh -c "SELECT username FROM dwh.datamartusers WHERE username = 'AngocA';"

# Check if country exists
psql -d notes_dwh -c "SELECT country_name_en FROM dwh.datamartcountries WHERE country_name_en = 'Colombia';"

# Use exact name as stored in database
# For countries, try both English and Spanish names
./bin/dwh/profile.sh --country Colombia
./bin/dwh/profile.sh --pais Colombia
```

## Development

### Adding New Scripts

1. Follow naming convention: `descriptiveName.sh`
2. Include header with purpose, author, version
3. Source common libraries from `lib/osm-common/` (OSM-Notes-Common submodule)
4. Add error handling and logging
5. Include help text (`--help` flag)
6. Test with shellcheck: `shellcheck -x -o all script.sh`
7. Format with shfmt: `shfmt -w -i 1 -sr -bn script.sh`

### Code Style

- Use descriptive function names with `__` prefix
- Add comments for complex logic
- Include error codes in help text
- Use strict error handling (`set -euo pipefail`)

## Related Documentation

### Essential Reading

- **[Entry Points](dwh/Entry_Points.md)** - Which scripts can be called directly
- **[Environment Variables](dwh/Environment_Variables.md)** - Complete environment variable
  reference
- **[DWH README](dwh/README.md)** - Detailed DWH documentation
- **[Main README](../README.md)** - Project overview and quick start

### Technical Documentation

- **[ETL Enhanced Features](../docs/ETL_Enhanced_Features.md)** - Advanced ETL capabilities
- **[DWH Star Schema ERD](../docs/DWH_Star_Schema_ERD.md)** - Entity-relationship diagram
- **[Data Dictionary](../docs/DWH_Star_Schema_Data_Dictionary.md)** - Complete schema documentation
- **[DWH Maintenance Guide](../docs/DWH_Maintenance_Guide.md)** - Maintenance procedures

### Configuration

- **[etc/README.md](../etc/README.md)** - Configuration files and setup
- **[sql/README.md](../sql/README.md)** - SQL scripts documentation

### Troubleshooting

- **[Troubleshooting Guide](../docs/Troubleshooting_Guide.md)** - Common issues and solutions

### Development

- **[Testing Guide](../tests/README.md)** - Testing documentation
- **[Contributing Guide](../CONTRIBUTING.md)** - Development standards
- **[CI/CD Guide](../docs/CI_CD_Guide.md)** - CI/CD workflows

### Related Projects

- **[OSM-Notes-Ingestion](https://github.com/OSM-Notes/OSM-Notes-Ingestion)** - Data ingestion
  system (upstream)
- **[OSM-Notes-Viewer](https://github.com/OSM-Notes/OSM-Notes-Viewer)** - Web application (sister
  project)
- **[OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common)** - Shared libraries (Git
  submodule)

## References

### Documentation

- **[Entry Points](dwh/Entry_Points.md)** - Which scripts can be called directly
- **[Environment Variables](dwh/Environment_Variables.md)** - Complete environment variable
  reference
- **[DWH README](dwh/README.md)** - Detailed DWH documentation
- **[ETL Enhanced Features](../docs/ETL_Enhanced_Features.md)** - Advanced ETL capabilities
- **[DWH Star Schema ERD](../docs/DWH_Star_Schema_ERD.md)** - Entity-relationship diagram
- **[Data Dictionary](../docs/DWH_Star_Schema_Data_Dictionary.md)** - Complete schema documentation
- **[Testing Guide](../tests/README.md)** - Testing documentation

### Related Projects

- **[OSM-Notes-Ingestion](https://github.com/OSM-Notes/OSM-Notes-Ingestion)** - Data ingestion
  system (upstream)
- **[OSM-Notes-Viewer](https://github.com/OSM-Notes/OSM-Notes-Viewer)** - Web application (sister
  project)

## Support

For issues with scripts:

1. Check log files in `/tmp/`
2. Review error messages
3. Validate configuration files
4. Create an issue with logs and error details
