# Star Schema Documentation

This document provides a high-level overview of the star schema. For complete documentation, see:

- **[DWH Star Schema ERD](../../docs/DWH_Star_Schema_ERD.md)** - Complete entity-relationship
  diagram
- **[Data Dictionary](../../docs/DWH_Star_Schema_Data_Dictionary.md)** - Detailed column definitions
- **[ETL Enhanced Features](../../docs/ETL_Enhanced_Features.md)** - ETL capabilities

## Overview

The data warehouse uses a **star schema design**:

- **Fact Table**: `dwh.facts` - One row per note action (partitioned by year)
- **Dimension Tables**: Users, countries, dates, times, applications, hashtags, etc.
- **ETL Flow**: Transforms base tables into star schema

**For complete documentation:**

- **[DWH Star Schema ERD](../../docs/DWH_Star_Schema_ERD.md)** - Complete entity-relationship
  diagram and schema design
- **[Data Dictionary](../../docs/DWH_Star_Schema_Data_Dictionary.md)** - Detailed column definitions
  for all tables

## ETL Flow (High Level)

**Note:** For detailed ETL process flow, see
[ETL Enhanced Features](../../docs/ETL_Enhanced_Features.md) and
[SQL README](../../sql/README.md#execution-flow).

```mermaid
flowchart TD
  A[Base tables: notes, note_comments, note_comments_text, users, countries]
    --> B[Staging functions & procedures]
  B -->|process_notes_at_date / per-year variants| C[staging.facts_${YEAR}]
  C --> D[Unify]
  D --> E[dwh.facts]
  B --> F[Update dimensions]
  F --> E
```

**Process Overview:**

- The staging procedures select note actions from base tables by date, resolve dimensional keys, and
  write to `staging.facts_${YEAR}` or directly to `dwh.facts` depending on the path.
- The unify step ensures `recent_opened_dimension_id_date` is filled for all facts before enforcing
  NOT NULL.
- A trigger computes resolution-day metrics when a closing action is inserted.

**For complete ETL documentation:**

- See [ETL Enhanced Features](../../docs/ETL_Enhanced_Features.md) for capabilities and
  configuration
- See [SQL README](../../sql/README.md#execution-flow) for detailed SQL execution flow

Key scripts:

- `sql/dwh/ETL_20_createDWHTables.sql`
- `sql/dwh/ETL_40_addConstraintsIndexesTriggers.sql`
- `sql/dwh/ETL_25_populateDimensionTables.sql`
- `sql/dwh/ETL_26_updateDimensionTables.sql`
- `sql/dwh/Staging_31_createBaseStagingObjects.sql`
- `sql/dwh/Staging_32_createStagingObjects.sql`
- `sql/dwh/Staging_34_initialFactsLoadCreate.sql`
- `sql/dwh/Staging_35_initialFactsLoadExecute.sql`
- `sql/dwh/Staging_50_unify.sql`

### Schema Overview

**Fact Table:**

- `dwh.facts` - One row per note action (opened, closed, commented, reopened, hidden)
  - Partitioned by year (2013-2025+) for optimal performance
  - Contains 30+ columns including metrics (days_to_resolution, etc.)
  - Includes temporal dimensions: `action_dimension_id_season` (season analysis),
    `action_timezone_id` (timezone for local time), `local_action_dimension_id_date` (local date
    based on timezone)
  - See [Data Dictionary](../../docs/DWH_Star_Schema_Data_Dictionary.md#table-dwhfacts) for complete
    column definitions

**Dimension Tables:**

- `dimension_users` - User information with SCD2 support
- `dimension_countries` - Countries with ISO codes and regions
- `dimension_days` - Date dimension with enhanced attributes (iso_week, quarter, month_name, etc.)
- `dimension_time_of_week` - Hour of week with period of day (Night/Morning/Afternoon/Evening)
- `dimension_timezones` - Timezone information (IANA tz names, UTC offsets) for local time analysis
- `dimension_seasons` - Seasons (Spring, Summer, Autumn, Winter) for temporal analysis
- `dimension_continents` - Continents (Americas, Europe, Asia, Africa, Oceania, Antarctica)
- `dimension_applications` - Applications used to create notes
- `dimension_hashtags` - Hashtags found in notes
- Plus additional dimensions (regions, automation levels, experience levels)

**Datamart Tables:**

- `dwh.datamartUsers` - Pre-computed user analytics (70+ metrics)
- `dwh.datamartCountries` - Pre-computed country analytics (70+ metrics)
- `dwh.datamartGlobal` - Global statistics

**For complete schema documentation:**

- **[DWH Star Schema ERD](../../docs/DWH_Star_Schema_ERD.md)** - Complete entity-relationship
  diagram with all relationships
- **[Data Dictionary](../../docs/DWH_Star_Schema_Data_Dictionary.md)** - Detailed column definitions
  for all tables

### Operational files

- `bin/dwh/ETL.sh`: Orchestrates the ETL process, validates SQL, populates dimensions, and loads
  facts incrementally.
- `bin/dwh/profile.sh`: Generates profiles for a country or a user against the datamarts.
- `bin/dwh/exportDatamartsToJSON.sh`: Exports datamarts to JSON files for web viewer consumption
  with atomic writes and schema validation.
- `bin/dwh/exportAndPushJSONToGitHub.sh`: Exports JSON files and automatically deploys them to
  GitHub Pages data repository.

## JSON Export

The `exportDatamartsToJSON.sh` script exports datamart data to JSON files for consumption by the web
viewer. For automated deployment to GitHub Pages, use `exportAndPushJSONToGitHub.sh` instead. The
export script also automatically copies JSON schemas to the data repository for frontend
consumption. It provides:

### Features

- **Atomic writes**: Files generated in temporary directory, validated, then moved atomically
- **Schema validation**: Each JSON file validated against schemas before export
- **Fail-safe**: On validation failure, keeps existing files and logs error
- **No partial updates**: Either all files are valid and moved, or none

### Usage

```bash
# Basic export
./bin/dwh/exportDatamartsToJSON.sh

# With custom output directory
export JSON_OUTPUT_DIR=/var/www/osm-notes-data
./bin/dwh/exportDatamartsToJSON.sh
```

### Output Structure

```
output/json/
├── users/
│   ├── 123.json
│   ├── 456.json
│   └── ...
├── countries/
│   ├── 1.json
│   ├── 2.json
│   └── ...
├── indexes/
│   ├── users.json
│   └── countries.json
├── metadata.json
└── global_stats.json
```

**Note:** When using `exportAndPushJSONToGitHub.sh`, JSON schemas are also copied to
`OSM-Notes-Data/schemas/` for frontend consumption. Schemas are available at:

- GitHub Pages: `https://osm-notes.github.io/OSM-Notes-Data/schemas/`
- Local: `OSM-Notes-Data/schemas/` (when repository is cloned)

### CSV Export for AI Context

Export closed notes to CSV files (one per country) for AI assistant context:

```bash
# Export and push to GitHub repository (does everything in one step)
./bin/dwh/exportAndPushCSVToGitHub.sh
```

**Output:**

- CSV files in `exports/csv/notes-by-country/`
- One file per country: `{country_id}_{country_name}.csv`
- Files contain cleaned comments (max 2000 chars, newlines removed, quotes normalized)
- Optimized column order for AI context understanding

**CSV Structure:**

- Basic info: note_id, country, location, dates
- Problem: opening_comment, opened_by_username
- Context: total_comments, was_reopened, days_to_resolution
- Solution: closing_comment, closed_by_username

**Scheduling:**

- Recommended: Monthly export (1st day of month at 3 AM)
- See `etc/cron.example` for cron configuration

**Production Setup:**

- For automated pushes from production (e.g., `notes` user), see `docs/GitHub_Push_Setup.md`
- Configure SSH keys or Personal Access Token for git authentication
- Test push before enabling cron: `./bin/dwh/exportAndPushCSVToGitHub.sh`

**CSV History:**

- CSV files are automatically replaced on each export (no history preserved)
- Other files in the repository maintain their full history
- The script uses `git rm --cached` to remove CSV from tracking before adding new ones

For complete schema location documentation, see
[JSON Schema Location](../../docs/JSON_Schema_Location.md).

The `global_stats.json` file contains aggregated statistics for the entire system:

- Total notes opened/closed/commented
- Unique users and countries
- Currently open notes
- First and latest notes in the system
- Global resolution metrics
- Recent activity (last 30 days, this year)

### Cron Integration

For automated exports with GitHub Pages deployment:

```bash
# Export and push to GitHub Pages every 15 minutes after datamarts update
45 2 * * * ~/OSM-Notes-Analytics/bin/dwh/exportAndPushJSONToGitHub.sh
```

**Note:** This replaces `exportDatamartsToJSON.sh` in cron jobs for production environments using
GitHub Pages. The `exportAndPushJSONToGitHub.sh` script handles both export and deployment
automatically.

Or use a complete workflow wrapper:

```bash
# Complete pipeline: ETL → Datamarts → JSON Export
*/15 * * * * /opt/osm-analytics/update-and-export.sh
```

See [Atomic Validation Export](docs/Atomic_Validation_Export.md) for detailed documentation.
