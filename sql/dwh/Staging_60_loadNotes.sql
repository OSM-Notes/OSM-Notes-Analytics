-- Loads new notes incrementally into the data warehouse.
-- Processes note actions that occurred since the last ETL run.
-- Calls the staging procedure to insert new facts.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-20

-- Read-only queries to ingestion tables use READ ONLY transaction for better concurrency
BEGIN READ ONLY;
SELECT /* Notes-staging */ COUNT(1) AS facts, 0 AS comments
FROM dwh.facts
UNION
SELECT /* Notes-staging */ 0 AS facts, count(1) AS comments
FROM public.note_comments;
COMMIT;

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Inserting facts' AS Task;

-- This procedure does writes, so it cannot be READ ONLY
CALL staging.process_notes_actions_into_dwh();

SELECT /* Notes-staging */ clock_timestamp() AS Processing,
 'Facts inserted' AS Task;

-- Read-only queries to ingestion tables use READ ONLY transaction for better concurrency
BEGIN READ ONLY;
SELECT /* Notes-staging */ COUNT(1) AS facts, 0 AS comments
FROM dwh.facts
UNION
SELECT /* Notes-staging */ 0 AS facts, count(1) AS comments
FROM public.note_comments;
COMMIT;
