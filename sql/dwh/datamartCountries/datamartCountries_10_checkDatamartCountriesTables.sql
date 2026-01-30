-- Verifies if the base tables are created in the database.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-12-08

  DO /* Notes-datamartCountries-checkTables */
  $$
  DECLARE
   qty INT;
  BEGIN
   SELECT /* Notes-datamartCountries */ COUNT(TABLE_NAME)
    INTO qty
   FROM INFORMATION_SCHEMA.TABLES
   WHERE TABLE_TYPE = 'BASE TABLE'
   AND TABLE_SCHEMA = 'dwh'
   AND LOWER(TABLE_NAME) = 'datamartcountries'
   ;
   IF (qty <> 1) THEN
    RAISE EXCEPTION 'Base tables are missing: datamartCountries.';
   END IF;
  END;
  $$;
