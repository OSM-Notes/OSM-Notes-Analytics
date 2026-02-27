---
title: "JSON Export Schema Documentation"
description:
  "The OSM-Notes-Analytics system exports datamart data to JSON files for consumption by web viewers"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "database"
  - "export"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# JSON Export Schema Documentation

## Overview

The OSM-Notes-Analytics system exports datamart data to JSON files for consumption by web viewers
and frontend applications. This document provides complete API documentation for the JSON export
schema, including field definitions, data types, examples, and usage guidelines.

**Last Updated**: 2025-12-14  
**Export Script**: `bin/dwh/exportDatamartsToJSON.sh`  
**Schema Validation**: JSON Schema Draft 07 (ajv)  
**Versioning**: Semantic versioning with schema hash detection

---

## Table of Contents

1. [Export System Overview](#export-system-overview)
2. [Directory Structure](#directory-structure)
3. [File Types](#file-types)
4. [User Profile Schema](#user-profile-schema)
5. [Country Profile Schema](#country-profile-schema)
6. [Index Files Schema](#index-files-schema)
7. [Global Statistics Schema](#global-statistics-schema)
8. [Metadata Schema](#metadata-schema)
9. [Field Reference](#field-reference)
10. [Usage Examples](#usage-examples)
11. [Versioning and Compatibility](#versioning-and-compatibility)
12. [Best Practices](#best-practices)

---

## Export System Overview

### Purpose

The JSON export system provides:

- **No database dependency**: Web viewers can be fully static
- **Fast loading**: Small, targeted JSON files per entity
- **CDN-friendly**: All files are static and cacheable
- **Reduced database load**: No queries from web viewers
- **Incremental processing**: Only exports modified entities (90-99% faster for updates)

### Complete Metrics Export

**Important**: The profile files (`users/{user_id}.json`, `countries/{country_id}.json`,
`global_stats.json`) contain **ALL metrics** from the datamart tables. The export script uses
`SELECT row_to_json(t)` which automatically includes every column in the table, ensuring that:

- ✅ **All 78+ user metrics** are exported in user profile files
- ✅ **All 77+ country metrics** are exported in country profile files
- ✅ **All global metrics** are exported in global_stats.json

**Index files** (`indexes/users.json`, `indexes/countries.json`, `global_stats_summary.json`)
contain only a **subset of key metrics** optimized for browsing and quick lookups. For complete
data, always use the profile files.

### Export Process

1. **Incremental Detection**: Only exports entities marked as modified (`json_exported = FALSE`)
2. **Schema Validation**: Each JSON file validated against JSON Schema before export
3. **Atomic Writes**: Files generated in temporary directory, validated, then moved atomically
4. **Fail-safe**: On validation failure, keeps existing files and logs error
5. **Version Tracking**: Tracks export version and schema hash for compatibility

### Execution

```bash
# Basic export
./bin/dwh/exportDatamartsToJSON.sh

# With custom output directory
export JSON_OUTPUT_DIR="/var/www/html/osm-notes/api"
./bin/dwh/exportDatamartsToJSON.sh
```

---

## Directory Structure

```
output/json/
├── metadata.json              # Export metadata (date, counts, version)
├── indexes/
│   ├── users.json            # List of all users with basic stats
│   └── countries.json        # List of all countries with basic stats
├── users/
│   ├── 12345.json           # Individual user profile (by user_id)
│   ├── 67890.json
│   └── ...
├── countries/
│   ├── 123456.json          # Individual country profile (by country_id)
│   ├── 789012.json
│   └── ...
└── global_stats.json         # Global statistics (full)
    global_stats_summary.json # Global statistics (simplified)
```

---

## File Types

### 1. User Profile Files (`users/{user_id}.json`)

**Purpose**: Complete user profile with **ALL 78+ metrics**  
**Schema**: `lib/osm-common/schemas/user-profile.schema.json`  
**Size**: ~5-50 KB per file (depends on activity)  
**Update Frequency**: Only when user data changes  
**Export Method**: Uses `SELECT row_to_json(t) FROM dwh.datamartusers t` which includes **ALL
columns** from the table  
**Note**: Contains every metric available in the datamart, including all historical counts,
resolution metrics, application statistics, content quality, user behavior, temporal patterns,
geographic patterns, and hashtag metrics

### 2. Country Profile Files (`countries/{country_id}.json`)

**Purpose**: Complete country profile with **ALL 77+ metrics**  
**Schema**: `lib/osm-common/schemas/country-profile.schema.json`  
**Size**: ~5-50 KB per file (depends on activity)  
**Update Frequency**: Only when country data changes  
**Export Method**: Uses `SELECT row_to_json(t) FROM dwh.datamartcountries t` which includes **ALL
columns** from the table  
**Note**: Contains every metric available in the datamart, including all historical counts,
resolution metrics, application statistics, content quality, community health, temporal patterns,
user patterns, and hashtag metrics

### 3. User Index (`indexes/users.json`)

**Purpose**: Quick lookup of all users with **key metrics only** (subset for performance)  
**Schema**: `lib/osm-common/schemas/user-index.schema.json`  
**Size**: ~100-500 KB (all users)  
**Update Frequency**: Every export (always regenerated)  
**Export Method**: Uses explicit `SELECT` with 18 key fields (not all metrics)  
**Note**: This is a **subset** of metrics optimized for browsing and search. For complete profile,
load `users/{user_id}.json` instead.

### 4. Country Index (`indexes/countries.json`)

**Purpose**: Quick lookup of all countries with **key metrics only** (subset for performance)  
**Schema**: `lib/osm-common/schemas/country-index.schema.json`  
**Size**: ~50-200 KB (all countries)  
**Update Frequency**: Every export (always regenerated)  
**Export Method**: Uses explicit `SELECT` with 18 key fields (not all metrics)  
**Note**: This is a **subset** of metrics optimized for browsing and search. For complete profile,
load `countries/{country_id}.json` instead.

### 5. Global Statistics (`global_stats.json`)

**Purpose**: Worldwide aggregated statistics with **ALL global metrics**  
**Schema**: `lib/osm-common/schemas/global-stats.schema.json`  
**Size**: ~2-5 KB  
**Update Frequency**: Every export  
**Export Method**: Uses `SELECT row_to_json(t) FROM dwh.datamartglobal t` which includes **ALL
columns** from the table  
**Note**: Contains every metric available in the global datamart

### 6. Global Statistics Summary (`global_stats_summary.json`)

**Purpose**: Simplified global statistics for quick loading (subset for performance)  
**Size**: ~1-2 KB  
**Update Frequency**: Every export  
**Export Method**: Uses explicit `SELECT` with 14 key fields (not all metrics)  
**Note**: This is a **subset** of metrics optimized for quick loading. For complete statistics, load
`global_stats.json` instead.

### 7. Metadata (`metadata.json`)

**Purpose**: Export metadata (date, counts, version, schema hash)  
**Schema**: `lib/osm-common/schemas/metadata.schema.json`  
**Size**: ~200 bytes  
**Update Frequency**: Every export

---

## User Profile Schema

### Overview

Complete user profile containing **78+ metrics** organized into categories:

- **Identity**: user_id, username, dimension_user_id
- **Historical Counts**: Activity counts by time period (whole, year, month, day, by year 2013-2025)
- **Resolution Metrics**: Average/median days to resolution, resolution rates
- **Application Statistics**: Usage patterns, trends, version adoption
- **Content Quality Metrics**: Comment analysis, URLs, mentions
- **User Behavior Metrics**: Response time, collaboration patterns, activity levels
- **Temporal Patterns**: Hour-of-week, day-of-week distributions
- **Geographic Patterns**: Countries where user opened/solved notes
- **Hashtag Metrics**: Hashtag usage and trends
- **First/Last Actions**: Temporal boundaries of activity

### Required Fields

```json
{
  "user_id": 12345,
  "username": "example_user",
  "history_whole_open": 100,
  "history_whole_closed": 50
}
```

### Complete Field List

#### Identity Fields

| Field                 | Type    | Description                           |
| --------------------- | ------- | ------------------------------------- |
| `dimension_user_id`   | integer | Internal dimension ID                 |
| `user_id`             | integer | OSM user ID (required, minimum: 1)    |
| `username`            | string  | OSM username (required, minLength: 1) |
| `id_contributor_type` | integer | Contributor type ID                   |
| `experience_level_id` | integer \| null | Experience level ID (1=newcomer to 7=legend) |
| `experience_level`    | string \| null | Experience level name (newcomer, beginner, intermediate, advanced, expert, master, legend) |

#### Date Fields

| Field                          | Type                  | Description                           |
| ------------------------------ | --------------------- | ------------------------------------- |
| `date_starting_creating_notes` | string (date) \| null | Date when user started creating notes |
| `date_starting_solving_notes`  | string (date) \| null | Date when user started solving notes  |

#### First/Last Note IDs

| Field                       | Type            | Description                    |
| --------------------------- | --------------- | ------------------------------ |
| `first_open_note_id`        | integer         | ID of first note opened        |
| `first_commented_note_id`   | integer \| null | ID of first note commented on  |
| `first_closed_note_id`      | integer \| null | ID of first note closed        |
| `first_reopened_note_id`    | integer \| null | ID of first note reopened      |
| `latest_open_note_id`       | integer         | ID of latest note opened       |
| `lastest_commented_note_id` | integer \| null | ID of latest note commented on |
| `lastest_closed_note_id`    | integer \| null | ID of latest note closed       |
| `lastest_reopened_note_id`  | integer \| null | ID of latest note reopened     |

#### Activity Pattern Fields

| Field                              | Type          | Description                                                                  |
| ---------------------------------- | ------------- | ---------------------------------------------------------------------------- |
| `last_year_activity`               | string        | Binary string representing last year activity (365 bits, pattern: `^[01]+$`) |
| `dates_most_open`                  | array \| null | Array of dates with most notes opened                                        |
| `dates_most_closed`                | array \| null | Array of dates with most notes closed                                        |
| `working_hours_of_week_opening`    | array \| null | Working hours pattern for opening notes                                      |
| `working_hours_of_week_commenting` | array \| null | Working hours pattern for commenting                                         |
| `working_hours_of_week_closing`    | array \| null | Working hours pattern for closing notes                                      |

**Working Hours Pattern Structure**:

```json
{
  "day_of_week": 1, // 0=Sunday, 6=Saturday
  "hour_of_day": 14, // 0-23
  "count": 5 // Number of actions at this time
}
```

#### Historical Count Fields

**Whole History**:

- `history_whole_open` (integer, required, minimum: 0): Total notes opened (all time)
- `history_whole_commented` (integer, minimum: 0): Total notes commented (all time)
- `history_whole_closed` (integer, required, minimum: 0): Total notes closed (all time)
- `history_whole_closed_with_comment` (integer, minimum: 0): Total closed with comment
- `history_whole_reopened` (integer, minimum: 0): Total notes reopened (all time)

**Current Period**:

- `history_year_open`, `history_year_commented`, `history_year_closed`,
  `history_year_closed_with_comment`, `history_year_reopened` (integer, minimum: 0)
- `history_month_open`, `history_month_commented`, `history_month_closed`,
  `history_month_closed_with_comment`, `history_month_reopened` (integer, minimum: 0)
- `history_day_open`, `history_day_commented`, `history_day_closed`,
  `history_day_closed_with_comment`, `history_day_reopened` (integer, minimum: 0)

**By Year (2013-2025)**:

- `history_{YEAR}_open`, `history_{YEAR}_commented`, `history_{YEAR}_closed`,
  `history_{YEAR}_closed_with_comment`, `history_{YEAR}_reopened` (integer, minimum: 0)

#### Resolution Metrics

| Field                                 | Type            | Description                                        |
| ------------------------------------- | --------------- | -------------------------------------------------- |
| `avg_days_to_resolution`              | number \| null  | Average days to resolve notes                      |
| `median_days_to_resolution`           | number \| null  | Median days to resolve notes                       |
| `notes_resolved_count`                | integer \| null | Count of resolved notes                            |
| `notes_still_open_count`              | integer \| null | Count of open notes                                |
| `notes_opened_but_not_closed_by_user` | integer \| null | Notes opened by user but never closed by same user |
| `resolution_rate`                     | number \| null  | Percentage of resolved notes (0-100)               |
| `resolution_by_year`                  | object \| null  | Resolution metrics by year                         |
| `resolution_by_month`                 | object \| null  | Resolution metrics by month                        |

#### Application Statistics

| Field                      | Type            | Description                            |
| -------------------------- | --------------- | -------------------------------------- |
| `applications_used`        | array \| null   | Array of applications used with counts |
| `most_used_application_id` | integer \| null | ID of most used application            |
| `mobile_apps_count`        | integer \| null | Count of mobile apps used              |
| `desktop_apps_count`       | integer \| null | Count of desktop/web apps used         |
| `application_usage_trends` | array \| null   | Application usage trends by year       |
| `version_adoption_rates`   | array \| null   | Version adoption rates by year         |

**Application Usage Trends Structure**:

```json
[
  {
    "year": 2024,
    "applications": [
      {
        "application_id": 1,
        "application_name": "JOSM",
        "count": 150
      }
    ]
  }
]
```

#### Content Quality Metrics

| Field                         | Type            | Description                                  |
| ----------------------------- | --------------- | -------------------------------------------- |
| `avg_comment_length`          | number \| null  | Average comment length in characters         |
| `comments_with_url_count`     | integer \| null | Comments containing URLs                     |
| `comments_with_url_pct`       | number \| null  | Percentage of comments with URLs (0-100)     |
| `comments_with_mention_count` | integer \| null | Comments containing mentions                 |
| `comments_with_mention_pct`   | number \| null  | Percentage of comments with mentions (0-100) |
| `avg_comments_per_note`       | number \| null  | Average comments per note                    |

#### User Behavior Metrics

| Field                    | Type            | Description                                                    |
| ------------------------ | --------------- | -------------------------------------------------------------- |
| `user_response_time`     | number \| null  | Average time in days from note open to first comment by user   |
| `days_since_last_action` | integer \| null | Days since user last performed any action                      |
| `collaboration_patterns` | object \| null  | Collaboration metrics (mentions, replies, collaboration score) |

**Collaboration Patterns Structure**:

```json
{
  "mentions_given": 10,
  "mentions_received": 5,
  "replies_count": 20,
  "collaboration_score": 0.75
}
```

#### Geographic Patterns

| Field                                   | Type          | Description                       |
| --------------------------------------- | ------------- | --------------------------------- |
| `countries_open_notes`                  | array \| null | Countries where user opened notes |
| `countries_solving_notes`               | array \| null | Countries where user solved notes |
| `countries_open_notes_current_month`    | array \| null | Current month countries           |
| `countries_solving_notes_current_month` | array \| null | Current month countries           |
| `countries_open_notes_current_day`      | array \| null | Current day countries             |
| `countries_solving_notes_current_day`   | array \| null | Current day countries             |

**Country Ranking Structure**:

```json
[
  {
    "rank": 1,
    "country": "Colombia",
    "quantity": 50
  }
]
```

#### Hashtag Metrics

| Field                         | Type           | Description                      |
| ----------------------------- | -------------- | -------------------------------- |
| `hashtags`                    | array \| null  | Array of hashtags used           |
| `hashtags_opening`            | array \| null  | Hashtags used in opening notes   |
| `hashtags_resolution`         | array \| null  | Hashtags used in resolving notes |
| `hashtags_comments`           | array \| null  | Hashtags used in comments        |
| `favorite_opening_hashtag`    | string \| null | Most used opening hashtag        |
| `favorite_resolution_hashtag` | string \| null | Most used resolution hashtag     |
| `opening_hashtag_count`       | integer        | Count of opening hashtags        |
| `resolution_hashtag_count`    | integer        | Count of resolution hashtags     |

#### Ranking Fields (By Year)

For each year (2013-2025):

- `ranking_countries_opening_{YEAR}` (array \| null): Ranking of countries by notes opened
- `ranking_countries_closing_{YEAR}` (array \| null): Ranking of countries by notes closed

#### Recent Activity Metrics

| Field                         | Type            | Description                    |
| ----------------------------- | --------------- | ------------------------------ |
| `notes_created_last_30_days`  | integer \| null | Notes created in last 30 days  |
| `notes_resolved_last_30_days` | integer \| null | Notes resolved in last 30 days |
| `active_notes_count`          | integer \| null | Currently active notes         |
| `notes_backlog_size`          | integer \| null | Notes backlog size             |
| `notes_age_distribution`      | object \| null  | Distribution of note ages      |

**Notes Age Distribution Structure**:

```json
{
  "0-7_days": 10,
  "8-30_days": 5,
  "31-90_days": 3,
  "90_plus_days": 2
}
```

### Example User Profile

```json
{
  "dimension_user_id": 123,
  "user_id": 12345,
  "username": "example_user",
  "date_starting_creating_notes": "2020-01-15",
  "date_starting_solving_notes": "2020-02-01",
  "history_whole_open": 100,
  "history_whole_closed": 50,
  "history_whole_commented": 75,
  "avg_days_to_resolution": 5.5,
  "resolution_rate": 50.0,
  "user_response_time": 2.3,
  "days_since_last_action": 5,
  "applications_used": [
    {
      "application_id": 1,
      "application_name": "JOSM",
      "count": 80
    }
  ],
  "collaboration_patterns": {
    "mentions_given": 10,
    "mentions_received": 5,
    "replies_count": 20,
    "collaboration_score": 0.75
  }
}
```

---

## Country Profile Schema

### Overview

Complete country profile containing **77+ metrics** organized into categories:

- **Identity**: country_id, country_name, country_name_es, country_name_en, dimension_country_id
- **Historical Counts**: Activity counts by time period
- **Resolution Metrics**: Average/median days to resolution, resolution rates
- **Application Statistics**: Usage patterns, trends, version adoption
- **Content Quality Metrics**: Comment analysis, URLs, mentions
- **Community Health Metrics**: Health score, backlog, activity trends
- **Temporal Patterns**: Hour-of-week, day-of-week distributions
- **User Patterns**: Users who opened/solved notes in country
- **Hashtag Metrics**: Hashtag usage and trends

### Required Fields

```json
{
  "country_id": 123456,
  "country_name": "Colombia",
  "history_whole_open": 1000,
  "history_whole_closed": 800
}
```

### Key Differences from User Profile

**Country-Specific Fields**:

- `notes_health_score` (number \| null): Overall notes health score (0-100)
- `new_vs_resolved_ratio` (number \| null): Ratio of new notes created vs resolved notes (last 30
  days)
- `users_open_notes` (array \| null): Users who opened notes in country
- `users_solving_notes` (array \| null): Users who solved notes in country
- `ranking_users_opening_{YEAR}` (array \| null): Ranking of users by notes opened (by year)
- `ranking_users_closing_{YEAR}` (array \| null): Ranking of users by notes closed (by year)

**Not in Country Profile**:

- `user_response_time`
- `days_since_last_action`
- `collaboration_patterns`
- `notes_opened_but_not_closed_by_user`

### Example Country Profile

```json
{
  "dimension_country_id": 45,
  "country_id": 123456,
  "country_name": "Colombia",
  "country_name_es": "Colombia",
  "country_name_en": "Colombia",
  "history_whole_open": 1000,
  "history_whole_closed": 800,
  "avg_days_to_resolution": 7.2,
  "resolution_rate": 80.0,
  "notes_health_score": 75.5,
  "new_vs_resolved_ratio": 1.2,
  "applications_used": [
    {
      "application_id": 1,
      "application_name": "JOSM",
      "count": 600
    }
  ],
  "application_usage_trends": [
    {
      "year": 2024,
      "applications": [
        {
          "application_id": 1,
          "application_name": "JOSM",
          "count": 150
        }
      ]
    }
  ]
}
```

---

## Index Files Schema

### User Index (`indexes/users.json`)

**Purpose**: Quick lookup of all users with key metrics  
**Structure**: Array of user objects

**Fields Included**:

- `user_id` (integer, required)
- `username` (string, required)
- `id_contributor_type` (integer)
- `date_starting_creating_notes` (string \| null)
- `history_whole_open` (integer, required)
- `history_whole_closed` (integer, required)
- `history_whole_commented` (integer)
- `history_year_open` (integer)
- `history_year_closed` (integer)
- `history_year_commented` (integer)
- `avg_days_to_resolution` (number \| null)
- `resolution_rate` (number \| null)
- `notes_resolved_count` (integer \| null)
- `notes_still_open_count` (integer \| null)
- `user_response_time` (number \| null)
- `days_since_last_action` (integer \| null)
- `notes_created_last_30_days` (integer \| null)
- `notes_resolved_last_30_days` (integer \| null)

**Example**:

```json
[
  {
    "user_id": 12345,
    "username": "example_user",
    "history_whole_open": 100,
    "history_whole_closed": 50,
    "avg_days_to_resolution": 5.5,
    "resolution_rate": 50.0
  }
]
```

### Country Index (`indexes/countries.json`)

**Purpose**: Quick lookup of all countries with key metrics  
**Structure**: Array of country objects

**Fields Included**:

- `country_id` (integer, required)
- `country_name` (string, required)
- `country_name_es` (string)
- `country_name_en` (string)
- `date_starting_creating_notes` (string \| null)
- `history_whole_open` (integer, required)
- `history_whole_closed` (integer, required)
- `history_whole_commented` (integer)
- `history_year_open` (integer)
- `history_year_closed` (integer)
- `history_year_commented` (integer)
- `avg_days_to_resolution` (number \| null)
- `resolution_rate` (number \| null)
- `notes_resolved_count` (integer \| null)
- `notes_still_open_count` (integer \| null)
- `notes_health_score` (number \| null)
- `new_vs_resolved_ratio` (number \| null)
- `notes_created_last_30_days` (integer \| null)
- `notes_resolved_last_30_days` (integer \| null)

**Example**:

```json
[
  {
    "country_id": 123456,
    "country_name": "Colombia",
    "country_name_en": "Colombia",
    "history_whole_open": 1000,
    "history_whole_closed": 800,
    "avg_days_to_resolution": 7.2,
    "resolution_rate": 80.0,
    "notes_health_score": 75.5
  }
]
```

---

## Global Statistics Schema

### Overview

Worldwide aggregated statistics for the entire OSM Notes system.

### Fields

| Field                          | Type                  | Description                              |
| ------------------------------ | --------------------- | ---------------------------------------- |
| `dimension_global_id`          | integer               | Always 1, single record identifier       |
| `date_starting_creating_notes` | string (date) \| null | Date of the oldest opened note globally  |
| `date_starting_solving_notes`  | string (date) \| null | Date of the oldest closed note globally  |
| `first_open_note_id`           | integer \| null       | First opened note ID globally            |
| `first_closed_note_id`         | integer \| null       | First closed note ID globally            |
| `latest_open_note_id`          | integer \| null       | Most recent opened note ID               |
| `latest_closed_note_id`        | integer \| null       | Most recent closed note ID               |
| `history_whole_open`           | integer \| null       | Total opened notes in history            |
| `history_whole_commented`      | integer \| null       | Total commented notes in history         |
| `history_whole_closed`         | integer \| null       | Total closed notes in history            |
| `history_year_open`            | integer \| null       | Notes opened in current year             |
| `history_year_closed`          | integer \| null       | Notes closed in current year             |
| `currently_open_count`         | integer \| null       | Number of notes currently open           |
| `currently_closed_count`       | integer \| null       | Number of notes currently closed         |
| `notes_created_last_30_days`   | integer \| null       | Notes created in last 30 days            |
| `notes_resolved_last_30_days`  | integer \| null       | Notes resolved in last 30 days           |
| `notes_backlog_size`           | integer \| null       | Number of open notes older than 7 days   |
| `avg_days_to_resolution`       | number \| null        | Average days to resolve notes (all time) |
| `median_days_to_resolution`    | number \| null        | Median days to resolve notes (all time)  |
| `resolution_rate`              | number \| null        | Percentage of notes resolved (0-100)     |
| `active_users_count`           | integer \| null       | Users active in last 30 days             |
| `notes_age_distribution`       | object \| null        | Distribution of note ages                |
| `applications_used`            | array \| null         | Most used applications                   |
| `avg_comment_length`           | number \| null        | Average length of comments               |
| `comments_with_url_pct`        | number \| null        | Percentage of comments with URLs         |

### Example

```json
{
  "dimension_global_id": 1,
  "history_whole_open": 1000000,
  "history_whole_closed": 800000,
  "currently_open_count": 200000,
  "avg_days_to_resolution": 5.5,
  "resolution_rate": 80.0,
  "notes_created_last_30_days": 5000,
  "notes_resolved_last_30_days": 4500,
  "active_users_count": 10000
}
```

---

## Metadata Schema

### Overview

Export metadata containing information about the export itself.

### Fields

| Field              | Type               | Description                                                |
| ------------------ | ------------------ | ---------------------------------------------------------- |
| `export_date`      | string (date-time) | ISO 8601 timestamp when export was generated (required)    |
| `export_timestamp` | integer            | Unix timestamp of export                                   |
| `total_users`      | integer            | Total number of users in export (required, minimum: 0)     |
| `total_countries`  | integer            | Total number of countries in export (required, minimum: 0) |
| `version`          | string             | Schema version identifier (semantic versioning)            |
| `schema_version`   | string             | Schema version                                             |
| `api_compat_min`   | string             | Minimum API version for compatibility                      |
| `data_schema_hash` | string             | SHA256 hash of datamart schema (for change detection)      |

### Example

```json
{
  "export_date": "2025-12-14T10:30:00Z",
  "export_timestamp": 1702552200,
  "total_users": 50000,
  "total_countries": 200,
  "version": "1.2.3",
  "schema_version": "1.0.0",
  "api_compat_min": "1.0.0",
  "data_schema_hash": "abc123..."
}
```

---

## Field Reference

### Data Types

- **integer**: Whole numbers (minimum: 0 for counts)
- **number**: Decimal numbers (DECIMAL in database)
- **string**: Text values
- **string (date)**: ISO 8601 date format (YYYY-MM-DD)
- **string (date-time)**: ISO 8601 datetime format (YYYY-MM-DDTHH:MM:SSZ)
- **boolean**: true/false
- **array**: JSON array
- **object**: JSON object
- **null**: Nullable fields (may be null)

### Common Patterns

**JSON Arrays**:

- Arrays may be `null` if no data
- Arrays are empty `[]` if no items
- Arrays contain objects with consistent structure

**JSON Objects**:

- Objects may be `null` if no data
- Objects use camelCase for keys
- Nested objects follow same patterns

**Date Formats**:

- Dates: `YYYY-MM-DD` (e.g., "2025-12-14")
- Date-times: `YYYY-MM-DDTHH:MM:SSZ` (e.g., "2025-12-14T10:30:00Z")

**Numeric Ranges**:

- Percentages: 0-100 (e.g., resolution_rate)
- Counts: 0 or positive integers
- Decimals: May have 2 decimal places (e.g., 5.50)

---

## Usage Examples

### Frontend Integration

#### 1. Load User Profile

```javascript
// Fetch user profile
async function loadUserProfile(userId) {
  const response = await fetch(`/api/users/${userId}.json`);
  const profile = await response.json();

  console.log(`User: ${profile.username}`);
  console.log(`Notes opened: ${profile.history_whole_open}`);
  console.log(`Resolution rate: ${profile.resolution_rate}%`);

  return profile;
}
```

#### 2. Load Country Profile

```javascript
// Fetch country profile
async function loadCountryProfile(countryId) {
  const response = await fetch(`/api/countries/${countryId}.json`);
  const profile = await response.json();

  console.log(`Country: ${profile.country_name}`);
  console.log(`Health score: ${profile.notes_health_score}`);
  console.log(`Backlog: ${profile.notes_backlog_size}`);

  return profile;
}
```

#### 3. Browse Users Index

```javascript
// Load users index for browsing
async function browseUsers() {
  const response = await fetch("/api/indexes/users.json");
  const users = await response.json();

  // Sort by activity
  const sorted = users.sort((a, b) => b.history_whole_open - a.history_whole_open);

  // Display top 10
  sorted.slice(0, 10).forEach((user) => {
    console.log(`${user.username}: ${user.history_whole_open} notes`);
  });

  return sorted;
}
```

#### 4. Check Export Metadata

```javascript
// Check export version and compatibility
async function checkExportVersion() {
  const response = await fetch("/api/metadata.json");
  const metadata = await response.json();

  console.log(`Export date: ${metadata.export_date}`);
  console.log(`Total users: ${metadata.total_users}`);
  console.log(`Schema version: ${metadata.schema_version}`);

  // Check compatibility
  if (metadata.api_compat_min > "1.0.0") {
    console.warn("API version may be incompatible");
  }

  return metadata;
}
```

#### 5. Display Global Statistics

```javascript
// Load global statistics
async function loadGlobalStats() {
  const response = await fetch("/api/global_stats_summary.json");
  const stats = await response.json();

  console.log(`Total notes: ${stats.history_whole_open}`);
  console.log(`Currently open: ${stats.currently_open_count}`);
  console.log(`Resolution rate: ${stats.resolution_rate}%`);
  console.log(`Active users: ${stats.active_users_count}`);

  return stats;
}
```

### Error Handling

```javascript
async function safeLoadProfile(type, id) {
  try {
    const response = await fetch(`/api/${type}/${id}.json`);

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    const profile = await response.json();
    return profile;
  } catch (error) {
    console.error(`Failed to load ${type} ${id}:`, error);
    return null;
  }
}
```

### Caching Strategy

```javascript
// Cache profiles for 1 hour
const CACHE_DURATION = 60 * 60 * 1000; // 1 hour

async function loadUserProfileCached(userId) {
  const cacheKey = `user_${userId}`;
  const cached = sessionStorage.getItem(cacheKey);

  if (cached) {
    const { data, timestamp } = JSON.parse(cached);
    if (Date.now() - timestamp < CACHE_DURATION) {
      return data;
    }
  }

  const profile = await loadUserProfile(userId);
  sessionStorage.setItem(
    cacheKey,
    JSON.stringify({
      data: profile,
      timestamp: Date.now(),
    }),
  );

  return profile;
}
```

---

## Versioning and Compatibility

### Version Tracking

The export system uses semantic versioning (MAJOR.MINOR.PATCH):

- **MAJOR**: Breaking changes (schema incompatible)
- **MINOR**: New fields added (backward compatible)
- **PATCH**: Bug fixes, no schema changes

### Schema Hash

Each export includes a `data_schema_hash` in metadata.json. This SHA256 hash is calculated from the
datamart table schema (column names, types, positions). If the hash changes, the schema has changed.

### Compatibility Checking

```javascript
// Check if export is compatible
function isCompatible(metadata, minVersion) {
  const exportVersion = metadata.version.split(".").map(Number);
  const minVersionParts = minVersion.split(".").map(Number);

  // Major version must match
  if (exportVersion[0] !== minVersionParts[0]) {
    return false;
  }

  // Minor version must be >= minimum
  if (exportVersion[1] < minVersionParts[1]) {
    return false;
  }

  return true;
}
```

### Handling Schema Changes

1. **Check metadata.json** for version and schema hash
2. **Validate against known schema** using JSON Schema validator
3. **Handle missing fields gracefully** (use defaults or skip)
4. **Log warnings** for unexpected fields (schemas allow `additionalProperties: true`)

---

## Best Practices

### For Frontend Developers

1. **Always check metadata.json first** to verify export version and compatibility
2. **Use index files for browsing** - don't load all profiles at once
3. **Implement caching** - profiles don't change frequently
4. **Handle null values** - many fields are nullable
5. **Validate JSON** - use JSON Schema validators in development
6. **Error handling** - files may not exist for all IDs
7. **Lazy loading** - load profiles only when needed
8. **CDN caching** - configure appropriate cache headers

### Performance Optimization

1. **Use index files** for initial page loads
2. **Load profiles on demand** (when user clicks)
3. **Cache aggressively** - data changes infrequently
4. **Compress responses** - enable gzip/brotli
5. **Use HTTP/2** - for parallel requests
6. **Preload critical files** - metadata.json, global_stats.json

### Data Validation

1. **Validate against JSON Schema** in development
2. **Check required fields** before using
3. **Handle type coercion** (numbers may be strings in some contexts)
4. **Validate ranges** (percentages 0-100, counts >= 0)

### Error Scenarios

1. **File not found (404)**: User/country may not exist
2. **Invalid JSON (500)**: Export may be corrupted
3. **Schema mismatch**: Version incompatibility
4. **Network errors**: Implement retry logic

---

## Related Documentation

- **[Metric Definitions](Metric_Definitions.md)**: Complete business definitions for all metrics
- **[Dashboard Analysis](Dashboard_Analysis.md)**: Implementation status and recommendations
- **[Testing Guide](Testing_Guide.md)**: How to test JSON exports
- **[Export Script README](../bin/dwh/Export_JSON_README.md)**: Export script documentation

---

## Schema Files Location

### For Frontend/Consumer Applications

**Primary location (recommended):** Schemas are automatically copied to the data repository:

```
OSM-Notes-Data/schemas/
├── user-profile.schema.json
├── country-profile.schema.json
├── user-index.schema.json
├── country-index.schema.json
├── metadata.schema.json
└── global-stats.schema.json
```

**Available via GitHub Pages:**

- `https://osm-notes.github.io/OSM-Notes-Data/schemas/`

This is the recommended location for frontend applications as schemas are versioned together with
the data.

### For Development/Validation

**Source location:** Schemas are maintained in:

```
lib/osm-common/schemas/
├── user-profile.schema.json
├── country-profile.schema.json
├── user-index.schema.json
├── country-index.schema.json
├── metadata.schema.json
└── global-stats.schema.json
```

Schemas are automatically synced to the data repository during each export via
`exportAndPushJSONToGitHub.sh`.

**For complete documentation on schema location and usage, see:**

- **[JSON Schema Location](JSON_Schema_Location.md)**: Complete guide on where to find schemas and
  how to use them

---

## Support

For questions or issues:

1. Check this documentation
2. Review JSON Schema files
3. Check export script logs
4. Create an issue with:
   - Export version (from metadata.json)
   - Schema hash (from metadata.json)
   - Specific field or error

---

**Last Updated**: 2025-12-14  
**Maintained By**: Development Team
