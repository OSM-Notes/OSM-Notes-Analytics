-- Verifies if the base tables are created in the database.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-11-29

ALTER TABLE dwh.datamartUsers
 ADD COLUMN history_${YEAR}_open INTEGER,
 ADD COLUMN history_${YEAR}_commented INTEGER,
 ADD COLUMN history_${YEAR}_closed INTEGER,
 ADD COLUMN history_${YEAR}_closed_with_comment INTEGER,
 ADD COLUMN history_${YEAR}_reopened INTEGER,
 ADD COLUMN ranking_countries_opening_${YEAR} JSON,
 ADD COLUMN ranking_countries_closing_${YEAR} JSON
;
COMMENT ON COLUMN dwh.datamartUsers.history_${YEAR}_open IS
  'Qty of notes opened in ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.history_${YEAR}_commented IS
  'Qty of notes commented in ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.history_${YEAR}_closed IS
  'Qty of notes closed in ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.history_${YEAR}_closed_with_comment IS
  'Qty of notes closed with comment in ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.history_${YEAR}_reopened IS
  'Qty of notes reopened in ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.ranking_countries_opening_${YEAR} IS
  'Ranking of countries where creating notes on year ${YEAR}';
COMMENT ON COLUMN dwh.datamartUsers.ranking_countries_closing_${YEAR} IS
  'Ranking of countries where closing notes on year ${YEAR}';
