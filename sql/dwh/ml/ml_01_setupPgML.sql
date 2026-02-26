-- Setup pgml (PostgreSQL Machine Learning) for note classification
-- This script sets up pgml extension and creates necessary structures
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20
-- Purpose: Enable ML classification directly in PostgreSQL

-- ============================================================================
-- 1. Install pgml Extension
-- ============================================================================
-- Note: pgml must be installed at the system level first
-- See: https://github.com/postgresml/postgresml

CREATE EXTENSION IF NOT EXISTS pgml;

-- Verify installation
SELECT * FROM pg_extension WHERE extname = 'pgml';

-- ============================================================================
-- 2. Create Training Data View
-- ============================================================================
-- This view combines all features for ML training
-- Based on existing analysis patterns documented in ML_Implementation_Plan.md

CREATE OR REPLACE VIEW dwh.v_note_ml_training_features AS
SELECT
  f.id_note,
  f.opened_dimension_id_date,
  f.closed_dimension_id_date,

  -- Text features (from dwh.facts - already used in manual analysis)
  f.comment_length,
  f.has_url::INTEGER AS has_url_int,  -- Convert boolean to int for ML
  f.has_mention::INTEGER AS has_mention_int,
  f.hashtag_number,
  f.total_comments_on_note,

  -- Hashtag features (from hashtag analysis)
  COALESCE(nhf.hashtag_count, 0) AS hashtag_count,
  COALESCE(nhf.has_fire_keyword::INTEGER, 0) AS has_fire_keyword,
  COALESCE(nhf.has_air_keyword::INTEGER, 0) AS has_air_keyword,
  COALESCE(nhf.has_access_keyword::INTEGER, 0) AS has_access_keyword,
  COALESCE(nhf.has_campaign_keyword::INTEGER, 0) AS has_campaign_keyword,
  COALESCE(nhf.has_fix_keyword::INTEGER, 0) AS has_fix_keyword,

  -- Application features (from application pattern analysis)
  CASE
    WHEN a.application_name IN ('Maps.me', 'StreetComplete', 'OrganicMaps', 'OnOSM.org')
    THEN 1 ELSE 0
  END AS is_assisted_app,
  CASE
    WHEN a.application_name LIKE '%mobile%' OR a.application_name LIKE '%app%'
    THEN 1 ELSE 0
  END AS is_mobile_app,

  -- Geographic features (from datamartCountries analysis)
  COALESCE(dc.resolution_rate, 0.0) AS country_resolution_rate,
  COALESCE(dc.avg_days_to_resolution, 0) AS country_avg_resolution_days,
  COALESCE(dc.notes_health_score, 0.0) AS country_notes_health_score,

  -- User features (from datamartUsers and dimension_users)
  COALESCE(du.user_response_time, 0) AS user_response_time,
  COALESCE(du.history_whole_open, 0) AS user_total_notes,
  COALESCE(dimu.experience_level_id, 0) AS user_experience_level,
  COALESCE(du.id_contributor_type, 0) AS user_contributor_type_id,

  -- Temporal features
  EXTRACT(DOW FROM d.date_id) AS day_of_week,
  EXTRACT(HOUR FROM d.date_id) AS hour_of_day,
  EXTRACT(MONTH FROM d.date_id) AS month,

  -- Age features (from obsolete note analysis)
  CASE
    WHEN f.closed_dimension_id_date IS NULL
    THEN EXTRACT(DAY FROM CURRENT_DATE - d.date_id)
  END AS days_open,

  -- Target variables (for training - based on historical outcomes)
  -- Level 1: Main Category
  CASE
    WHEN f.closed_dimension_id_date IS NOT NULL
         AND (SELECT COUNT(*)
          FROM dwh.facts f2
          WHERE f2.id_note = f.id_note
            AND f2.action_comment = 'commented'
            AND f2.action_at < f.closed_dimension_id_date) > 0
    THEN 'contributes_with_change'
    WHEN f.closed_dimension_id_date IS NOT NULL
    THEN 'doesnt_contribute'
  END AS main_category,

  -- Level 2: Specific Type (simplified - can be enhanced with text analysis)
  CASE
    WHEN f.comment_length < 10 THEN 'empty'
    WHEN f.comment_length < 50 AND f.total_comments_on_note > 2 THEN 'lack_of_precision'
    WHEN f.comment_length > 200 AND f.has_url = TRUE THEN 'advertising'
    WHEN f.closed_dimension_id_date IS NULL
         AND EXTRACT(DAY FROM CURRENT_DATE - d.date_id) > 180 THEN 'obsolete'
    WHEN a.application_name IN ('Maps.me', 'StreetComplete', 'OrganicMaps', 'OnOSM.org')
         AND f.comment_length > 30 THEN 'adds_to_map'
    ELSE 'other'
  END AS specific_type,

  -- Level 3: Action Recommendation
  CASE
    WHEN f.closed_dimension_id_date IS NOT NULL
         AND (SELECT COUNT(*)
          FROM dwh.facts f2
          WHERE f2.id_note = f.id_note
            AND f2.action_comment = 'commented'
            AND f2.action_at < f.closed_dimension_id_date) > 0
    THEN 'process'
    WHEN f.closed_dimension_id_date IS NOT NULL
    THEN 'close'
    WHEN f.comment_length < 50 AND f.total_comments_on_note > 2
    THEN 'needs_more_data'
  END AS recommended_action

FROM dwh.facts f
LEFT JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
LEFT JOIN dwh.dimension_applications a ON f.dimension_application_creation = a.dimension_application_id
LEFT JOIN dwh.datamartCountries dc ON f.dimension_id_country = dc.dimension_country_id
LEFT JOIN dwh.datamartUsers du ON f.opened_dimension_id_user = du.dimension_user_id
LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
LEFT JOIN dwh.v_note_hashtag_features nhf ON f.id_note = nhf.id_note
WHERE f.action_comment = 'opened'
  AND f.closed_dimension_id_date IS NOT NULL  -- Only resolved notes for training
  AND f.comment_length > 0;  -- Only notes with content

COMMENT ON VIEW dwh.v_note_ml_training_features IS
  'Training features for ML classification. Combines metrics, hashtags, applications, geographic, user, and temporal features. Includes target variables based on historical outcomes.';

-- ============================================================================
-- 3. Create Prediction Features View (for new notes)
-- ============================================================================
-- Same features as training, but without target variables

CREATE OR REPLACE VIEW dwh.v_note_ml_prediction_features AS
SELECT
  f.id_note,
  f.opened_dimension_id_date,

  -- Same features as training view (without target variables)
  f.comment_length,
  f.has_url::INTEGER AS has_url_int,
  f.has_mention::INTEGER AS has_mention_int,
  f.hashtag_number,
  f.total_comments_on_note,

  COALESCE(nhf.hashtag_count, 0) AS hashtag_count,
  COALESCE(nhf.has_fire_keyword::INTEGER, 0) AS has_fire_keyword,
  COALESCE(nhf.has_air_keyword::INTEGER, 0) AS has_air_keyword,
  COALESCE(nhf.has_access_keyword::INTEGER, 0) AS has_access_keyword,
  COALESCE(nhf.has_campaign_keyword::INTEGER, 0) AS has_campaign_keyword,
  COALESCE(nhf.has_fix_keyword::INTEGER, 0) AS has_fix_keyword,

  CASE
    WHEN a.application_name IN ('Maps.me', 'StreetComplete', 'OrganicMaps', 'OnOSM.org')
    THEN 1 ELSE 0
  END AS is_assisted_app,
  CASE
    WHEN a.application_name LIKE '%mobile%' OR a.application_name LIKE '%app%'
    THEN 1 ELSE 0
  END AS is_mobile_app,

  COALESCE(dc.resolution_rate, 0.0) AS country_resolution_rate,
  COALESCE(dc.avg_days_to_resolution, 0) AS country_avg_resolution_days,
  COALESCE(dc.notes_health_score, 0.0) AS country_notes_health_score,

  COALESCE(du.user_response_time, 0) AS user_response_time,
  COALESCE(du.history_whole_open, 0) AS user_total_notes,
  COALESCE(dimu.experience_level_id, 0) AS user_experience_level,
  COALESCE(du.id_contributor_type, 0) AS user_contributor_type_id,

  EXTRACT(DOW FROM d.date_id) AS day_of_week,
  EXTRACT(HOUR FROM d.date_id) AS hour_of_day,
  EXTRACT(MONTH FROM d.date_id) AS month,

  EXTRACT(DAY FROM CURRENT_DATE - d.date_id) AS days_open

FROM dwh.facts f
LEFT JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
LEFT JOIN dwh.dimension_applications a ON f.dimension_application_creation = a.dimension_application_id
LEFT JOIN dwh.datamartCountries dc ON f.dimension_id_country = dc.dimension_country_id
LEFT JOIN dwh.datamartUsers du ON f.opened_dimension_id_user = du.dimension_user_id
LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
LEFT JOIN dwh.v_note_hashtag_features nhf ON f.id_note = nhf.id_note
WHERE f.action_comment = 'opened'
  AND f.comment_length > 0;

COMMENT ON VIEW dwh.v_note_ml_prediction_features IS
  'Features for ML prediction on new notes. Same structure as training features but without target variables.';

-- ============================================================================
-- Usage Examples
-- ============================================================================

-- Example 1: Check training data availability
-- SELECT
--   COUNT(*) as total_notes,
--   COUNT(DISTINCT main_category) as categories,
--   COUNT(DISTINCT specific_type) as types,
--   COUNT(DISTINCT recommended_action) as actions
-- FROM dwh.v_note_ml_training_features
-- WHERE main_category IS NOT NULL;

-- Example 2: View sample training data
-- SELECT * FROM dwh.v_note_ml_training_features LIMIT 10;

-- Example 3: Check feature distributions
-- SELECT
--   AVG(comment_length) as avg_length,
--   AVG(has_url_int) as url_ratio,
--   AVG(hashtag_count) as avg_hashtags,
--   AVG(country_resolution_rate) as avg_resolution_rate
-- FROM dwh.v_note_ml_training_features;
