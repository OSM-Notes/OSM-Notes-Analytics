-- Test-only helper: satisfy ETL prerequisite on the database used as DBNAME_INGESTION in CI/local
-- runs (often the same DB as TEST_DBNAME). Production ingestion sets this via OSM-Notes-Ingestion
-- after processPlanetNotes.sh --base; do not use on production notes DB.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-20

CREATE TABLE IF NOT EXISTS public.properties (
 key VARCHAR(32) PRIMARY KEY,
 value VARCHAR(32),
 updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO public.properties (key, value) VALUES ('base_load_complete', 'true')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value,
 updated_at = CURRENT_TIMESTAMP;
