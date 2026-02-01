---
title: "Incremental JSON Export"
description:
  "The JSON export system has been optimized to use incremental processing, only exporting entities"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "export"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Incremental JSON Export

## Overview

The JSON export system has been optimized to use incremental processing, only exporting entities
(users and countries) that have been modified. This significantly reduces export time and data
transfer, especially for large datasets.

## How It Works

### 1. Export Flag Tracking

The datamart tables include a `json_exported` flag:

```sql
json_exported BOOLEAN DEFAULT FALSE
```

This flag tracks whether each entity has been exported to JSON.

### 2. Modified Detection

The export script uses the `modified` flag from dimension tables:

- `dwh.dimension_users.modified`
- `dwh.dimension_countries.modified`

When entities are updated during the ETL process, their `modified` flag is set to `TRUE`.

### 3. Incremental Export Process

```bash
# Reset export flags for modified entities
UPDATE dwh.datamartusers
SET json_exported = FALSE
FROM dwh.dimension_users
WHERE datamartusers.dimension_user_id = dimension_users.dimension_user_id
  AND dimension_users.modified = TRUE;

# Export only entities with json_exported = FALSE
SELECT user_id, username
FROM dwh.datamartusers
WHERE user_id IS NOT NULL
  AND json_exported = FALSE;

# Mark as exported after successful export
UPDATE dwh.datamartusers
SET json_exported = TRUE
WHERE user_id = ${user_id};
```

### 4. Preserving Unchanged Files

The export script:

1. Copies existing JSON files to temporary directory
2. Only exports new/modified entities
3. Validates only modified files
4. Atomically replaces all files

This ensures unchanged files remain unchanged and are not unnecessarily regenerated or re-validated.

## Benefits

### Performance Improvements

- **Export Time**: Reduced by 90-99% for incremental updates
- **Database Load**: Only queries modified entities
- **Validation**: Only validates changed files
- **Git Transfer**: Only pushes modified files (git detects changes)

### Example Scenarios

#### Initial Export (10,000 users)

```bash
# Export all 10,000 users
Time: ~15 minutes
Files: 10,000 JSON files
```

#### Incremental Update (50 modified users)

```bash
# Export only 50 modified users
Time: ~30 seconds
Files: Only 50 JSON files changed
Transfer: ~250 KB vs ~50 MB
```

### Real-World Performance

| Scenario               | Old System | Optimized | Improvement   |
| ---------------------- | ---------- | --------- | ------------- |
| 10K users, full export | 15 min     | 15 min    | 0% (one-time) |
| 10K users, 50 modified | 15 min     | 30 sec    | 97% faster    |
| 10K users, 5 modified  | 15 min     | 10 sec    | 99% faster    |

## Integration with ETL

The incremental export integrates seamlessly with the ETL process:

### Recommended Workflow

```bash
# 1. Run ETL (updates dimension.modified flags)
./bin/dwh/ETL.sh

# 2. Update datamarts (processes only modified entities)
./bin/dwh/datamartUsers/datamartUsers.sh
./bin/dwh/datamartCountries/datamartCountries.sh

# 3. Export JSON (exports only modified entities)
./bin/dwh/exportDatamartsToJSON.sh
```

The export script automatically:

1. Detects entities marked as `modified = TRUE` in dimension tables
2. Resets their `json_exported` flag to `FALSE`
3. Exports only those entities
4. Marks them as `json_exported = TRUE`

## Manual Operations

### Force Full Export

To force a full export (ignore incrementality):

```bash
# Reset all export flags
psql -d notes -c "UPDATE dwh.datamartusers SET json_exported = FALSE;"
psql -d notes -c "UPDATE dwh.datamartcountries SET json_exported = FALSE;"

# Run export
./bin/dwh/exportDatamartsToJSON.sh
```

### Check Export Status

```bash
# Check how many users are pending export
psql -d notes -c "
  SELECT COUNT(*) as pending_users
  FROM dwh.datamartusers
  WHERE json_exported = FALSE;
"

# Check how many countries are pending export
psql -d notes -c "
  SELECT COUNT(*) as pending_countries
  FROM dwh.datamartcountries
  WHERE json_exported = FALSE;
"
```

### Reset All Export Flags

```bash
# Mark all as not exported (will trigger full export on next run)
psql -d notes -c "UPDATE dwh.datamartusers SET json_exported = FALSE;"
psql -d notes -c "UPDATE dwh.datamartcountries SET json_exported = FALSE;"
```

## Schema Changes

When datamart schema changes (new columns added), you should:

```bash
# 1. Reset all flags to force re-export
psql -d notes -c "UPDATE dwh.datamartusers SET json_exported = FALSE;"
psql -d notes -c "UPDATE dwh.datamartcountries SET json_exported = FALSE;"

# 2. Update version in .json_export_version
echo "1.1.0" > .json_export_version

# 3. Run export
./bin/dwh/exportDatamartsToJSON.sh
```

## Monitoring

### Export Statistics

The export script provides statistics:

```bash
# Example output
Exporting users datamart (incremental)...
  Copying existing user files...
  Exported modified user: 12345 (username1)
  Exported modified user: 67890 (username2)
  Total modified users exported: 50

Exporting countries datamart (incremental)...
  Copying existing country files...
  Exported modified country: 123 (Country1)
  Total modified countries exported: 3
```

### Log File

Export logs are captured:

```bash
./bin/dwh/exportDatamartsToJSON.sh > /tmp/json-export.log 2>&1
```

## Troubleshooting

### No Files Exported

If the export reports "No modified users/countries to export":

```bash
# Check if there are pending exports
psql -d notes -c "
  SELECT COUNT(*) FROM dwh.datamartusers WHERE json_exported = FALSE;
"

# Check if dimension tables have modified flags
psql -d notes -c "
  SELECT COUNT(*) FROM dwh.dimension_users WHERE modified = TRUE;
"
```

### Missing Files After Export

If files appear to be missing:

```bash
# Verify files were copied
ls -l output/json/users/ | wc -l
ls -l output/json/countries/ | wc -l

# Check file permissions
find output/json -type f ! -readable -ls
```

### Stale Data

If data appears stale despite exports:

1. Check datamart population:

   ```bash
   ./bin/dwh/datamartUsers/datamartUsers.sh
   ./bin/dwh/datamartCountries/datamartCountries.sh
   ```

2. Verify dimension modified flags:

   ```bash
   psql -d notes -c "SELECT * FROM dwh.dimension_users WHERE modified = TRUE LIMIT 5;"
   ```

3. Force re-export:
   ```bash
   psql -d notes -c "UPDATE dwh.datamartusers SET json_exported = FALSE;"
   ./bin/dwh/exportDatamartsToJSON.sh
   ```

## Related Documentation

- [JSON Export System](../bin/dwh/export_json_readme.md)
- [Version Compatibility](Version_Compatibility.md)
- [ETL Process](../bin/dwh/README.md)
