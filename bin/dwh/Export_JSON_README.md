# JSON Export System for Web Viewer

This system exports the datamarts to precalculated JSON files, allowing the web viewer to consume
data without direct database access.

## Overview

The export system generates individual JSON files for each user and country, plus index files for
quick lookups. This approach provides:

- **No database dependency for web viewer**: The web interface can be fully static
- **Fast loading**: Small, targeted JSON files per entity
- **Easy CDN deployment**: All files are static and can be cached
- **Reduced database load**: No queries from the web viewer
- **Incremental processing**: Only exports modified entities (90-99% faster for updates)

## Directory Structure

```
output/json/
├── metadata.json              # Export metadata (date, counts)
├── indexes/
│   ├── users.json            # List of all users with basic stats
│   └── countries.json        # List of all countries with basic stats
├── users/
│   ├── 12345.json           # Individual user data (by user_id)
│   ├── 67890.json
│   └── ...
└── countries/
    ├── 123456.json          # Individual country data (by country_id)
    ├── 789012.json
    └── ...
```

## Usage

### Basic Export

```bash
cd bin/dwh
./exportDatamartsToJSON.sh
```

### Export and Push to GitHub Pages

The script `exportAndPushJSONToGitHub.sh` exports and pushes countries intelligently:

```bash
./bin/dwh/exportAndPushJSONToGitHub.sh
```

**Behavior:**

1. Identifies countries that need export (missing, outdated, or marked as not exported)
2. Removes countries from GitHub that no longer exist in local database
3. Exports each country individually
4. Commits and pushes each country immediately after export
5. Continues with next country even if one fails
6. Generates README.md with alphabetical list of countries
7. Updates country index at the end

**Features:**

- **Resilient**: If one country fails, others continue processing
- **Progress tracking**: See which countries are being processed
- **Automatic detection**: Identifies missing or outdated countries (default: 30 days)
- **Cleanup**: Removes countries from GitHub that don't exist locally
- **Documentation**: Auto-generates README.md with country list
- **Small commits**: Easier to track changes in GitHub
- **Less risk**: If process fails, only one country is lost

**Environment variables:**

- `MAX_AGE_DAYS`: Maximum age in days for country files before regeneration (default: 30)
  - Since cron runs monthly, default of 30 days ensures all countries are refreshed
- `COUNTRIES_PER_BATCH`: Number of countries to process before taking a break (default: 10)
- `DBNAME_DWH`: Database name for DWH (default: from etc/properties.sh)

**Examples:**

```bash
# Default: Export countries older than 30 days (monthly cron)
./bin/dwh/exportAndPushJSONToGitHub.sh

# Export countries older than 7 days (for testing)
MAX_AGE_DAYS=7 ./bin/dwh/exportAndPushJSONToGitHub.sh

# Process 5 countries at a time
COUNTRIES_PER_BATCH=5 ./bin/dwh/exportAndPushJSONToGitHub.sh
```

**Requirements:**

- `OSM-Notes-Data` repository cloned to `~/github/OSM-Notes-Data` or `~/OSM-Notes-Data`
- Git credentials configured for push access

**Generated Files:**

- `data/countries/README.md`: Alphabetical list of all countries with links to their JSON files

### Custom Output Directory

Set the `JSON_OUTPUT_DIR` environment variable:

```bash
export JSON_OUTPUT_DIR="/var/www/html/osm-notes/api"
./exportDatamartsToJSON.sh
```

Or edit `etc/properties.sh` to change the default.

### Scheduled Export

Add to crontab for automatic updates:

```bash
# Export every hour
0 * * * * cd /path/to/OSM-Notes-Analytics/bin/dwh && ./exportDatamartsToJSON.sh >> /tmp/json-export.log 2>&1

# Export every 15 minutes
*/15 * * * * cd /path/to/OSM-Notes-Analytics/bin/dwh && ./exportDatamartsToJSON.sh >> /tmp/json-export.log 2>&1
```

## API Endpoints for Web Viewer

The web viewer can access the data through these file paths:

### Get User Data

```
GET /users/{user_id}.json
```

Example: `/users/12345.json`

Returns complete user profile with all statistics.

### Get Country Data

```
GET /countries/{country_id}.json
```

Example: `/countries/123456.json`

Returns complete country profile with all statistics.

### Get User Index

```
GET /indexes/users.json
```

Returns array of all users with basic information:

- user_id
- username
- history_whole_open
- history_whole_closed
- history_year_open
- history_year_closed

### Get Country Index

```
GET /indexes/countries.json
```

Returns array of all countries with basic information:

- country_id
- country_name (all languages)
- history_whole_open
- history_whole_closed
- history_year_open
- history_year_closed

### Get Metadata

```
GET /metadata.json
```

Returns export metadata:

- export_date
- total_users
- total_countries
- version

## Data Schema

### User JSON Structure

```json
{
  "dimension_user_id": 123,
  "user_id": 12345,
  "username": "example_user",
  "date_starting_creating_notes": "2015-03-20",
  "date_starting_solving_notes": "2015-04-15",
  "first_open_note_id": 100,
  "id_contributor_type": 2,
  "experience_level_id": 4,
  "experience_level": "advanced",
  "last_year_activity": "...",
  "hashtags": [
    {"rank": 1, "hashtag": "#mapathon", "quantity": 45},
    {"rank": 2, "hashtag": "#survey", "quantity": 23}
  ],
  "countries_open_notes": [
    {"rank": 1, "country": "Colombia", "quantity": 150},
    {"rank": 2, "country": "Ecuador", "quantity": 45}
  ],
  "working_hours_of_week_opening": [...],
  "history_whole_open": 542,
  "history_whole_closed": 234,
  "history_whole_closed_with_comment": 189,
  "history_year_open": 45,
  "history_year_closed": 23
}
```

### Country JSON Structure

```json
{
  "dimension_country_id": 123,
  "country_id": 123456,
  "country_name": "Colombia",
  "country_name_es": "Colombia",
  "country_name_en": "Colombia",
  "date_starting_creating_notes": "2013-06-15",
  "hashtags": [
    {"rank": 1, "hashtag": "#mapathon", "quantity": 450},
    {"rank": 2, "hashtag": "#survey", "quantity": 230}
  ],
  "users_open_notes": [
    {"rank": 1, "username": "user1", "quantity": 1500},
    {"rank": 2, "username": "user2", "quantity": 450}
  ],
  "working_hours_of_week_opening": [...],
  "history_whole_open": 5420,
  "history_whole_closed": 2340,
  "history_whole_closed_with_comment": 1890,
  "history_year_open": 450,
  "history_year_closed": 230
}
```

## Web Server Configuration

### Nginx Example

```nginx
server {
    listen 80;
    server_name osm-notes.example.com;

    root /var/www/html/osm-notes;

    location /api/ {
        alias /var/www/html/osm-notes/api/;
        add_header Cache-Control "public, max-age=3600";
        add_header Access-Control-Allow-Origin "*";
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

### Apache Example

```apache
<VirtualHost *:80>
    ServerName osm-notes.example.com
    DocumentRoot /var/www/html/osm-notes

    <Directory /var/www/html/osm-notes/api>
        Header set Cache-Control "public, max-age=3600"
        Header set Access-Control-Allow-Origin "*"
    </Directory>
</VirtualHost>
```

## Performance Considerations

- **Export time**: Depends on datamart size. Typical times:
  - 1000 users: ~2 minutes
  - 10000 users: ~15 minutes
  - 100000 users: ~2 hours

- **Storage**: Each JSON file is typically 2-10 KB
  - 10000 users ≈ 50 MB
  - 200 countries ≈ 2 MB

- **Incremental updates**: Currently exports all data. For large datasets, consider implementing
  incremental exports based on `modified` flag in dimension tables.

## Troubleshooting

### Export fails with "Properties file not found"

Ensure you're running from the correct directory or set `PROPERTIES_LOCATION`:

```bash
export PROPERTIES_LOCATION="/path/to/OSM-Notes-Analytics/etc"
./exportDatamartsToJSON.sh
```

### Permission denied on output directory

```bash
mkdir -p ./output/json
chmod 755 ./output/json
```

### Empty JSON files

Check that datamarts are populated:

```sql
SELECT COUNT(*) FROM dwh.datamartUsers;
SELECT COUNT(*) FROM dwh.datamartCountries;
```

If empty, run the datamart population scripts first.

## Integration with ETL

Add JSON export to your ETL pipeline:

```bash
# In ETL.sh or as a separate cron job
./bin/dwh/datamartUsers/datamartUsers.sh
./bin/dwh/datamartCountries/datamartCountries.sh
./bin/dwh/exportDatamartsToJSON.sh
```

## Automation

### Automated GitHub Pages Deployment

The `exportAndPushJSONToGitHub.sh` script automates the entire workflow:

```bash
# Manual execution
./bin/dwh/exportAndPushJSONToGitHub.sh

# Or add to cron for automatic updates
0 * * * * cd /path/to/OSM-Notes-Analytics && ./bin/dwh/exportAndPushJSONToGitHub.sh >> /tmp/github-push.log 2>&1
```

This ensures your GitHub Pages data repository is always up-to-date with the latest Analytics data.

## Future Enhancements

- Incremental export (only modified entities)
- Compression (gzip JSON files)
- Versioning (keep multiple exports with timestamps)
- Delta files for real-time updates
- Search index generation
- GraphQL API layer
