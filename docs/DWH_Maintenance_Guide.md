---
title: "data warehouse Maintenance and Cleanup Guide"
description:
  "This guide covers maintenance operations for the OSM-Notes-Analytics data warehouse, including
  when"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "database"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# data warehouse Maintenance and Cleanup Guide

## 📋 Overview

This guide covers maintenance operations for the OSM-Notes-Analytics data warehouse, including when
and how to use the cleanup script safely.

---

## 🧹 Cleanup Script: `cleanupDWH.sh`

### Purpose

The cleanup script removes data warehouse objects and temporary files. It's designed for:

- Development environment resets
- Troubleshooting corrupted objects
- Regular maintenance of temporary files
- Complete environment cleanup

### ⚠️ Safety Features

The script includes several safety mechanisms:

1. **Confirmation prompts** for destructive operations
2. **Dry-run mode** to preview operations
3. **Granular options** to control what gets removed
4. **Clear warnings** about data loss

---

## 🎯 When to Use Cleanup

### Safe Operations (No Data Loss)

#### Regular Maintenance

```bash
# Clean temporary files (safe, no confirmation)
./bin/dwh/cleanupDWH.sh --remove-temp-files
```

**When to use:**

- After ETL runs to free disk space
- Before running tests to ensure clean environment
- Regular maintenance (weekly/monthly)
- When `/tmp` directory is getting full

#### Preview Operations

```bash
# See what would be removed (safe)
./bin/dwh/cleanupDWH.sh --dry-run
```

**When to use:**

- Before any destructive operation
- Understanding what cleanup will do
- Planning maintenance windows
- Troubleshooting cleanup issues

### Destructive Operations (Data Loss)

#### Complete Reset

```bash
# Remove everything (requires confirmation)
./bin/dwh/cleanupDWH.sh
```

**When to use:**

- Starting fresh development environment
- After major schema changes
- Resolving complex corruption issues
- Before initial ETL setup

#### DWH Objects Only

```bash
# Remove only database objects (requires confirmation)
./bin/dwh/cleanupDWH.sh --remove-all-data
```

**When to use:**

- Schema corruption issues
- Before schema migrations
- Testing schema changes
- Resolving constraint violations

---

## 🔄 Common Workflows

### Development Environment Reset

```bash
# 1. Preview what will be removed
./bin/dwh/cleanupDWH.sh --dry-run

# 2. Remove everything (with confirmation)
./bin/dwh/cleanupDWH.sh

# 3. Recreate data warehouse (auto-detects first execution)
./bin/dwh/ETL.sh
```

### Regular Maintenance

```bash
# Clean temporary files only
./bin/dwh/cleanupDWH.sh --remove-temp-files
```

### Troubleshooting Schema Issues

```bash
# 1. Preview DWH cleanup
./bin/dwh/cleanupDWH.sh --dry-run

# 2. Remove only DWH objects
./bin/dwh/cleanupDWH.sh --remove-all-data

# 3. Recreate schema (auto-detects first execution)
./bin/dwh/ETL.sh
```

### Testing Environment

```bash
# Clean between test runs
./bin/dwh/cleanupDWH.sh --remove-temp-files

# Or complete reset for integration tests
./bin/dwh/cleanupDWH.sh --dry-run  # Preview first
./bin/dwh/cleanupDWH.sh            # Full cleanup
```

---

## 📊 What Gets Removed

### DWH Objects (`--remove-all-data` or default)

**Schemas:**

- `staging` - Staging area objects
- `dwh` - data warehouse schema

**Tables:**

- `dwh.facts` - Main fact table (partitioned)
- `dwh.dimension_*` - All dimension tables
- `dwh.datamartCountries` - Country analytics
- `dwh.datamartUsers` - User analytics
- `dwh.iso_country_codes` - ISO codes reference

**Functions:**

- `dwh.get_*` - Helper functions
- `dwh.update_*` - Update functions
- `dwh.refresh_*` - Refresh functions

**Triggers:**

- `update_days_to_resolution` - Fact table trigger

### Temporary Files (`--remove-temp-files` or default)

**Directories removed:**

- `/tmp/ETL_*` - ETL temporary files
- `/tmp/datamartCountries_*` - Country datamart temp files
- `/tmp/datamartUsers_*` - User datamart temp files
- `/tmp/profile_*` - Profile analysis temp files
- `/tmp/cleanupDWH_*` - Cleanup script temp files

---

## ⚙️ Configuration

### Database Configuration

The script uses database configuration from `etc/properties.sh`:

```bash
# Database configuration (recommended: use DBNAME_INGESTION and DBNAME_DWH)
# Option 1: Separate databases
DBNAME_INGESTION="notes_dwh"
DBNAME_DWH="notes_dwh"

# Option 2: Same database (legacy/compatibility)
DBNAME="notes_dwh"  # Used when both databases are the same

# Database user
DB_USER="notes"
```

### Prerequisites

- Database must exist and be accessible
- User must have DROP privileges on target schemas
- PostgreSQL client tools (`psql`) must be installed
- Script must be run from project root directory

---

## 🚨 Safety Guidelines

### Before Any Destructive Operation

1. **Always run dry-run first:**

   ```bash
   ./bin/dwh/cleanupDWH.sh --dry-run
   ```

2. **Backup important data** if needed

3. **Verify database configuration** in `etc/properties.sh`

4. **Ensure you have proper privileges**

### Best Practices

- Use `--remove-temp-files` for regular maintenance
- Use `--dry-run` before any destructive operation
- Keep backups of important data
- Test cleanup procedures in development first
- Document any custom cleanup procedures

### Emergency Procedures

If cleanup fails or causes issues:

1. **Check logs** in `/tmp/cleanupDWH_*` directories
2. **Verify database connectivity**
3. **Check user privileges**
4. **Review SQL script files** for syntax errors
5. **Contact database administrator** if needed

---

## 🔍 Troubleshooting

### Common Issues

#### Permission Denied

```
ERROR: Permission denied for schema dwh
```

**Solution:** Ensure user has DROP privileges on schemas

#### Database Not Found

```
ERROR: Database 'notes_dwh' does not exist
```

**Solution:** Check `etc/properties.sh` configuration

#### SQL Script Errors

```
ERROR: SQL file validation failed
```

**Solution:** Check SQL script syntax and file permissions

### Getting Help

```bash
# Show detailed help
./bin/dwh/cleanupDWH.sh --help
```

---

## 📚 Related Documentation

- [ETL Enhanced Features](ETL_Enhanced_Features.md) - ETL capabilities and configuration
- [DWH Star Schema Data Dictionary](DWH_Star_Schema_Data_Dictionary.md) - Table definitions
- [bin/README.md](../bin/README.md) - Script documentation
- [Main README](../README.md) - Project overview

---

## 🏷️ Version History

- **2025-10-22**: Initial documentation
- **2025-10-22**: Added safety guidelines and troubleshooting
- **2025-10-22**: Updated with new script options and workflows
