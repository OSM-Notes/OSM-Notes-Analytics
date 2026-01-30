-- Verifies if the base tables are created in the database.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-20

  DO /* Notes-datamartGlobal-checkTables */
  $$
  DECLARE
   qty INT;
  BEGIN
   SELECT /* Notes-datamartGlobal */ COUNT(TABLE_NAME)
    INTO qty
   FROM INFORMATION_SCHEMA.TABLES
   WHERE TABLE_TYPE = 'BASE TABLE'
   AND TABLE_SCHEMA = 'dwh'
   AND LOWER(TABLE_NAME) = 'datamartglobal'
   ;
   IF (qty <> 1) THEN
    RAISE EXCEPTION 'Base tables are missing: datamartGlobal.';
   END IF;
  END;
  $$;


