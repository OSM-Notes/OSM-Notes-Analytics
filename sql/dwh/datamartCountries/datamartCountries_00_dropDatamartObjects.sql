-- Drop datamart for countries tables.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-11-11

DROP PROCEDURE IF EXISTS dwh.update_datamart_country;

DROP PROCEDURE IF EXISTS dwh.update_datamart_country_activity_year;

DROP PROCEDURE IF EXISTS dwh.insert_datamart_country;

DROP TABLE IF EXISTS dwh.max_date_countries_processed;

DROP TABLE IF EXISTS dwh.datamartCountries;
