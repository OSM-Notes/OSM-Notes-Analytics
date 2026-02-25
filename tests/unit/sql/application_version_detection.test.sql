-- Unit tests: application and version detection from real-world note comment text.
-- Validates staging.get_application() and dwh.get_application_version_id() with
-- realistic samples (like "Opened with iD 2.19.3", "JOSM", "Vespucci 0.9.0").
--
-- Prerequisites: dwh.dimension_applications, dwh.dimension_application_versions,
-- staging.get_application (Staging_31), dwh.get_application_version_id (ETL_23).
-- Inserts minimal application patterns if missing so tests can run after ETL_25 or mock ETL.

BEGIN;

-- Ensure application patterns used by tests exist (idempotent)
INSERT INTO dwh.dimension_applications (application_name, pattern)
SELECT v.app_name, v.pat
FROM (VALUES
  ('iD', '% iD %'),
  ('iD', '%with iD%'),
  ('JOSM', '%JOSM%'),
  ('Vespucci', '%Vespucci%'),
  ('Go Map!!', '%Go Map%'),
  ('Potlatch', '%Potlatch%'),
  ('StreetComplete', '%via StreetComplete%'),
  ('OrganicMaps', '%#organicmaps%'),
  ('OsmAnd', '%#OsmAnd%'),
  ('EveryDoor', '%#EveryDoor%'),
  ('Mapillary', '%Mapillary%')
) AS v(app_name, pat)
WHERE NOT EXISTS (
  SELECT 1 FROM dwh.dimension_applications a
  WHERE a.application_name = v.app_name AND (a.pattern IS NOT DISTINCT FROM v.pat)
);

-- Test 1: get_application identifies app from real-world opening comment text
DO $$
DECLARE
  r RECORD;
  app_id INTEGER;
  app_name TEXT;
  samples TEXT[] := ARRAY[
    'Opened with iD 2.19.3',
    'Opened with iD 2.20.1',
    'Created with JOSM',
    'Vespucci 0.9.0',
    'via StreetComplete 2.0',
    'Opened with Go Map!! 1.0',
    'Potlatch 2',
    '#organicmaps',
    '#EveryDoor 0.1.2',
    '#OsmAnd 4.2.1',
    'Mapillary app'
  ];
  expected_names TEXT[] := ARRAY['iD','iD','JOSM','Vespucci','StreetComplete','Go Map!!','Potlatch','OrganicMaps','EveryDoor','OsmAnd','Mapillary'];
  i INT;
BEGIN
  IF array_length(samples, 1) != array_length(expected_names, 1) THEN
    RAISE EXCEPTION 'Test data array length mismatch';
  END IF;
  FOR i IN 1..array_length(samples, 1) LOOP
    SELECT staging.get_application(samples[i]) INTO app_id;
    IF app_id IS NULL THEN
      RAISE EXCEPTION 'get_application returned NULL for comment: %', samples[i];
    END IF;
    SELECT a.application_name INTO app_name
    FROM dwh.dimension_applications a WHERE a.dimension_application_id = app_id;
    IF app_name IS NULL OR app_name != expected_names[i] THEN
      RAISE EXCEPTION 'For comment "%" expected app %, got % (id %)', samples[i], expected_names[i], app_name, app_id;
    END IF;
    RAISE NOTICE 'PASS: "%" -> %', samples[i], app_name;
  END LOOP;
  RAISE NOTICE 'Test 1 passed: all real-world samples identified correct application';
END $$;

-- Test 2: comment with no app returns NULL
DO $$
DECLARE
  app_id INTEGER;
BEGIN
  SELECT staging.get_application('Fixed the road') INTO app_id;
  IF app_id IS NOT NULL THEN
    RAISE EXCEPTION 'get_application should return NULL for comment with no app, got %', app_id;
  END IF;
  RAISE NOTICE 'Test 2 passed: comment with no app returns NULL';
END $$;

-- Test 3: version extraction and get_application_version_id (creates row if missing)
DO $$
DECLARE
  app_id INTEGER;
  ver_id INTEGER;
  ver_text TEXT;
BEGIN
  -- Resolve iD application id (any row with application_name = 'iD')
  SELECT dimension_application_id INTO app_id
  FROM dwh.dimension_applications WHERE application_name = 'iD' AND pattern IS NOT NULL LIMIT 1;
  IF app_id IS NULL THEN
    RAISE EXCEPTION 'Test 3: iD application not found in dimension_applications';
  END IF;
  -- Simulate version from comment: regexp_match returns array, take first element
  SELECT (regexp_match('Opened with iD 2.19.3', E'(\\d+\\.\\d+(?:\\.\\d+)?)'))[1] INTO ver_text;
  IF ver_text IS NULL THEN
    RAISE EXCEPTION 'Test 3: regexp_match did not extract version';
  END IF;
  SELECT dwh.get_application_version_id(app_id, ver_text) INTO ver_id;
  IF ver_id IS NULL THEN
    RAISE EXCEPTION 'Test 3: get_application_version_id returned NULL for iD %', ver_text;
  END IF;
  RAISE NOTICE 'Test 3 passed: version % -> dimension_application_version_id %', ver_text, ver_id;
END $$;

-- Test 4: LIKE-style patterns (ensure SIMILAR TO behaves: % matches any string)
DO $$
DECLARE
  app_id INTEGER;
BEGIN
  SELECT staging.get_application('Some prefix with iD 2.19 and suffix') INTO app_id;
  IF app_id IS NULL THEN
    RAISE EXCEPTION 'get_application should match " iD " inside long text';
  END IF;
  RAISE NOTICE 'Test 4 passed: " iD " matched inside long text';
END $$;

COMMIT;
