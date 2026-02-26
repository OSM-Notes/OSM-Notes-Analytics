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
-- Joins dimension_users and dimension_experience_levels to expose experience level
CREATE VIEW dwh.datamartusers_export AS
SELECT
  -- Primary keys and identifiers
  du.dimension_user_id,
  du.user_id,
  du.username,

  -- Dates
  du.date_starting_creating_notes,
  du.date_starting_solving_notes,

  -- First/last note IDs
  du.first_open_note_id,
  du.first_commented_note_id,
  du.first_closed_note_id,
  du.first_reopened_note_id,
  du.latest_open_note_id,
  du.latest_commented_note_id,
  du.latest_closed_note_id,
  du.latest_reopened_note_id,

  -- Activity tracking
  du.last_year_activity,
  du.id_contributor_type,
  el.dimension_experience_id AS experience_level_id,
  el.experience_level AS experience_level,

  -- JSON aggregations
  du.dates_most_open,
  du.dates_most_closed,
  du.hashtags,
  du.countries_open_notes,
  du.countries_solving_notes,
  du.countries_open_notes_current_month,
  du.countries_solving_notes_current_month,
  du.countries_open_notes_current_day,
  du.countries_solving_notes_current_day,
  du.working_hours_of_week_opening,
  du.working_hours_of_week_commenting,
  du.working_hours_of_week_closing,

  -- Historical counts (whole)
  du.history_whole_open,
  du.history_whole_commented,
  du.history_whole_closed,
  du.history_whole_closed_with_comment,
  du.history_whole_reopened,

  -- Historical counts (current year)
  du.history_year_open,
  du.history_year_commented,
  du.history_year_closed,
  du.history_year_closed_with_comment,
  du.history_year_reopened,

  -- Historical counts (current month)
  du.history_month_open,
  du.history_month_commented,
  du.history_month_closed,
  du.history_month_closed_with_comment,
  du.history_month_reopened,

  -- Historical counts (current day)
  du.history_day_open,
  du.history_day_commented,
  du.history_day_closed,
  du.history_day_closed_with_comment,
  du.history_day_reopened,

  -- Resolution metrics
  du.avg_days_to_resolution,
  du.median_days_to_resolution,
  du.notes_resolved_count,
  du.notes_still_open_count,
  du.notes_opened_but_not_closed_by_user,
  du.resolution_rate,

  -- Application statistics
  du.applications_used,
  du.most_used_application_id,
  du.mobile_apps_count,
  du.desktop_apps_count,

  -- Content quality
  du.avg_comment_length,
  du.comments_with_url_count,
  du.comments_with_url_pct,
  du.comments_with_mention_count,
  du.comments_with_mention_pct,
  du.avg_comments_per_note,

  -- Community health
  du.active_notes_count,
  du.notes_backlog_size,
  du.notes_age_distribution,
  du.notes_created_last_30_days,
  du.notes_resolved_last_30_days,

  -- Resolution temporal metrics
  du.resolution_by_year,
  du.resolution_by_month,

  -- Hashtag metrics
  du.hashtags_opening,
  du.hashtags_resolution,
  du.hashtags_comments,
  du.favorite_opening_hashtag,
  du.favorite_resolution_hashtag,
  du.opening_hashtag_count,
  du.resolution_hashtag_count,

  -- Application trends
  du.application_usage_trends,
  du.version_adoption_rates,

  -- User behavior
  du.user_response_time,
  du.days_since_last_action,
  du.collaboration_patterns,

  -- Enhanced date/time columns
  du.iso_week,
  du.quarter,
  du.month_name,
  du.hour_of_week,
  du.period_of_day,

  -- Export tracking (needed for incremental exports)
  du.json_exported

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

FROM dwh.datamartusers du
LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
LEFT JOIN dwh.dimension_experience_levels el ON dimu.experience_level_id = el.dimension_experience_id;

COMMENT ON VIEW dwh.datamartusers_export IS
  'Export view for datamartUsers that excludes internal columns (_partial_* and _last_processed_*). '
  'Use this view for JSON exports to ensure internal implementation details are not included.';
