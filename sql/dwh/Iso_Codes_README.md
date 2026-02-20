# ISO Country Codes Reference

This file explains how to maintain the ISO country codes reference table used in the data warehouse.

## Overview

The `dwh.iso_country_codes` table provides a mapping between OSM relation IDs and ISO 3166-1 country
codes (alpha-2 and alpha-3). This table is used to enrich the `dimension_countries` table with
standardized country codes.

## Table Structure

```sql
CREATE TABLE dwh.iso_country_codes (
  osm_country_id INTEGER PRIMARY KEY,  -- OSM relation ID
  iso_alpha2 VARCHAR(2) NOT NULL,      -- ISO 3166-1 alpha-2 (e.g., 'CO')
  iso_alpha3 VARCHAR(3) NOT NULL,      -- ISO 3166-1 alpha-3 (e.g., 'COL')
  country_name_en VARCHAR(100)         -- English name for reference
);
```

## How It Works

1. **Initial Load**: Script `ETL_24_populateISOCodes.sql` creates and populates the table
2. **Country Insert**: When new countries are added to `dimension_countries`, ISO codes are looked
   up via LEFT JOIN
3. **Country Update**: When running ETL updates, new ISO codes are added if available
4. **NULL Values**: Countries not in the reference table have NULL ISO codes (this is OK)

## Adding New Countries

### Option 1: Edit the SQL File (Recommended)

Edit `sql/dwh/ETL_24_populateISOCodes.sql` and add new rows to the INSERT statement:

```sql
INSERT INTO dwh.iso_country_codes (osm_country_id, iso_alpha2, iso_alpha3, country_name_en)
VALUES
 -- Existing countries...
 (192796, 'ZA', 'ZAF', 'South Africa'),

 -- Add your new country here:
 (123456, 'XX', 'XXX', 'New Country Name')
;
```

Then run:

```bash
psql -d notes_dwh -f sql/dwh/ETL_24_populateISOCodes.sql
```

The script uses `ON CONFLICT DO UPDATE`, so you can run it multiple times safely.

### Option 2: Direct SQL Update

For quick additions without modifying source files:

```sql
INSERT INTO dwh.iso_country_codes (osm_country_id, iso_alpha2, iso_alpha3, country_name_en)
VALUES (123456, 'XX', 'XXX', 'New Country Name')
ON CONFLICT (osm_country_id) DO UPDATE
 SET iso_alpha2 = EXCLUDED.iso_alpha2,
     iso_alpha3 = EXCLUDED.iso_alpha3;
```

Then update dimension_countries:

```sql
UPDATE dwh.dimension_countries d
SET iso_alpha2 = iso.iso_alpha2,
    iso_alpha3 = iso.iso_alpha3
FROM dwh.iso_country_codes iso
WHERE d.country_id = iso.osm_country_id
  AND d.iso_alpha2 IS NULL;
```

## Finding OSM Country IDs

To find the OSM relation ID for a country:

1. Go to <https://www.openstreetmap.org>
2. Search for the country name
3. Look for the admin_level=2 relation
4. The relation ID is in the URL: `https://www.openstreetmap.org/relation/120027` → `120027`

Example:

- Colombia: <https://www.openstreetmap.org/relation/120027> → `120027`
- Germany: <https://www.openstreetmap.org/relation/51477> → `51477`

Or query your database:

```sql
SELECT country_id, country_name, country_name_en
FROM countries
WHERE country_name_en LIKE '%Germany%';
```

## ISO Code References

- **ISO 3166-1 alpha-2**: Two-letter codes (e.g., US, DE, JP)
  - <https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2>
- **ISO 3166-1 alpha-3**: Three-letter codes (e.g., USA, DEU, JPN)
  - <https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3>

## Current Coverage

The initial data includes:

- ✅ **North America**: US, CA, MX, Central American countries
- ✅ **South America**: BR, AR, CO, CL, PE, VE, and others
- ✅ **Europe**: Major European countries (DE, FR, GB, ES, IT, etc.)
- ✅ **Asia**: JP, CN, IN, KR, TH, and others
- ✅ **Oceania**: AU, NZ
- ✅ **Africa**: ZA, NG, EG, KE, and others

**Total**: ~60 countries with highest OSM activity

## Maintenance

### Adding Missing Countries

Monitor countries without ISO codes:

```sql
SELECT d.country_id, d.country_name, d.country_name_en,
       COUNT(f.fact_id) as note_actions
FROM dwh.dimension_countries d
LEFT JOIN dwh.facts f ON d.dimension_country_id = f.dimension_id_country
WHERE d.iso_alpha2 IS NULL
GROUP BY d.country_id, d.country_name, d.country_name_en
ORDER BY note_actions DESC
LIMIT 20;
```

Countries with high activity should be added to the reference table.

### Verifying ISO Codes

Check for invalid or duplicate codes:

```sql
-- Check for duplicate ISO codes (should be unique per country)
SELECT iso_alpha2, COUNT(*)
FROM dwh.iso_country_codes
GROUP BY iso_alpha2
HAVING COUNT(*) > 1;

-- Check for invalid format
SELECT *
FROM dwh.iso_country_codes
WHERE LENGTH(iso_alpha2) != 2 OR LENGTH(iso_alpha3) != 3;
```

### Updating Existing Codes

If an ISO code is incorrect:

```sql
UPDATE dwh.iso_country_codes
SET iso_alpha2 = 'XX',
    iso_alpha3 = 'XXX'
WHERE osm_country_id = 123456;

-- Then update dimension_countries
UPDATE dwh.dimension_countries
SET iso_alpha2 = 'XX',
    iso_alpha3 = 'XXX'
WHERE country_id = 123456;
```

## Design Rationale

**Why not fetch from external API?**

- ✅ Self-contained: No external dependencies
- ✅ Fast: No network calls
- ✅ Reliable: No rate limiting or API changes
- ✅ Versionable: Changes tracked in Git
- ✅ Offline: Works without internet

**Why allow NULL values?**

- ✅ Flexible: New countries work immediately
- ✅ Practical: Not all countries have activity
- ✅ Progressive: Can add codes as needed
- ✅ No blocking: ETL doesn't fail for missing codes

**Why manual maintenance?**

- ✅ Quality control: Verify codes before adding
- ✅ Intentional: Only add countries that matter
- ✅ Simple: No complex automation needed

## Future Enhancements

Possible improvements:

1. **Script to import from CSV**:
   - Download full ISO 3166-1 list
   - Match by country name
   - Semi-automated population

2. **Validation script**:
   - Check against official ISO list
   - Detect invalid codes
   - Suggest corrections

3. **Coverage report**:
   - Show % of countries with ISO codes
   - Show % of notes with ISO codes
   - Identify high-priority additions

## Support

For questions about ISO codes:

1. Check this README
2. Query the reference table: `SELECT * FROM dwh.iso_country_codes;`
3. Check official ISO 3166-1 lists
4. Create an issue with country details
