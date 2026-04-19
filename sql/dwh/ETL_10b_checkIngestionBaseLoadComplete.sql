-- Verifies OSM-Notes-Ingestion completed a full Planet --base load.
-- Ingestion records this in public.properties (key base_load_complete, value true)
-- via processPlanetNotes.sh __record_base_load_complete after analyze/vacuum.
-- Reference: OSM-Notes-Ingestion bin/process/processPlanetNotes.sh
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-19

DO /* Notes-ETL-checkBaseLoadComplete */
$$
DECLARE
 qty INT;
 prop_value TEXT;
BEGIN
 SELECT /* Notes-ETL */ COUNT(*)
  INTO qty
 FROM information_schema.tables
 WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
  AND table_name = 'properties';

 IF (qty <> 1) THEN
  RAISE EXCEPTION
   'public.properties is missing; cannot verify base_load_complete. Expected OSM-Notes-Ingestion DDL: https://github.com/OSM-Notes/OSM-Notes-Ingestion';
 END IF;

 SELECT /* Notes-ETL */ value
  INTO prop_value
 FROM public.properties
 WHERE key = 'base_load_complete';

 IF prop_value IS NULL THEN
  RAISE EXCEPTION
   'Ingestion base load not marked complete: public.properties has no key base_load_complete. Wait for processPlanetNotes.sh --base to finish successfully, or insert base_load_complete=true when API-only data is ready. See OSM-Notes-Ingestion processPlanetNotes __record_base_load_complete.';
 END IF;

 IF lower(trim(prop_value)) IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION
   'Ingestion base_load_complete is % (expected true). Planet --base may have failed or property was changed.',
   prop_value;
 END IF;

 RAISE NOTICE 'Ingestion base_load_complete verified (public.properties).';
END
$$;
