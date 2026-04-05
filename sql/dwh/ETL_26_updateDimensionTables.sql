-- Updates dimension tables with new data from base tables.
-- Handles new users, username changes (SCD2), and new countries.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-05

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Updates dimension users (SCD2)' AS Task;

-- Inserts new users as current rows
INSERT INTO dwh.dimension_users
 (user_id, username, valid_from, is_current)
 SELECT /* Notes-ETL */ c.user_id, c.username, NOW(), TRUE
 FROM users c
 WHERE NOT EXISTS (
  SELECT /* Notes-ETL */ 1
  FROM dwh.dimension_users u
  WHERE u.user_id = c.user_id
  )
;

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Closing previous current rows when username changes' AS Task;

-- Close current rows where username changed (SCD2)
UPDATE dwh.dimension_users d
SET valid_to = NOW(), is_current = FALSE
FROM users c
WHERE d.user_id = c.user_id
  AND d.is_current = TRUE
  AND c.username IS DISTINCT FROM d.username
;

-- Insert new current row with new username
INSERT INTO dwh.dimension_users (user_id, username, valid_from, is_current)
SELECT c.user_id, c.username, NOW(), TRUE
FROM users c
JOIN dwh.dimension_users d ON d.user_id = c.user_id
WHERE d.is_current = FALSE
  AND NOT EXISTS (
    SELECT 1 FROM dwh.dimension_users d2
    WHERE d2.user_id = c.user_id AND d2.username = c.username AND d2.is_current = TRUE
  )
GROUP BY c.user_id, c.username
;

-- REMOVED: Redundant UPDATE that was causing performance issues
-- The SCD2 process above (lines 24-44) already handles username changes correctly:
-- 1. Closes old rows when username changes
-- 2. Inserts new current rows with updated username
-- The previous UPDATE was processing ALL rows (including historical ones), breaking SCD2 integrity
-- and causing severe performance degradation with large datasets.
-- Removed: 2025-10-21

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Updating dimension countries' AS Task;

-- Populates the countries dimension with new countries.
-- ISO codes are populated from reference table if available, otherwise NULL.
-- Mark new countries as modified so datamarts are updated (ETL-007)
INSERT INTO dwh.dimension_countries
 (country_id, country_name, country_name_es, country_name_en,
  iso_alpha2, iso_alpha3, modified)
 SELECT /* Notes-ETL */ c.country_id, c.country_name, c.country_name_es,
  c.country_name_en, iso.iso_alpha2, iso.iso_alpha3, TRUE
 FROM countries c
  LEFT JOIN dwh.iso_country_codes iso ON c.country_id = iso.osm_country_id
 WHERE NOT EXISTS (
  SELECT /* Notes-ETL */ 1
  FROM dwh.dimension_countries dc
  WHERE dc.country_id = c.country_id
 )
;
SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Updating countries with region (takes a while)' AS Task;
-- Updates countries with regions.
UPDATE /* Notes-ETL */ dwh.dimension_countries
 SET region_id = dwh.get_country_region(country_id);

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Showing modified countries' AS Task;
-- Shows countries renamed.
COPY (
 SELECT /* Notes-ETL */ DISTINCT d.country_name AS OldCountryName,
  c.country_name AS NewCountryName
 FROM countries c
  JOIN dwh.dimension_countries d
  ON d.country_id = c.country_id
 WHERE c.country_name <> d.country_name
  OR c.country_name_es <> d.country_name_es
  OR c.country_name_en <> d.country_name_en
)
TO '/tmp/countries_changed.csv' WITH DELIMITER ',' CSV HEADER -- noqa: PRS
;

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Updating modified country names' AS Task;

-- Updates the dimension when country names change or ISO codes are added.
-- Mark countries as modified so datamarts are updated (ETL-007)
UPDATE /* Notes-ETL */ dwh.dimension_countries d
 SET country_name = c.country_name,
 country_name_es = c.country_name_es,
 country_name_en = c.country_name_en,
 iso_alpha2 = COALESCE(iso.iso_alpha2, d.iso_alpha2),
 iso_alpha3 = COALESCE(iso.iso_alpha3, d.iso_alpha3),
 modified = TRUE
 FROM countries AS c
  LEFT JOIN dwh.iso_country_codes iso ON c.country_id = iso.osm_country_id
 WHERE d.country_id = c.country_id
  AND (c.country_name IS DISTINCT FROM d.country_name
   OR c.country_name_es IS DISTINCT FROM d.country_name_es
   OR c.country_name_en IS DISTINCT FROM d.country_name_en
   OR (iso.iso_alpha2 IS NOT NULL AND d.iso_alpha2 IS NULL)
   OR (iso.iso_alpha3 IS NOT NULL AND d.iso_alpha3 IS NULL))
;

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Dimensions updated' AS Task;
