# Entry Points Documentation

**Purpose:** Define allowed entry points for OSM-Notes-Analytics DWH system

## Overview

This document defines the **standardized entry points** (scripts that can be called directly by
users or schedulers) vs **internal scripts** (supporting components that should not be called
directly).

## ✅ Allowed Entry Points

These are the **only scripts** that should be executed directly:

### Primary ETL Processing

1. **`bin/dwh/ETL.sh`** - Main ETL orchestration script
   - **Usage**: `./bin/dwh/ETL.sh` (no arguments needed)
   - **Options**:
     - `(no arguments)`: Auto-detect mode - creates DWH if first execution, otherwise processes
       incremental updates (perfect for cron jobs)
     - `--help` or `-h`: Shows detailed help information
   - **Purpose**: Orchestrates the complete ETL process to populate the data warehouse
   - **Auto-detection**: Automatically detects if first execution (checks if `dwh.facts` table
     exists and has data):
     - **First execution**: Creates all DWH objects and performs initial load (~30 hours)
     - **Subsequent runs**: Processes only incremental updates (5-15 minutes)
   - **Prerequisites**:
     - Base tables must exist (populated by OSM-Notes-Ingestion)
   - **Example**:

     ```bash
     # First time or regular updates (same command for both)
     ./bin/dwh/ETL.sh

     # For cron jobs (recommended)
     0 * * * * /path/to/OSM-Notes-Analytics/bin/dwh/ETL.sh
     ```

### Datamart Scripts

2. **`bin/dwh/datamartCountries/datamartCountries.sh`** - Country datamart population
   - **Usage**: `./bin/dwh/datamartCountries/datamartCountries.sh`
   - **Purpose**: Populates the country-level datamart with pre-computed analytics
   - **When**: After ETL completes (automatically called by ETL.sh, or manually for updates)
   - **Execution time**: ~20 minutes
   - **Prerequisites**: ETL must be completed, DWH fact and dimension tables must exist
   - **Output**: Populates `dwh.datamartCountries` table
   - **Example**:
     ```bash
     ./bin/dwh/datamartCountries/datamartCountries.sh
     ```

3. **`bin/dwh/datamartUsers/datamartUsers.sh`** - User datamart population
   - **Usage**: `./bin/dwh/datamartUsers/datamartUsers.sh`
   - **Purpose**: Populates the user-level datamart with pre-computed analytics
   - **When**: After ETL completes (automatically called by ETL.sh, or manually for updates)
- **Execution time**:
    - Per run: ~3–5 minutes for 1000 users on typical prod; ~4000 users fit in 15 min
    - Full initial load: incremental over cycles (use catch-up for large backlogs)
   - **Prerequisites**: ETL must be completed, DWH fact and dimension tables must exist
   - **Output**: Populates `dwh.datamartUsers` table
   - **Note**: Designed to run incrementally. Schedule to run regularly until all users are
     processed.
   - **Example**:
     ```bash
     ./bin/dwh/datamartUsers/datamartUsers.sh
     ```

4. **`bin/dwh/datamartGlobal/datamartGlobal.sh`** - Global datamart population
   - **Usage**: `./bin/dwh/datamartGlobal/datamartGlobal.sh`
   - **Purpose**: Populates the global-level datamart with aggregated statistics
   - **When**: After ETL completes (automatically called by ETL.sh, or manually for updates)
   - **Prerequisites**: ETL must be completed, DWH fact and dimension tables must exist
   - **Output**: Populates `dwh.datamartGlobal` table
   - **Example**:
     ```bash
     ./bin/dwh/datamartGlobal/datamartGlobal.sh
     ```

### Profile Generation

5. **`bin/dwh/profile.sh`** - Profile generator for users and countries
   - **Usage**: `./bin/dwh/profile.sh [OPTIONS] [ARGUMENT]`
   - **Options**:
     - `--user <UserName>`: Shows the profile for the given user
     - `--country <CountryName>`: Shows the profile for the given country (English name)
     - `--pais <NombrePais>`: Shows the profile for the given country (Spanish name)
     - `--help` or `-h`: Shows help information
     - (no options): Shows general statistics about notes
   - **Purpose**: Generates detailed profiles for users and countries based on datamart data
   - **When**: After datamarts are populated
   - **Prerequisites**: Datamarts must be populated first
   - **Examples**:

     ```bash
     # User profile
     ./bin/dwh/profile.sh --user AngocA

     # Country profile (English)
     ./bin/dwh/profile.sh --country Colombia
     ./bin/dwh/profile.sh --country "United States of America"

     # Country profile (Spanish)
     ./bin/dwh/profile.sh --pais Colombia
     ./bin/dwh/profile.sh --pais "Estados Unidos"

     # General statistics
     ./bin/dwh/profile.sh
     ```

### Export Scripts

6. **`bin/dwh/exportDatamartsToJSON.sh`** - Export datamarts to JSON files
   - **Usage**: `./bin/dwh/exportDatamartsToJSON.sh`
   - **Purpose**: Exports datamart data to JSON files for OSM-Notes-Viewer (sister project)
     consumption
   - **When**: After datamarts are populated and updated
   - **Prerequisites**: Datamarts must be populated
   - **Output**: Creates JSON files in `./output/json/`:
     - Individual files per user: `users/{user_id}.json`
     - Individual files per country: `countries/{country_id}.json`
     - Index files: `indexes/users.json`, `indexes/countries.json`
     - Metadata: `metadata.json`
   - **Consumer**: JSON files are consumed by OSM-Notes-Viewer (sister project) web application
   - **Features**:
     - Atomic writes: Files generated in temporary directory, validated, then moved atomically
     - Schema validation: Each JSON file validated against schemas before export
     - Fail-safe: On validation failure, keeps existing files and exits with error
   - **Example**:
     ```bash
     ./bin/dwh/exportDatamartsToJSON.sh
     ```

7. **`bin/dwh/exportAndPushJSONToGitHub.sh`** - Export and push to GitHub Pages
   - **Usage**: `./bin/dwh/exportAndPushJSONToGitHub.sh`
   - **Purpose**: Exports JSON files and automatically deploys them to GitHub Pages for
     OSM-Notes-Viewer (sister project)
   - **When**: After datamarts are updated (typically scheduled monthly via cron)
   - **Prerequisites**:
     - Datamarts must be populated
     - Git repository configured (`OSM-Notes-Data` cloned)
     - GitHub Pages enabled
     - Git credentials configured
   - **Consumer**: OSM-Notes-Viewer (sister project) reads these JSON files
   - **Features**:
     - Intelligent incremental export: exports countries one by one and pushes immediately
     - Automatic detection of missing or outdated countries (default: 30 days)
     - Removes obsolete countries from GitHub that no longer exist locally
     - Generates README.md with alphabetical list of countries
     - Resilient: continues processing even if one country fails
   - **Environment variables**:
     - `MAX_AGE_DAYS`: Maximum age in days before regeneration (default: 30)
     - `COUNTRIES_PER_BATCH`: Number of countries before break (default: 10)
     - `DBNAME_DWH`: Database name (default: from etc/properties.sh)
   - **Example**:

     ```bash
     # Default: monthly refresh (30 days)
     ./bin/dwh/exportAndPushJSONToGitHub.sh

     # Custom age threshold
     MAX_AGE_DAYS=7 ./bin/dwh/exportAndPushJSONToGitHub.sh
     ```

### Maintenance Scripts

8. **`bin/dwh/cleanupDWH.sh`** - data warehouse cleanup script
   - **Usage**: `./bin/dwh/cleanupDWH.sh [OPTIONS]`
   - **Options**:
     - `--remove-temp-files`: Remove only temporary files (safe, no confirmation)
     - `--dry-run`: Show what would be done without actually doing it (safe)
     - `--remove-all-data`: Remove DWH schema and data only (destructive, requires confirmation)
     - (no options): Full cleanup - removes ALL DWH objects (destructive, requires confirmation)
     - `--help` or `-h`: Shows detailed help
   - **Purpose**: Removes data warehouse objects from the database and cleans up temporary files
   - **⚠️ WARNING**: Destructive operations permanently delete data! Always use `--dry-run` first.
   - **When**:
     - Development/Testing: Clean temporary files
     - Complete Reset: Remove everything before re-running ETL
     - Troubleshooting: Remove corrupted DWH objects
   - **Examples**:

     ```bash
     # Safe operations (no confirmation required)
     ./bin/dwh/cleanupDWH.sh --remove-temp-files    # Clean temporary files only
     ./bin/dwh/cleanupDWH.sh --dry-run              # Preview operations

     # Destructive operations (require confirmation)
     ./bin/dwh/cleanupDWH.sh                        # Full cleanup
     ./bin/dwh/cleanupDWH.sh --remove-all-data      # DWH objects only
     ```

## ❌ Internal Scripts (DO NOT CALL DIRECTLY)

These scripts are **supporting components** and should **never** be called directly:

### SQL Scripts

All SQL scripts in `sql/dwh/` are called internally by the entry point scripts:

- `ETL_*.sql` - Called by `ETL.sh`
- `Staging_*.sql` - Called by `ETL.sh` during staging phase
- `datamartCountries/*.sql` - Called by `datamartCountries.sh`
- `datamartUsers/*.sql` - Called by `datamartUsers.sh`
- `datamartGlobal/*.sql` - Called by `datamartGlobal.sh`

**Never execute SQL scripts directly** - they are called by the entry point scripts with proper
error handling and logging.

## Examples

### ✅ Correct Usage

```bash
# Initial setup workflow
./bin/dwh/ETL.sh

# Regular updates workflow
./bin/dwh/ETL.sh

# Update datamarts manually (if needed)
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/datamartUsers/datamartUsers.sh

# Generate profiles
./bin/dwh/profile.sh --user AngocA
./bin/dwh/profile.sh --country Colombia

# Export to JSON
./bin/dwh/exportDatamartsToJSON.sh

# Cleanup temporary files (safe)
./bin/dwh/cleanupDWH.sh --remove-temp-files
```

### ❌ Incorrect Usage (DO NOT CALL)

```bash
# SQL scripts - should not be executed directly
psql -d notes_dwh -f sql/dwh/ETL_20_createDWHTables.sql  # WRONG (use ETL.sh instead)
```

## Workflow Examples

### Initial Setup (First Time)

```bash
# 1. Run initial ETL (creates DWH, populates facts and dimensions, updates datamarts)
./bin/dwh/ETL.sh

# 2. Verify datamarts are populated
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartcountries;"
psql -d notes_dwh -c "SELECT COUNT(*) FROM dwh.datamartusers;"

# 3. Generate a test profile
./bin/dwh/profile.sh --user AngocA

# 4. Export to JSON (optional)
./bin/dwh/exportDatamartsToJSON.sh
```

### Regular Updates (Scheduled)

```bash
# 1. Incremental ETL (processes new data, updates datamarts automatically)
./bin/dwh/ETL.sh

# 2. Export to JSON and push to GitHub (optional)
./bin/dwh/exportAndPushJSONToGitHub.sh
```

### Manual Datamart Updates

```bash
# If you need to manually update datamarts (usually not needed, ETL does this automatically)
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/datamartUsers/datamartUsers.sh
./bin/dwh/datamartGlobal/datamartGlobal.sh
```

## Implementation Notes

### Current Behavior

- All entry point scripts include help text (`--help` or `-h`)
- Scripts validate prerequisites before execution
- Lock files prevent concurrent execution
- Comprehensive logging to `/tmp/` directories

### Best Practices

1. **Always use entry points**: Never call internal scripts or SQL files directly
2. **Check prerequisites**: Ensure base tables exist before running ETL
3. **Use auto-detect mode**: Simply run `ETL.sh` without arguments - it handles both first execution
   and incremental updates automatically
4. **Monitor logs**: Check log files in `/tmp/` for execution details
5. **Use dry-run**: For cleanup operations, always use `--dry-run` first

## For Developers

If you need functionality from an internal script:

1. Check if there's a proper entry point that provides this functionality
2. If not, create a proper entry point or extend an existing one
3. Never call internal scripts directly in new code
4. Follow the established patterns for error handling and logging

## See Also

- [bin/README.md](./README.md) - Complete script documentation
- [bin/dwh/ENVIRONMENT_VARIABLES.md](./Environment_Variables.md) - Environment variables
  documentation
- [bin/dwh/README.md](./README.md) - DWH-specific documentation
- [docs/ETL_Enhanced_Features.md](../../docs/ETL_Enhanced_Features.md) - ETL features documentation
