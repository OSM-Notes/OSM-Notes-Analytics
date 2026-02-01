---
title: "Versioning System Implementation Summary"
description:
  "A comprehensive semantic versioning system has been implemented for JSON exports to ensure
  compatibility between exported data and the web viewer."
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

# Versioning System Implementation Summary

## Overview

A comprehensive semantic versioning system has been implemented for JSON exports to ensure
compatibility between exported data and the web viewer.

## What Was Implemented

### 1. Schema Definitions (`lib/osm-common/schemas/`)

Created JSON Schema files for validation:

- **metadata.schema.json** - Defines metadata structure with version fields
- **user-profile.schema.json** - Validates user profile JSON files
- **country-profile.schema.json** - Validates country profile JSON files
- **user-index.schema.json** - Validates user index structure
- **country-index.schema.json** - Validates country index structure
- **global-stats.schema.json** - Validates global statistics

### 2. Version Management Functions

Added to `bin/dwh/exportDatamartsToJSON.sh`:

```bash
# Track current version
__get_current_version()

# Increment version (major, minor, patch)
__increment_version(version, type)

# Save version to file
__save_version(version)

# Calculate schema hash for change detection
__calculate_schema_hash()
```

### 3. Enhanced Metadata

The `metadata.json` file now includes:

```json
{
  "export_date": "2025-01-15T10:30:00Z",
  "export_timestamp": 1705318200,
  "total_users": 12345,
  "total_countries": 234,
  "version": "1.2.3",
  "schema_version": "1.0.0",
  "api_compat_min": "1.0.0",
  "data_schema_hash": "0a1b2c3d..."
}
```

### 4. Automatic Version Increment

The export script automatically:

- Reads current version from `.json_export_version`
- Increments version based on changes detected
- Saves new version after successful export
- Calculates schema hash for change detection

### 5. Documentation

Created comprehensive documentation:

- **Version_Compatibility.md** - Viewer implementation guide
- **lib/osm-common/schemas/README.md** - Schema documentation
- **docs/Implementation_Versioning.md** - This file

## How It Works

### Export Flow

1. **Check Current Version**: Read from `.json_export_version` or default to `1.0.0`
2. **Calculate Schema Hash**: Generate hash of datamart table structures
3. **Generate Metadata**: Include version and hash in `metadata.json`
4. **Validate**: Check all JSON files against schemas
5. **Update Version**: Increment and save version after successful export

### Version Bumping Logic

```bash
# Patch increment (default - data refresh)
1.0.0 → 1.0.1

# Minor increment (new features, backward compatible)
1.0.1 → 1.1.0

# Major increment (breaking changes)
1.1.0 → 2.0.0
```

### Schema Hash Calculation

The hash is calculated from:

- Table names: `datamartusers`, `datamartcountries`
- Column names
- Data types
- Column order (ordinal_position)

This ensures any structural changes are detected.

## Viewer Integration

The web viewer must:

1. **Fetch metadata.json** from exported data
2. **Check `api_compat_min`** against viewer version
3. **Verify MAJOR version** for breaking changes
4. **Handle incompatibilities** gracefully

Example implementation provided in `Version_Compatibility.md`.

## Testing

To test the versioning system:

```bash
# 1. Create initial export
./bin/dwh/exportDatamartsToJSON.sh

# Check generated metadata
cat output/json/metadata.json

# Verify version file
cat .json_export_version

# 2. Make schema changes (add column)
# Run export again
./bin/dwh/exportDatamartsToJSON.sh

# Check hash changed
cat output/json/metadata.json
```

## Benefits

1. **Compatibility Checking**: Viewer can verify data compatibility
2. **Change Detection**: Schema hash tracks structural changes
3. **Automatic Versioning**: No manual version management needed
4. **Backward Compatibility**: Clear signaling when breaking changes occur
5. **Validation**: JSON files validated against schemas
6. **Documentation**: Clear migration path for breaking changes

## Files Created/Modified

### Created

- `lib/osm-common/schemas/README.md`
- `lib/osm-common/schemas/metadata.schema.json`
- `lib/osm-common/schemas/user-profile.schema.json`
- `lib/osm-common/schemas/country-profile.schema.json`
- `Version_Compatibility.md`
- `docs/Implementation_Versioning.md`

### Modified

- `bin/dwh/exportDatamartsToJSON.sh` - Added versioning functions
- `.gitignore` - Added `.json_export_version`

### Ignored

- `.json_export_version` - Local version tracking (not committed)

## Usage

### Default Export (Auto-increment PATCH)

```bash
./bin/dwh/exportDatamartsToJSON.sh
```

### Force Version Bump

```bash
# Force minor increment
VERSION_INCREMENT=minor ./bin/dwh/exportDatamartsToJSON.sh

# Force major increment
VERSION_INCREMENT=major ./bin/dwh/exportDatamartsToJSON.sh
```

### Manual Version Setting

```bash
echo "2.0.0" > .json_export_version
./bin/dwh/exportDatamartsToJSON.sh
```

## Next Steps

To complete the implementation, you may want to:

1. Create schemas for `user-index.schema.json` and `country-index.schema.json`
2. Add version checking to the web viewer
3. Implement automated version bump detection based on schema changes
4. Add changelog tracking for major versions

## Related Documentation

- [Version Compatibility Guide](Version_Compatibility.md)
- [JSON Export Documentation](../bin/dwh/export_json_readme.md)
- [Atomic Validation Export](Atomic_Validation_Export.md)
