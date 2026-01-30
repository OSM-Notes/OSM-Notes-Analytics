-- Populates the global datamart with aggregated statistics.
-- Computes metrics for all notes globally.
--
-- OPTIMIZED VERSION (2026-01-15):
-- - Consolidated COUNT queries using CTEs
-- - Optimized JOINs with dimension_days (single JOIN for multiple metrics)
-- - Replaced NOT IN with NOT EXISTS for better performance
-- - Optimized MIN/MAX queries for first/latest note IDs
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-15 (Optimized)

DO /* Notes-datamartGlobal-processGlobal */
$$
DECLARE
  m_max_date DATE;
  m_last_year_activity CHAR(371) := '0';
  m_top_countries JSON;
  m_applications_used JSON;
  r RECORD;
BEGIN
  -- Get max processed date
  SELECT COALESCE(date, '1970-01-01'::DATE)
   INTO m_max_date
  FROM dwh.max_date_global_processed;

  IF (m_max_date < CURRENT_DATE) THEN
   RAISE NOTICE 'Moving activities.';

   -- Update last year activity
   SELECT last_year_activity
    INTO m_last_year_activity
   FROM dwh.datamartGlobal
   WHERE dimension_global_id = 1;

   UPDATE dwh.datamartGlobal
    SET last_year_activity = dwh.move_day(COALESCE(last_year_activity, '0'))
   WHERE dimension_global_id = 1;

   UPDATE dwh.max_date_global_processed
    SET date = CURRENT_DATE;
  END IF;

  RAISE NOTICE 'Processing global statistics.';

  -- OPTIMIZATION 1: Consolidated action counts using CTE
  -- This replaces multiple individual COUNT(*) queries with a single scan
  WITH action_counts AS (
    SELECT /* Notes-datamartGlobal */
      action_comment,
      COUNT(*) as total_count
    FROM dwh.facts
    WHERE action_comment IN ('opened', 'commented', 'closed', 'reopened')
    GROUP BY action_comment
  ),
  -- OPTIMIZATION 2: Consolidated year metrics with single JOIN to dimension_days
  year_metrics AS (
    SELECT /* Notes-datamartGlobal */
      f.action_comment,
      COUNT(*) as total_count
    FROM dwh.facts f
    JOIN dwh.dimension_days dd
    ON (f.action_dimension_id_date = dd.dimension_day_id)
    WHERE EXTRACT(YEAR FROM dd.date_id) = EXTRACT(YEAR FROM CURRENT_DATE)
      AND f.action_comment IN ('opened', 'commented', 'closed', 'reopened')
    GROUP BY f.action_comment
  ),
  -- OPTIMIZATION 3: Consolidated resolution metrics
  resolution_metrics AS (
    SELECT /* Notes-datamartGlobal */
      AVG(days_to_resolution)::DECIMAL(10,2) as avg_all_time,
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_resolution)::DECIMAL(10,2) as median_all_time
    FROM dwh.facts
    WHERE days_to_resolution IS NOT NULL
      AND days_to_resolution > 0
  ),
  -- OPTIMIZATION 4: Consolidated resolution metrics for current year
  resolution_metrics_year AS (
    SELECT /* Notes-datamartGlobal */
      AVG(f.days_to_resolution)::DECIMAL(10,2) as avg_year,
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.days_to_resolution)::DECIMAL(10,2) as median_year
    FROM dwh.facts f
    JOIN dwh.dimension_days dd
    ON (f.opened_dimension_id_date = dd.dimension_day_id)
    WHERE f.days_to_resolution IS NOT NULL
      AND f.days_to_resolution > 0
      AND EXTRACT(YEAR FROM dd.date_id) = EXTRACT(YEAR FROM CURRENT_DATE)
  ),
  -- OPTIMIZATION 5: Consolidated first/latest note IDs
  first_latest_notes AS (
    SELECT /* Notes-datamartGlobal */
      action_comment,
      MIN(fact_id) as first_fact_id,
      MAX(fact_id) as last_fact_id
    FROM dwh.facts
    WHERE action_comment IN ('opened', 'closed', 'reopened')
    GROUP BY action_comment
  ),
  -- Consolidated closed with comment counts
  closed_with_comment_whole AS (
    SELECT /* Notes-datamartGlobal */ COUNT(*) as total
    FROM dwh.facts f
    WHERE f.action_comment = 'closed'
      AND EXISTS (
        SELECT 1
        FROM dwh.facts f2
        WHERE f2.id_note = f.id_note
          AND f2.action_comment = 'commented'
          AND f2.sequence_action < f.sequence_action
      )
  ),
  closed_with_comment_year AS (
    SELECT /* Notes-datamartGlobal */ COUNT(*) as total
    FROM dwh.facts f
    JOIN dwh.dimension_days dd
    ON (f.action_dimension_id_date = dd.dimension_day_id)
    WHERE f.action_comment = 'closed'
      AND EXTRACT(YEAR FROM dd.date_id) = EXTRACT(YEAR FROM CURRENT_DATE)
      AND EXISTS (
        SELECT 1
        FROM dwh.facts f2
        WHERE f2.id_note = f.id_note
          AND f2.action_comment = 'commented'
          AND f2.sequence_action < f.sequence_action
      )
  ),
  -- Consolidated resolution rate calculation
  resolution_rate_calc AS (
    SELECT /* Notes-datamartGlobal */
      CASE
        WHEN COUNT(DISTINCT CASE WHEN action_comment = 'opened' THEN id_note END) > 0
        THEN (COUNT(DISTINCT CASE WHEN action_comment = 'closed' THEN id_note END)::DECIMAL
              / COUNT(DISTINCT CASE WHEN action_comment = 'opened' THEN id_note END)::DECIMAL
              * 100)
        ELSE 0
      END as rate
    FROM dwh.facts
  ),
  -- Consolidated comment metrics
  comment_metrics AS (
    SELECT /* Notes-datamartGlobal */
      AVG(comment_length)::DECIMAL(10,2) as avg_length,
      CASE
        WHEN COUNT(*) > 0
        THEN (COUNT(CASE WHEN has_url THEN 1 END)::DECIMAL / COUNT(*)::DECIMAL * 100)
        ELSE 0
      END as url_pct,
      CASE
        WHEN COUNT(*) > 0
        THEN (COUNT(CASE WHEN has_mention THEN 1 END)::DECIMAL / COUNT(*)::DECIMAL * 100)
        ELSE 0
      END as mention_pct
    FROM dwh.facts
    WHERE comment_length IS NOT NULL OR has_url IS NOT NULL OR has_mention IS NOT NULL
  ),
  -- Consolidated 30-day metrics
  metrics_30_days AS (
    SELECT /* Notes-datamartGlobal */
      COUNT(DISTINCT CASE WHEN f.action_comment = 'opened' THEN f.id_note END) as notes_created,
      COUNT(DISTINCT CASE WHEN f.action_comment = 'closed' THEN f.id_note END) as notes_resolved,
      COUNT(DISTINCT f.action_dimension_id_user) as active_users
    FROM dwh.facts f
    JOIN dwh.dimension_days dd
    ON (f.action_dimension_id_date = dd.dimension_day_id)
    WHERE dd.date_id >= CURRENT_DATE - INTERVAL '30 days'
  )

  -- Update global statistics using consolidated CTEs
  UPDATE dwh.datamartGlobal
  SET
   -- Static values (date_starting_creating_notes)
   date_starting_creating_notes = (
    SELECT /* Notes-datamartGlobal */ date_id
    FROM dwh.dimension_days
    WHERE dimension_day_id = (
     SELECT /* Notes-datamartGlobal */ MIN(opened_dimension_id_date)
     FROM dwh.facts
    )
   ),

   -- date_starting_solving_notes
   date_starting_solving_notes = (
    SELECT /* Notes-datamartGlobal */ date_id
    FROM dwh.dimension_days
    WHERE dimension_day_id = (
     SELECT /* Notes-datamartGlobal */ MIN(closed_dimension_id_date)
     FROM dwh.facts
     WHERE closed_dimension_id_date IS NOT NULL
    )
   ),

   -- first_open_note_id (optimized)
   first_open_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT first_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'opened'
    )
   ),

   -- first_closed_note_id (optimized)
   first_closed_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT first_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'closed'
    )
   ),

   -- first_reopened_note_id (optimized)
   first_reopened_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT first_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'reopened'
    )
   ),

   -- latest_open_note_id (optimized)
   latest_open_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT last_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'opened'
    )
   ),

   -- latest_closed_note_id (optimized)
   latest_closed_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT last_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'closed'
    )
   ),

   -- latest_reopened_note_id (optimized)
   latest_reopened_note_id = (
    SELECT /* Notes-datamartGlobal */ id_note
    FROM dwh.facts
    WHERE fact_id = (
     SELECT last_fact_id
     FROM first_latest_notes
     WHERE action_comment = 'reopened'
    )
   ),

   -- Historical totals (from consolidated CTE)
   history_whole_open = (SELECT total_count FROM action_counts WHERE action_comment = 'opened'),
   history_whole_commented = (SELECT total_count FROM action_counts WHERE action_comment = 'commented'),
   history_whole_closed = (SELECT total_count FROM action_counts WHERE action_comment = 'closed'),
   history_whole_closed_with_comment = (SELECT total FROM closed_with_comment_whole),
   history_whole_reopened = (SELECT total_count FROM action_counts WHERE action_comment = 'reopened'),

   -- Current year totals (from consolidated CTE)
   history_year_open = (SELECT total_count FROM year_metrics WHERE action_comment = 'opened'),
   history_year_commented = (SELECT total_count FROM year_metrics WHERE action_comment = 'commented'),
   history_year_closed = (SELECT total_count FROM year_metrics WHERE action_comment = 'closed'),
   history_year_closed_with_comment = (SELECT total FROM closed_with_comment_year),
   history_year_reopened = (SELECT total_count FROM year_metrics WHERE action_comment = 'reopened'),

   -- Current status
   -- Using note_current_status table for better performance (ETL-003, ETL-004)
   currently_open_count = (
    SELECT /* Notes-datamartGlobal */ COALESCE(COUNT(*), 0)
    FROM dwh.note_current_status
    WHERE is_currently_open = TRUE
   ),
   currently_closed_count = (
    SELECT /* Notes-datamartGlobal */ COALESCE(COUNT(*), 0)
    FROM dwh.note_current_status
    WHERE is_currently_open = FALSE
   ),
   notes_created_last_30_days = (SELECT notes_created FROM metrics_30_days),
   notes_resolved_last_30_days = (SELECT notes_resolved FROM metrics_30_days),
   notes_backlog_size = (
    -- Using note_current_status table for better performance (ETL-003, ETL-004)
    -- Count open notes older than 7 days
    SELECT /* Notes-datamartGlobal */ COALESCE(COUNT(*), 0)
    FROM dwh.note_current_status ncs
    JOIN dwh.dimension_days dd
    ON (ncs.opened_dimension_id_date = dd.dimension_day_id)
    WHERE ncs.is_currently_open = TRUE
     AND dd.date_id < CURRENT_DATE - INTERVAL '7 days'
   ),

   -- Resolution metrics (from consolidated CTEs)
   avg_days_to_resolution = (SELECT avg_all_time FROM resolution_metrics),
   median_days_to_resolution = (SELECT median_all_time FROM resolution_metrics),
   avg_days_to_resolution_current_year = (SELECT avg_year FROM resolution_metrics_year),
   median_days_to_resolution_current_year = (SELECT median_year FROM resolution_metrics_year),
   notes_resolved_count = (SELECT total_count FROM action_counts WHERE action_comment = 'closed'),
   resolution_rate = (SELECT rate FROM resolution_rate_calc),

   -- Additional metrics
   active_users_count = (SELECT active_users FROM metrics_30_days),
   applications_used = (
    SELECT /* Notes-datamartGlobal */
     JSON_AGG(jsonb_build_object(
      'application_id', app.dimension_application_id,
      'application_name', app.application_name,
      'usage_count', app.usage_count
     ) ORDER BY app.usage_count DESC)
    FROM (
     SELECT da.dimension_application_id, da.application_name, COUNT(*) as usage_count
     FROM dwh.facts f
     JOIN dwh.dimension_applications da
     ON (f.dimension_application_creation = da.dimension_application_id)
     WHERE f.dimension_application_creation IS NOT NULL
      AND f.action_comment = 'opened'
     GROUP BY da.dimension_application_id, da.application_name
     ORDER BY usage_count DESC
     LIMIT 10
    ) app
   ),
   most_used_application_id = (
    SELECT /* Notes-datamartGlobal */ dimension_application_id
    FROM (
     SELECT f.dimension_application_creation as dimension_application_id, COUNT(*) as usage_count
     FROM dwh.facts f
     WHERE f.dimension_application_creation IS NOT NULL
      AND f.action_comment = 'opened'
     GROUP BY f.dimension_application_creation
     ORDER BY usage_count DESC
     LIMIT 1
    ) app
   ),
   mobile_apps_count = (
    SELECT /* Notes-datamartGlobal */ COUNT(DISTINCT f.dimension_application_creation)
    FROM dwh.facts f
    JOIN dwh.dimension_applications da
    ON (f.dimension_application_creation = da.dimension_application_id)
    WHERE f.action_comment = 'opened'
     AND (da.platform LIKE '%android%' OR da.platform LIKE '%ios%')
   ),
   desktop_apps_count = (
    SELECT /* Notes-datamartGlobal */ COUNT(DISTINCT f.dimension_application_creation)
    FROM dwh.facts f
    JOIN dwh.dimension_applications da
    ON (f.dimension_application_creation = da.dimension_application_id)
    WHERE f.action_comment = 'opened'
     AND (da.platform LIKE '%desktop%' OR da.platform LIKE '%web%')
   ),
   avg_comment_length = (SELECT avg_length FROM comment_metrics),
   comments_with_url_pct = (SELECT url_pct FROM comment_metrics),
   comments_with_mention_pct = (SELECT mention_pct FROM comment_metrics),
   avg_comments_per_note = (
    SELECT /* Notes-datamartGlobal */ AVG(total_comments_on_note)::DECIMAL(10,2)
    FROM (
     SELECT id_note, MAX(total_comments_on_note) as total_comments_on_note
     FROM dwh.facts
     WHERE total_comments_on_note IS NOT NULL
     GROUP BY id_note
    ) notes
   )
  WHERE dimension_global_id = 1;

  -- Top countries
  SELECT JSON_AGG(jsonb_build_object(
    'country_id', c.country_id,
    'country_name', c.country_name,
    'total_actions', c.total_actions
   ) ORDER BY c.total_actions DESC)
  INTO m_top_countries
  FROM (
   SELECT dc.country_id, dc.country_name, COUNT(*) as total_actions
   FROM dwh.facts f
   JOIN dwh.dimension_countries dc
   ON (f.dimension_id_country = dc.dimension_country_id)
   GROUP BY dc.country_id, dc.country_name
   ORDER BY total_actions DESC
   LIMIT 10
  ) c;

  UPDATE dwh.datamartGlobal
  SET top_countries = m_top_countries
  WHERE dimension_global_id = 1;

  -- Notes age distribution
  -- OPTIMIZATION 6: Replaced NOT IN with NOT EXISTS for better performance
  UPDATE dwh.datamartGlobal
  SET notes_age_distribution = (
    SELECT /* Notes-datamartGlobal */ jsonb_build_object(
     '0-7_days', COUNT(CASE WHEN age_days BETWEEN 0 AND 7 THEN 1 END),
     '8-30_days', COUNT(CASE WHEN age_days BETWEEN 8 AND 30 THEN 1 END),
     '31-90_days', COUNT(CASE WHEN age_days BETWEEN 31 AND 90 THEN 1 END),
     '90_plus_days', COUNT(CASE WHEN age_days > 90 THEN 1 END)
    )
    FROM (
     SELECT f.id_note,
      CURRENT_DATE - dd.date_id AS age_days
     FROM dwh.facts f
     JOIN dwh.dimension_days dd
     ON (f.opened_dimension_id_date = dd.dimension_day_id)
     WHERE f.action_comment = 'opened'
      AND NOT EXISTS (
       SELECT 1
       FROM dwh.facts f2
       WHERE f2.id_note = f.id_note
         AND f2.action_comment = 'closed'
         AND f2.fact_id = (
          SELECT /* Notes-datamartGlobal */ MAX(f3.fact_id)
          FROM dwh.facts f3
          WHERE f3.id_note = f2.id_note
         )
      )
    ) open_notes
  )
  WHERE dimension_global_id = 1;

  -- Update DM-011: Last comment timestamp
  -- Only if the function exists (for backward compatibility)
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_global_last_comment_timestamp') THEN
    BEGIN
      PERFORM dwh.update_global_last_comment_timestamp();
    EXCEPTION WHEN OTHERS THEN
      -- Ignore errors for missing columns (backward compatibility)
      NULL;
    END;
  END IF;

  RAISE NOTICE 'Global statistics updated successfully.';
END
$$;
