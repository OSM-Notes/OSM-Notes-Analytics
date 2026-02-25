-- Populates dimension tables with initial data.
-- Inserts regions, continents, applications, timezones, seasons, and other
-- dimension data that can be populated before processing facts.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-08-08

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Inserting Regions' AS Task;

INSERT INTO dwh.dimension_regions (region_name_es, region_name_en) VALUES
 ('Indefinida', 'Undefined'),
 ('Norteamérica', 'North America'),
 ('Centroamérica', 'Central America'),
 ('Antillas', 'Antilles'),
 ('Sudamérica', 'South America'),
 ('Europa Occidental', 'Western Europe'),
 ('Europa Oriental', 'Eastern Europe'),
 ('Cáucaso', 'Caucasus'),
 ('Siberia', 'Siberia'),
 ('Asia Central', 'Central Asia'),
 ('Asia Oriental', 'East Asia'),
 ('África del Norte', 'North Africa'),
 ('África subsahariana', 'Sub-Saharan Africa'),
 ('Medio Oriente', 'Middle East'),
 ('Indostán', 'Indian subcontinent'),
 ('Indochina', 'Mainland Southeast Asia'),
 ('Insulindia', 'Malay Archipelago'),
 ('Islas del Pacífico (Melanesia, Micronesia y Polinesia)',
   'Pacific Islands (Melanesia, Micronesia and Polynesia)'),
 ('Australia', 'Australia'),
 ('Antártida', 'Antarctica');

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Inserting Continents' AS Task;

INSERT INTO dwh.dimension_continents (continent_name_es, continent_name_en) VALUES
  ('África', 'Africa'),
  ('América', 'Americas'),
  ('Antártida', 'Antarctica'),
  ('Asia', 'Asia'),
  ('Europa', 'Europe'),
  ('Oceanía', 'Oceania')
ON CONFLICT DO NOTHING;

-- Optional mapping Regions -> Continents (coarse, can be refined later)
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Americas'
) WHERE region_name_en IN ('North America', 'Central America', 'Antilles', 'South America');
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Europe'
) WHERE region_name_en IN ('Western Europe', 'Eastern Europe', 'Caucasus', 'Siberia');
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Asia'
) WHERE region_name_en IN ('Central Asia', 'East Asia', 'Middle East', 'Indian subcontinent', 'Mainland Southeast Asia', 'Malay Archipelago');
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Africa'
) WHERE region_name_en IN ('North Africa', 'Sub-Saharan Africa');
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Oceania'
) WHERE region_name_en IN ('Pacific Islands (Melanesia, Micronesia and Polynesia)', 'Australia');
UPDATE dwh.dimension_regions SET continent_id = (
  SELECT dimension_continent_id FROM dwh.dimension_continents WHERE continent_name_en = 'Antarctica'
) WHERE region_name_en IN ('Antarctica');

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Inserting dimension countries' AS Task;

-- Insert an id for notes without a country. It does not insert again if it
-- already exist on the table (-1 NOT IN).
-- Note: This does not depend on the countries table, it's just a check to ensure
-- the row doesn't already exist in dimension_countries.
INSERT INTO dwh.dimension_countries
 (country_id, country_name, country_name_es, country_name_en)
 SELECT /* Notes-ETL */ -1, 'Unkown - International waters',
  'Desconocido - Aguas internacionales', 'Unkown - International waters'
 WHERE -1 NOT IN (
  SELECT /* Notes-ETL */ country_id
  FROM dwh.dimension_countries
 )
;

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Adding hour values' AS Task;

DO /* Notes-ETL-addWeekHours */
$$
DECLARE
 m_day SMALLINT;
 m_hour SMALLINT;
 m_date VARCHAR(32);
BEGIN
 m_day := 1;
 WHILE (m_day <= 7) LOOP
  m_hour := 1;
  WHILE (m_hour <= 24) LOOP
   IF (m_day < 10) THEN
    IF (m_hour < 10) THEN
     m_date := '2013-07-0' || m_day || ' 0' || m_hour || ':00:00.00000+00';
    ELSE
     m_date := '2013-07-0' || m_day || ' ' || m_hour || ':00:00.00000+00';
    END IF;
   ELSE
    IF (m_hour < 10) THEN
     m_date := '2013-07-' || m_day || ' 0' || m_hour || ':00:00.00000+00';
    ELSE
     m_date := '2013-07-' || m_day || ' ' || m_hour || ':00:00.00000+00';
    END IF;
   END IF;
   PERFORM dwh.get_hour_of_week_id(m_date::TIMESTAMP);
   m_hour := m_hour + 1;
  END LOOP;
  m_day := m_day + 1;
 END LOOP;
END
$$;

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Adding application names' AS Task;

INSERT INTO dwh.dimension_applications (application_name, pattern) VALUES
('Unknown', NULL),
('StreetComplete', '%via StreetComplete%'),
('Maps.me', '%#mapsme'),
('EveryDoor', '%#EveryDoor'),
('OsmAnd', '%#OsmAnd'),
('LocusMap', '%#LocusMap'),
('OrganicMaps', '%#organicmaps'),
('OSM Report', '%#osmreport')
;

INSERT INTO dwh.dimension_applications (application_name, pattern, platform) VALUES
('OrganicMaps', '%#organicmaps android', 'android'),
('OrganicMaps', '%#organicmaps ios', 'ios'),
('OnOSM.org', 'onosm.org %', 'web'),
('MapComplete', '%#MapComplete #notes', 'web'),
('Mapy.cz', '(%#Mapy.cz%|%#Mapycz%|#Mapy.cz%|%#mapycz%)', 'web'),
('msftopenmaps', '%(#msftopenmaps|%#MSFTOpenMaps)%', 'web'),
('OnOSM.OSMiranorg', 'onosm.osmiran.org %', 'web')
;

-- Applications commonly indicated in note comment text (e.g. "Opened with iD 2.19", "JOSM").
-- Only apps not already in the INSERTs above; idempotent for existing installations.
INSERT INTO dwh.dimension_applications (application_name, pattern)
SELECT v.app_name, v.pat
FROM (VALUES
  ('iD', '% iD %'),
  ('iD', '%with iD%'),
  ('JOSM', '%JOSM%'),
  ('Vespucci', '%Vespucci%'),
  ('Go Map!!', '%Go Map%'),
  ('Potlatch', '%Potlatch%'),
  ('Mapillary', '%Mapillary%')
) AS v(app_name, pat)
WHERE NOT EXISTS (
  SELECT 1 FROM dwh.dimension_applications a
  WHERE a.application_name = v.app_name AND (a.pattern IS NOT DISTINCT FROM v.pat)
);

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Dimensions populated' AS Task;

-- Timezones
INSERT INTO dwh.dimension_timezones (tz_name, utc_offset_minutes) VALUES
 ('UTC', 0),
 ('UTC-12', -720), ('UTC-11', -660), ('UTC-10', -600), ('UTC-9', -540),
 ('UTC-8', -480), ('UTC-7', -420), ('UTC-6', -360), ('UTC-5', -300),
 ('UTC-4', -240), ('UTC-3', -180), ('UTC-2', -120), ('UTC-1', -60),
 ('UTC+1', 60), ('UTC+2', 120), ('UTC+3', 180), ('UTC+4', 240),
 ('UTC+5', 300), ('UTC+6', 360), ('UTC+7', 420), ('UTC+8', 480),
 ('UTC+9', 540), ('UTC+10', 600), ('UTC+11', 660), ('UTC+12', 720),
 ('UTC+13', 780), ('UTC+14', 840)
ON CONFLICT DO NOTHING;

-- Common IANA-like zones with standard offsets (DST not modeled here)
INSERT INTO dwh.dimension_timezones (tz_name, utc_offset_minutes) VALUES
 ('Europe/London', 0),
 ('Europe/Berlin', 60),
 ('Europe/Madrid', 60),
 ('Europe/Paris', 60),
 ('America/New_York', -300),
 ('America/Chicago', -360),
 ('America/Denver', -420),
 ('America/Los_Angeles', -480),
 ('America/Bogota', -300),
 ('America/Lima', -300),
 ('America/Mexico_City', -360),
 ('America/Sao_Paulo', -180),
 ('America/Buenos_Aires', -180),
 ('Africa/Cairo', 120),
 ('Africa/Johannesburg', 120),
 ('Asia/Tokyo', 540),
 ('Asia/Shanghai', 480),
 ('Asia/Kolkata', 330),
 ('Australia/Sydney', 600),
 ('Pacific/Auckland', 720)
ON CONFLICT DO NOTHING;

-- Seasons
INSERT INTO dwh.dimension_seasons (dimension_season_id, season_name_en, season_name_es) VALUES
 (0, 'No season', 'Sin estación'),
 (1, 'Spring', 'Primavera'),
 (2, 'Summer', 'Verano'),
 (3, 'Autumn', 'Otoño'),
 (4, 'Winter', 'Invierno')
ON CONFLICT DO NOTHING;

-- Anonymous user member (SCD2 current)
INSERT INTO dwh.dimension_users (user_id, username, modified, valid_from, is_current)
VALUES (-1, 'Anonymous', FALSE, NOW(), TRUE)
ON CONFLICT DO NOTHING;
