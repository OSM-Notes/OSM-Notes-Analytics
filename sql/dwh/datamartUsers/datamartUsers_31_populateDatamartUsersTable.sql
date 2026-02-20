-- Populates the user datamart with aggregated statistics.
-- Processes a limited batch of users per run (SQL default 500; shell uses MAX_USERS_PER_CYCLE, default 5000).
--
-- DM-005: Implements intelligent prioritization:
-- - Users with recent activity (last 7/30/90 days) processed first
-- - High-activity users (>100 actions) prioritized
-- - Atomic transactions ensure data consistency
-- - Error handling with EXCEPTION prevents batch failures
--
-- See bin/dwh/datamartUsers/PARALLEL_PROCESSING.md for detailed documentation.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-27

-- DM-004: Badges are assigned only for the users updated in this run (see loop below),
-- to avoid costly full scan every cycle when most users have no changes.
-- Note: When datamartUsers.sh runs, it uses the shell path (parallel workers) with
-- MAX_USERS_PER_CYCLE (default 5000) and assigns badges there per user; this SQL
-- block applies when this script is run directly (e.g. single-thread) with LIMIT below.

DO /* Notes-datamartUsers-processRecentUsers */
$$
DECLARE
 r RECORD;
 max_date DATE;
BEGIN
 SELECT /* Notes-datamartUsers */ date
  INTO max_date
 FROM dwh.max_date_users_processed;
 IF (max_date < CURRENT_DATE) THEN
  RAISE NOTICE 'Moving activities.';
  -- Updates all users, moving a day.
  UPDATE dwh.datamartUsers
   SET last_year_activity = dwh.move_day(last_year_activity);
  UPDATE dwh.max_date_users_processed
   SET date = CURRENT_DATE;
 END IF;

 -- Inserts the part of the date to reduce calling the function Extract.
 DELETE FROM dwh.properties WHERE key IN ('year', 'month', 'day');
 INSERT INTO dwh.properties VALUES ('year', DATE_PART('year', CURRENT_DATE));
 INSERT INTO dwh.properties VALUES ('month', DATE_PART('month', CURRENT_DATE));
 INSERT INTO dwh.properties VALUES ('day', DATE_PART('day', CURRENT_DATE));

 FOR r IN
  -- Process the datamart only for modified users.
  -- DM-005: Intelligent prioritization by relevance using refined criteria:
  -- 1. Users with recent activity (last 7 days) - CRITICAL priority
  -- 2. Users with activity in last 30 days - HIGH priority
  -- 3. Users with activity in last 90 days - MEDIUM priority
  -- 4. Users with high historical activity (>100 actions) - MEDIUM priority
  -- 5. Users with moderate activity (10-100 actions) - LOW priority
  -- 6. Inactive users (<10 actions or >2 years inactive) - LOWEST priority
  -- This ensures most relevant users are processed first, reducing
  -- time to have fresh data for active users from days to minutes.
  SELECT /* Notes-datamartUsers */
   f.action_dimension_id_user AS dimension_user_id
  FROM dwh.facts f
   JOIN dwh.dimension_users u
   ON (f.action_dimension_id_user = u.dimension_user_id)
  WHERE u.modified = TRUE
  GROUP BY f.action_dimension_id_user
  ORDER BY
   -- Priority 1: Very recent activity (last 7 days) = highest
   CASE WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '7 days' THEN 1
        WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '30 days' THEN 2
        WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '90 days' THEN 3
        ELSE 4 END,
   -- Priority 2: High activity users (>100 actions) get priority
   CASE WHEN COUNT(*) > 100 THEN 1
        WHEN COUNT(*) > 10 THEN 2
        ELSE 3 END,
   -- Priority 3: Most active users historically
   COUNT(*) DESC,
   -- Priority 4: Most recent activity first
   MAX(f.action_at) DESC NULLS LAST
  LIMIT 500
 LOOP
  RAISE NOTICE 'Processing user %.', r.dimension_user_id;
  -- Timing is handled inside update_datamart_user procedure
  -- Use transaction to ensure atomicity (DM-005)
  BEGIN
   CALL dwh.update_datamart_user(r.dimension_user_id);
   UPDATE dwh.dimension_users
    SET modified = FALSE
    WHERE dimension_user_id = r.dimension_user_id;
   -- DM-004: Assign badges only for this user (just updated); avoids full scan every run
   PERFORM dwh.assign_badges_to_user(r.dimension_user_id);
  EXCEPTION WHEN OTHERS THEN
   RAISE WARNING 'Failed to process user %: %', r.dimension_user_id, SQLERRM;
   -- Continue with next user instead of failing entire batch
  END;

 END LOOP;
END
$$;
