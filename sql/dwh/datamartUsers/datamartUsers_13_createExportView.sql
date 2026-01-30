-- Create export view for datamartUsers that excludes internal columns
-- Internal columns (prefixed with _partial_ or _last_processed_) are excluded
-- from JSON exports as they are implementation details, not user-facing metrics
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-03

-- Drop view if exists (for idempotency)
DROP VIEW IF EXISTS dwh.datamartusers_export;

-- Create view that excludes internal columns
-- This view is used by JSON export scripts to ensure internal columns
-- (prefixed with _partial_ or _last_processed_) are not included in exports
CREATE VIEW dwh.datamartusers_export AS
SELECT 
  -- Primary keys and identifiers
  dimension_user_id,
  user_id,
  username,
  
  -- Dates
  date_starting_creating_notes,
  date_starting_solving_notes,
  
  -- First/last note IDs
  first_open_note_id,
  first_commented_note_id,
  first_closed_note_id,
  first_reopened_note_id,
  latest_open_note_id,
  latest_commented_note_id,
  latest_closed_note_id,
  latest_reopened_note_id,
  
  -- Activity tracking
  last_year_activity,
  id_contributor_type,
  
  -- JSON aggregations
  dates_most_open,
  dates_most_closed,
  hashtags,
  countries_open_notes,
  countries_solving_notes,
  countries_open_notes_current_month,
  countries_solving_notes_current_month,
  countries_open_notes_current_day,
  countries_solving_notes_current_day,
  working_hours_of_week_opening,
  working_hours_of_week_commenting,
  working_hours_of_week_closing,
  
  -- Historical counts (whole)
  history_whole_open,
  history_whole_commented,
  history_whole_closed,
  history_whole_closed_with_comment,
  history_whole_reopened,
  
  -- Historical counts (current year)
  history_year_open,
  history_year_commented,
  history_year_closed,
  history_year_closed_with_comment,
  history_year_reopened,
  
  -- Historical counts (current month)
  history_month_open,
  history_month_commented,
  history_month_closed,
  history_month_closed_with_comment,
  history_month_reopened,
  
  -- Historical counts (current day)
  history_day_open,
  history_day_commented,
  history_day_closed,
  history_day_closed_with_comment,
  history_day_reopened,
  
  -- Resolution metrics
  avg_days_to_resolution,
  median_days_to_resolution,
  notes_resolved_count,
  notes_still_open_count,
  notes_opened_but_not_closed_by_user,
  resolution_rate,
  
  -- Application statistics
  applications_used,
  most_used_application_id,
  mobile_apps_count,
  desktop_apps_count,
  
  -- Content quality
  avg_comment_length,
  comments_with_url_count,
  comments_with_url_pct,
  comments_with_mention_count,
  comments_with_mention_pct,
  avg_comments_per_note,
  
  -- Community health
  active_notes_count,
  notes_backlog_size,
  notes_age_distribution,
  notes_created_last_30_days,
  notes_resolved_last_30_days,
  
  -- Resolution temporal metrics
  resolution_by_year,
  resolution_by_month,
  
  -- Hashtag metrics
  hashtags_opening,
  hashtags_resolution,
  hashtags_comments,
  favorite_opening_hashtag,
  favorite_resolution_hashtag,
  opening_hashtag_count,
  resolution_hashtag_count,
  
  -- Application trends
  application_usage_trends,
  version_adoption_rates,
  
  -- User behavior
  user_response_time,
  days_since_last_action,
  collaboration_patterns,
  
  -- Enhanced date/time columns
  iso_week,
  quarter,
  month_name,
  hour_of_week,
  period_of_day,
  
  -- Export tracking (needed for incremental exports)
  json_exported
  
  -- NOTE: Columns prefixed with _partial_ or _last_processed_ are EXCLUDED
  -- These are internal implementation details for incremental updates:
  -- - _partial_count_opened
  -- - _partial_count_commented
  -- - _partial_count_closed
  -- - _partial_count_reopened
  -- - _partial_count_closed_with_comment
  -- - _partial_sum_comment_length
  -- - _partial_count_comments
  -- - _partial_sum_days_to_resolution
  -- - _partial_count_resolved
  -- - _last_processed_fact_id
  
FROM dwh.datamartusers;

COMMENT ON VIEW dwh.datamartusers_export IS 
  'Export view for datamartUsers that excludes internal columns (_partial_* and _last_processed_*). '
  'Use this view for JSON exports to ensure internal implementation details are not included.';
