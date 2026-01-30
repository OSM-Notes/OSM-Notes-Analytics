-- Populates datamart for users.
-- This SQL is executed in batches by the bash script to allow periodic commits.
-- Each execution processes a batch of users (typically 50) in a single transaction.
-- Uses OFFSET to process different subsets of users in each batch.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-01-03

DO /* Notes-datamartUsers-processOldUsers */
$$
DECLARE
 r RECORD;
 m_count INTEGER;
BEGIN
 m_count := 0;
 RAISE NOTICE 'Processing batch of old users (range: ${LOWER_VALUE}-${HIGH_VALUE}, offset: ${BATCH_OFFSET}, limit: ${BATCH_SIZE}).';

 -- Process users in current batch using OFFSET and LIMIT
 FOR r IN
  SELECT /* Notes-datamartUsers */
   f.action_dimension_id_user AS dimension_user_id
  FROM dwh.facts f
   JOIN dwh.dimension_users u
   ON (f.action_dimension_id_user = u.dimension_user_id)
  WHERE ${LOWER_VALUE} <= u.user_id
   AND u.user_id < ${HIGH_VALUE}
  GROUP BY f.action_dimension_id_user
  HAVING COUNT(1) <= 20
  ORDER BY COUNT(1) DESC
  OFFSET ${BATCH_OFFSET}
  LIMIT ${BATCH_SIZE}
 LOOP
  BEGIN
   CALL dwh.update_datamart_user(r.dimension_user_id);

   UPDATE dwh.dimension_users
    SET modified = FALSE
    WHERE dimension_user_id = r.dimension_user_id;

   m_count := m_count + 1;
  EXCEPTION WHEN OTHERS THEN
   RAISE WARNING 'Failed to process user %: %', r.dimension_user_id, SQLERRM;
   -- Continue with next user
  END;
 END LOOP;

 RAISE NOTICE 'Batch completed. Processed % users.', m_count;
END
$$;
