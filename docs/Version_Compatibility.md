---
title: "Version Compatibility System for JSON Exports"
description:
  "The JSON export system uses semantic versioning to ensure compatibility between exported data and"
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

# Version Compatibility System for JSON Exports

## Overview

The JSON export system uses semantic versioning to ensure compatibility between exported data and
the web viewer. This document explains how the versioning system works and how the viewer should
verify compatibility.

## Version Format

The version follows [Semantic Versioning](https://semver.org/) specification:

```
MAJOR.MINOR.PATCH

Examples:
- 1.0.0  (initial release)
- 1.0.1  (patch: bug fixes)
- 1.1.0  (minor: new features, backward compatible)
- 2.0.0  (major: breaking changes)
```

## Version Tracking

### Version File

The current export version is tracked in: `.json_export_version`

Example:

```
1.2.3
```

This file is automatically created and updated by the export script.

### Schema Hash

A SHA256 hash of the datamart schema is calculated to detect schema changes:

```bash
# Example schema hash
0a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

This hash changes when columns are added, removed, or modified in the datamart tables.

## Metadata Structure

Every export includes a `metadata.json` file with version information:

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

### Fields

- **export_date**: ISO 8601 timestamp of export
- **export_timestamp**: Unix timestamp
- **total_users**: Count of user files exported
- **total_countries**: Count of country files exported
- **version**: Current semantic version of the export
- **schema_version**: Version of the JSON schema definitions
- **api_compat_min**: Minimum viewer version required
- **data_schema_hash**: SHA256 hash of datamart schema

## Viewer Compatibility Check

The web viewer should perform the following compatibility checks before consuming data:

### 1. Fetch Metadata

```javascript
// Fetch metadata.json from the data repository
const response = await fetch("/data/metadata.json");
const metadata = await response.json();
```

### 2. Check Minimum API Version

```javascript
// Compare viewer version with minimum required version
function versionCompare(v1, v2) {
  const a = v1.split(".").map(Number);
  const b = v2.split(".").map(Number);

  for (let i = 0; i < 3; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}

// Get viewer version (from build-time constant or API)
const VIEWER_VERSION = "1.0.0"; // Replace with actual viewer version

if (versionCompare(VIEWER_VERSION, metadata.api_compat_min) < 0) {
  throw new Error(
    `Viewer version ${VIEWER_VERSION} is too old. Minimum required: ${metadata.api_compat_min}`,
  );
}
```

### 3. Detect Breaking Changes (MAJOR version increment)

```javascript
// Compare major version numbers
const [major] = metadata.version.split(".").map(Number);
const [currentMajor] = localStorage.getItem("lastVersion", "1.0.0").split(".").map(Number);

if (major > currentMajor) {
  console.warn("Breaking changes detected! Viewer may need update.");
  // Show warning to user
}

// Store current version
localStorage.setItem("lastVersion", metadata.version);
```

### 4. Schema Hash Verification (Optional)

```javascript
// Compare schema hashes for change detection
const lastHash = localStorage.getItem("lastSchemaHash");
if (lastHash && lastHash !== metadata.data_schema_hash) {
  console.info("Schema changes detected. Data structure may have changed.");
}

localStorage.setItem("lastSchemaHash", metadata.data_schema_hash);
```

## Complete Viewer Implementation Example

```javascript
// api-compatibility.js

const VIEWER_VERSION = "1.0.0"; // Set at build time
const METADATA_URL = "/data/metadata.json";

class ApiCompatibilityChecker {
  constructor() {
    this.metadata = null;
  }

  async check() {
    try {
      // Fetch metadata
      const response = await fetch(METADATA_URL);
      this.metadata = await response.json();

      // Check minimum API version
      if (this.versionCompare(VIEWER_VERSION, this.metadata.api_compat_min) < 0) {
        return {
          compatible: false,
          error: `Viewer version ${VIEWER_VERSION} is incompatible. Minimum required: ${this.metadata.api_compat_min}`,
        };
      }

      // Check for breaking changes
      const breakingChange = this.detectBreakingChange(this.metadata.version);
      if (breakingChange) {
        return {
          compatible: true,
          warning: breakingChange,
        };
      }

      // Update stored version
      this.updateStoredVersion(this.metadata);

      return {
        compatible: true,
        version: this.metadata.version,
        timestamp: this.metadata.export_timestamp,
      };
    } catch (error) {
      return {
        compatible: false,
        error: `Failed to check compatibility: ${error.message}`,
      };
    }
  }

  versionCompare(v1, v2) {
    const a = v1.split(".").map(Number);
    const b = v2.split(".").map(Number);

    for (let i = 0; i < 3; i++) {
      if (a[i] < b[i]) return -1;
      if (a[i] > b[i]) return 1;
    }
    return 0;
  }

  detectBreakingChange(currentVersion) {
    const lastVersion = localStorage.getItem("lastExportVersion") || "1.0.0";
    const [lastMajor] = lastVersion.split(".").map(Number);
    const [currentMajor] = currentVersion.split(".").map(Number);

    if (currentMajor > lastMajor) {
      return `Breaking changes detected (v${lastVersion} → v${currentVersion}). Some features may not work correctly.`;
    }

    return null;
  }

  updateStoredVersion(metadata) {
    localStorage.setItem("lastExportVersion", metadata.version);
    localStorage.setItem("lastExportTimestamp", metadata.export_timestamp);
    localStorage.setItem("lastSchemaHash", metadata.data_schema_hash);
  }

  getMetadata() {
    return this.metadata;
  }
}

// Usage in viewer
const checker = new ApiCompatibilityChecker();

checker.check().then((result) => {
  if (!result.compatible) {
    // Display error and prevent data loading
    document.getElementById("error").textContent = result.error;
    document.getElementById("error").style.display = "block";
    return;
  }

  if (result.warning) {
    // Show warning but allow data loading
    console.warn(result.warning);
    // Optionally show user-visible warning
  }

  // Proceed with normal data loading
  loadUserData();
});
```

## Version Bumping

### Automatic Versioning

The export script automatically increments the version:

- **Patch** (1.0.0 → 1.0.1): Data structure unchanged, data refresh
- **Minor** (1.0.1 → 1.1.0): New fields added (backward compatible)
- **Major** (1.1.0 → 2.0.0): Breaking changes (fields removed/renamed)

### Manual Version Bump

To force a specific version:

```bash
# In the project root
echo "2.0.0" > .json_export_version
```

Or increment programmatically:

```bash
# Patch increment (default)
./bin/dwh/exportDatamartsToJSON.sh

# Force minor increment
VERSION_INCREMENT=minor ./bin/dwh/exportDatamartsToJSON.sh

# Force major increment
VERSION_INCREMENT=major ./bin/dwh/exportDatamartsToJSON.sh
```

## Best Practices

1. **Always check `api_compat_min`** before loading data
2. **Handle version incompatibilities gracefully** (show user-friendly error)
3. **Cache metadata** to avoid repeated fetches
4. **Log version changes** for debugging
5. **Update viewer version** in package.json/version file
6. **Use schema hash** for advanced change detection

## Example Error Messages

```javascript
// Too old viewer
"Your viewer is outdated. Please update to version 1.1.0 or later.";

// Breaking changes detected
"Data format has changed (v1 → v2). Some features may not work as expected.";

// Schema changes
"The data structure has been updated. Refreshing...";
```

## Testing Compatibility

To test viewer compatibility with different versions:

1. Change version in `.json_export_version`
2. Re-run export: `./bin/dwh/exportDatamartsToJSON.sh`
3. Test viewer with new metadata
4. Verify compatibility checks work correctly

## Schema Validation

JSON files are validated against schemas in `lib/osm-common/schemas/`:

- `metadata.schema.json` - Metadata structure
- `user-profile.schema.json` - User data
- `country-profile.schema.json` - Country data
- `user-index.schema.json` - User index
- `country-index.schema.json` - Country index

Validation is performed during export. Invalid files prevent the export from completing.

## Migration Guide

When upgrading to a new major version:

1. Update viewer to support new version
2. Check changelog for breaking changes
3. Test with new export data
4. Deploy updated viewer before new exports go live

## Related Documentation

- [JSON Export Documentation](../bin/dwh/export_json_readme.md)
- [Atomic Validation Export](Atomic_Validation_Export.md)
- [ETL Process Documentation](ETL_Enhanced_Features.md)
