-- Setup pgml (PostgreSQL Machine Learning) for note classification
-- This script sets up pgml extension and creates necessary structures
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20
-- Purpose: Enable ML classification directly in PostgreSQL
-- \ir includes resolve relative to this file's directory (sql/dwh/ml/).

-- ============================================================================
-- 1. Install pgml Extension
-- ============================================================================
-- Note: pgml must be installed at the system level first
-- See: https://github.com/postgresml/postgresml

CREATE EXTENSION IF NOT EXISTS pgml;

-- Verify installation
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'pgml';

\ir ml_00_note_type_classifications.sql

-- ============================================================================
-- 2. Hashtag features view (dependency for ML feature joins)
-- ============================================================================
-- Also defined in ml_00_analyzeHashtagsForClassification.sql section 6.
-- Created here so setup works without running the analysis script first
-- (e.g. ml_retrain.sh / fresh DWH).

CREATE OR REPLACE VIEW dwh.v_note_hashtag_features AS
SELECT
  f.id_note,
  f.opened_dimension_id_date,
  COUNT(DISTINCT fh.dimension_hashtag_id) AS hashtag_count,
  ARRAY_AGG(DISTINCT h.description ORDER BY h.description) AS hashtag_names,
  bool_or(LOWER(h.description) LIKE '%fire%'
             OR LOWER(h.description) LIKE '%bomber%') AS has_fire_keyword,
  bool_or(LOWER(h.description) LIKE '%air%'
             OR LOWER(h.description) LIKE '%plane%') AS has_air_keyword,
  bool_or(LOWER(h.description) LIKE '%wheel%'
             OR LOWER(h.description) LIKE '%access%') AS has_access_keyword,
  bool_or(LOWER(h.description) LIKE '%missing%'
             OR LOWER(h.description) LIKE '%campaign%') AS has_campaign_keyword,
  bool_or(LOWER(h.description) LIKE '%fix%'
             OR LOWER(h.description) LIKE '%correc%') AS has_fix_keyword
FROM dwh.facts f
LEFT JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
LEFT JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
WHERE f.action_comment = 'opened'
GROUP BY f.id_note, f.opened_dimension_id_date;

COMMENT ON VIEW dwh.v_note_hashtag_features IS
  'Hashtag-based features for ML classification. Includes hashtag count, names, and category indicators.';

-- --------------------------------------------------------------------------
-- Aggregate comment count per note (full lifecycle; excludes only 'opened').
-- facts.total_comments_on_note on action_comment='opened' is UP TO open time only
-- (trigger: count where fact_id < opened row → always 0), which degenerates ML features
-- and can trigger PostgresML snapshot panics (`Option::unwrap()` on empty stats).
CREATE OR REPLACE VIEW dwh.v_note_ml_comment_counts AS
SELECT
  id_note,
  COUNT(*) FILTER (WHERE action_comment = 'commented')::INTEGER AS comments_on_note
FROM dwh.facts
GROUP BY id_note;

COMMENT ON VIEW dwh.v_note_ml_comment_counts IS
  'Per-note count of commented actions (all time). Used for ML features/target rules instead '
  'of facts.total_comments_on_note on opened rows (always zero at insertion).';

-- ============================================================================
-- 3. Create Training Data View
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
  COALESCE(ncc.comments_on_note, 0) AS total_comments_on_note,

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
  -- Cast to timestamp: EXTRACT(HOUR FROM date) errors; some DWH loads use DATE for action_at.
  -- Do not cast to INTEGER: CREATE OR REPLACE VIEW cannot change hour_of_day type vs existing view.
  EXTRACT(HOUR FROM f.action_at::TIMESTAMP) AS hour_of_day,
  EXTRACT(MONTH FROM d.date_id) AS month,

  -- Calendar days from open-date to close-date (training rows are always resolved here).
  (d_close.date_id - d.date_id) AS days_open,

  -- Target variables (for training - based on historical outcomes)
  -- Level 1: Main Category
  CASE
    WHEN f.closed_dimension_id_date IS NOT NULL
         AND (SELECT COUNT(*)
          FROM dwh.facts f2
          WHERE f2.id_note = f.id_note
            AND f2.action_comment = 'commented'
            AND f2.action_at < (
              SELECT MIN(fc.action_at)
              FROM dwh.facts fc
              WHERE fc.id_note = f.id_note
                AND fc.action_comment = 'closed'
                AND fc.action_at > f.action_at
            )) > 0
    THEN 'contributes_with_change'
    WHEN f.closed_dimension_id_date IS NOT NULL
    THEN 'doesnt_contribute'
  END AS main_category,

  -- Level 2: Specific Type (simplified - can be enhanced with text analysis)
  CASE
    WHEN f.comment_length < 10 THEN 'empty'
    WHEN f.comment_length < 50 AND COALESCE(ncc.comments_on_note, 0) > 2 THEN 'lack_of_precision'
    WHEN f.comment_length > 200 AND f.has_url = TRUE THEN 'advertising'
    WHEN f.closed_dimension_id_date IS NULL
         AND (CURRENT_DATE - d.date_id) > 180 THEN 'obsolete'
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
            AND f2.action_at < (
              SELECT MIN(fc.action_at)
              FROM dwh.facts fc
              WHERE fc.id_note = f.id_note
                AND fc.action_comment = 'closed'
                AND fc.action_at > f.action_at
            )) > 0
    THEN 'process'
    WHEN f.closed_dimension_id_date IS NOT NULL
    THEN 'close'
    WHEN f.comment_length < 50 AND COALESCE(ncc.comments_on_note, 0) > 2
    THEN 'needs_more_data'
  END AS recommended_action

FROM dwh.facts f
LEFT JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
LEFT JOIN dwh.dimension_days d_close ON f.closed_dimension_id_date = d_close.dimension_day_id
LEFT JOIN dwh.dimension_applications a ON f.dimension_application_creation = a.dimension_application_id
LEFT JOIN dwh.datamartCountries dc ON f.dimension_id_country = dc.dimension_country_id
LEFT JOIN dwh.datamartUsers du ON f.opened_dimension_id_user = du.dimension_user_id
LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
LEFT JOIN dwh.v_note_hashtag_features nhf ON f.id_note = nhf.id_note
LEFT JOIN dwh.v_note_ml_comment_counts ncc ON ncc.id_note = f.id_note
WHERE f.action_comment = 'opened'
  AND f.closed_dimension_id_date IS NOT NULL  -- Only resolved notes for training
  AND f.comment_length > 0;  -- Only notes with content

COMMENT ON VIEW dwh.v_note_ml_training_features IS
  'Training features for ML classification. Combines metrics, hashtags, applications, geographic, user, and temporal features. Includes target variables based on historical outcomes.';

-- ============================================================================
-- 4. Create Prediction Features View (for new notes)
-- ============================================================================
-- CREATE OR REPLACE cannot change existing column types (e.g. INTEGER -> DOUBLE PRECISION).
-- CASCADE may drop dependents such as dwh.predict_note_classification_pgml; restore via
-- sql/dwh/ml/ml_03_predictWithPgML.sql (ml_retrain.sh does this after training).

DROP VIEW IF EXISTS dwh.v_note_ml_prediction_features CASCADE;

CREATE VIEW dwh.v_note_ml_prediction_features AS
SELECT
  f.id_note,
  f.opened_dimension_id_date,

  -- Finite DOUBLE PRECISION features (same clamps as v_note_ml_train_*); avoids NULL entries
  -- in ARRAY[...]::DOUBLE PRECISION[] for pgml.predict (ERROR: array contains NULL).
  LEAST(GREATEST(COALESCE(f.comment_length, 0), 0), 524288)::DOUBLE PRECISION AS comment_length,
  LEAST(GREATEST(COALESCE(f.has_url::INTEGER, 0), 0), 1)::DOUBLE PRECISION AS has_url_int,
  LEAST(GREATEST(COALESCE(f.has_mention::INTEGER, 0), 0), 1)::DOUBLE PRECISION AS has_mention_int,
  LEAST(GREATEST(COALESCE(f.hashtag_number, 0), 0), 100000)::DOUBLE PRECISION AS hashtag_number,
  LEAST(GREATEST(COALESCE(ncc.comments_on_note, 0), 0), 2147483647)::DOUBLE PRECISION
    AS total_comments_on_note,
  LEAST(GREATEST(COALESCE(nhf.hashtag_count, 0), 0), 2147483647)::DOUBLE PRECISION AS hashtag_count,
  LEAST(GREATEST(COALESCE(nhf.has_fire_keyword::INTEGER, 0), 0), 1)::DOUBLE PRECISION AS has_fire_keyword,
  LEAST(GREATEST(COALESCE(nhf.has_air_keyword::INTEGER, 0), 0), 1)::DOUBLE PRECISION AS has_air_keyword,
  LEAST(GREATEST(COALESCE(nhf.has_access_keyword::INTEGER, 0), 0), 1)::DOUBLE PRECISION
    AS has_access_keyword,
  LEAST(GREATEST(COALESCE(nhf.has_campaign_keyword::INTEGER, 0), 0), 1)::DOUBLE PRECISION
    AS has_campaign_keyword,
  LEAST(GREATEST(COALESCE(nhf.has_fix_keyword::INTEGER, 0), 0), 1)::DOUBLE PRECISION AS has_fix_keyword,

  LEAST(GREATEST(COALESCE(
    CASE
      WHEN a.application_name IN ('Maps.me', 'StreetComplete', 'OrganicMaps', 'OnOSM.org')
      THEN 1 ELSE 0
    END, 0), 0), 1)::DOUBLE PRECISION AS is_assisted_app,
  LEAST(GREATEST(COALESCE(
    CASE
      WHEN a.application_name LIKE '%mobile%' OR a.application_name LIKE '%app%'
      THEN 1 ELSE 0
    END, 0), 0), 1)::DOUBLE PRECISION AS is_mobile_app,

  LEAST(GREATEST(COALESCE(dc.resolution_rate, 0.0)::NUMERIC, 0), 1)::DOUBLE PRECISION AS country_resolution_rate,
  LEAST(GREATEST(COALESCE(dc.avg_days_to_resolution, 0), 0), 100000)::DOUBLE PRECISION
    AS country_avg_resolution_days,
  LEAST(GREATEST(COALESCE(dc.notes_health_score, 0.0)::NUMERIC, 0), 1)::DOUBLE PRECISION
    AS country_notes_health_score,

  LEAST(GREATEST(COALESCE(du.user_response_time, 0), 0), 2147483647)::DOUBLE PRECISION AS user_response_time,
  LEAST(GREATEST(COALESCE(du.history_whole_open, 0), 0), 2147483647)::DOUBLE PRECISION AS user_total_notes,
  LEAST(GREATEST(COALESCE(dimu.experience_level_id, 0), 0), 32767)::DOUBLE PRECISION AS user_experience_level,
  LEAST(GREATEST(COALESCE(du.id_contributor_type, 0), 0), 2147483647)::DOUBLE PRECISION
    AS user_contributor_type_id,

  LEAST(GREATEST(COALESCE(EXTRACT(DOW FROM d.date_id), 0), 0), 6)::DOUBLE PRECISION AS day_of_week,
  LEAST(GREATEST(COALESCE(EXTRACT(HOUR FROM f.action_at::TIMESTAMP), 0), 0), 23)::DOUBLE PRECISION AS hour_of_day,
  LEAST(GREATEST(COALESCE(EXTRACT(MONTH FROM d.date_id), 0), 0), 12)::DOUBLE PRECISION AS month,
  LEAST(GREATEST(COALESCE((CURRENT_DATE - d.date_id), 0), 0), 100000)::DOUBLE PRECISION AS days_open

FROM dwh.facts f
LEFT JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
LEFT JOIN dwh.dimension_applications a ON f.dimension_application_creation = a.dimension_application_id
LEFT JOIN dwh.datamartCountries dc ON f.dimension_id_country = dc.dimension_country_id
LEFT JOIN dwh.datamartUsers du ON f.opened_dimension_id_user = du.dimension_user_id
LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
LEFT JOIN dwh.v_note_hashtag_features nhf ON f.id_note = nhf.id_note
LEFT JOIN dwh.v_note_ml_comment_counts ncc ON ncc.id_note = f.id_note
WHERE f.action_comment = 'opened'
  AND f.comment_length > 0;

COMMENT ON VIEW dwh.v_note_ml_prediction_features IS
  'Features for ML prediction on notes (no targets). DOUBLE PRECISION columns with COALESCE/clamps '
  'match v_note_ml_train_* inference order; avoids NULL elements in pgml.predict feature arrays.';

\ir ml_00_note_ml_feature_vector.sql

-- ============================================================================
-- 5. pgml.training relations (feature matrix + single label column)
-- ============================================================================
-- PostgresML snapshots all relation columns except y_column_name into X. Wide views with
-- id_note / dimension surrogates / sibling labels confused stats in some pgml builds
-- (`Option::unwrap()` on None). Use these narrow views: feature column order MUST match
-- ARRAY[...] in sql/dwh/ml/ml_03_predictWithPgML.sql.
--
-- PostgresML 2.x (Rust snapshot) computes column stats after dropping NaNs; if every value is
-- NULL/NaN in the Rust binding that column becomes empty and `analyze()` hits
-- `data.first().unwrap()` -> ERROR: Option::unwrap() on None. Coalesce finite numbers and clamp
-- large counts so bindings never synthesize all-NaN feature columns.

DROP VIEW IF EXISTS dwh.v_note_ml_train_main_category CASCADE;
CREATE VIEW dwh.v_note_ml_train_main_category AS
SELECT
  LEAST(GREATEST(COALESCE(pf.comment_length, 0), 0), 524288)::DOUBLE PRECISION AS comment_length,
  LEAST(GREATEST(COALESCE(pf.has_url_int, 0), 0), 1)::DOUBLE PRECISION AS has_url_int,
  LEAST(GREATEST(COALESCE(pf.has_mention_int, 0), 0), 1)::DOUBLE PRECISION AS has_mention_int,
  LEAST(GREATEST(COALESCE(pf.hashtag_number, 0), 0), 100000)::DOUBLE PRECISION AS hashtag_number,
  LEAST(GREATEST(COALESCE(pf.total_comments_on_note, 0), 0), 2147483647)::DOUBLE PRECISION
    AS total_comments_on_note,
  LEAST(GREATEST(COALESCE(pf.hashtag_count, 0), 0), 2147483647)::DOUBLE PRECISION AS hashtag_count,
  LEAST(GREATEST(COALESCE(pf.has_fire_keyword, 0), 0), 1)::DOUBLE PRECISION AS has_fire_keyword,
  LEAST(GREATEST(COALESCE(pf.has_air_keyword, 0), 0), 1)::DOUBLE PRECISION AS has_air_keyword,
  LEAST(GREATEST(COALESCE(pf.has_access_keyword, 0), 0), 1)::DOUBLE PRECISION AS has_access_keyword,
  LEAST(GREATEST(COALESCE(pf.has_campaign_keyword, 0), 0), 1)::DOUBLE PRECISION AS has_campaign_keyword,
  LEAST(GREATEST(COALESCE(pf.has_fix_keyword, 0), 0), 1)::DOUBLE PRECISION AS has_fix_keyword,
  LEAST(GREATEST(COALESCE(pf.is_assisted_app, 0), 0), 1)::DOUBLE PRECISION AS is_assisted_app,
  LEAST(GREATEST(COALESCE(pf.is_mobile_app, 0), 0), 1)::DOUBLE PRECISION AS is_mobile_app,
  LEAST(GREATEST(COALESCE(pf.country_resolution_rate, 0)::NUMERIC, 0), 1)::DOUBLE PRECISION
    AS country_resolution_rate,
  LEAST(GREATEST(COALESCE(pf.country_avg_resolution_days, 0), 0), 100000)::DOUBLE PRECISION
    AS country_avg_resolution_days,
  LEAST(GREATEST(COALESCE(pf.country_notes_health_score, 0)::NUMERIC, 0), 1)::DOUBLE PRECISION
    AS country_notes_health_score,
  LEAST(GREATEST(COALESCE(pf.user_response_time, 0), 0), 2147483647)::DOUBLE PRECISION
    AS user_response_time,
  LEAST(GREATEST(COALESCE(pf.user_total_notes, 0), 0), 2147483647)::DOUBLE PRECISION
    AS user_total_notes,
  LEAST(GREATEST(COALESCE(pf.user_experience_level, 0), 0), 32767)::DOUBLE PRECISION
    AS user_experience_level,
  LEAST(GREATEST(COALESCE(pf.user_contributor_type_id, 0), 0), 2147483647)::DOUBLE PRECISION
    AS user_contributor_type_id,
  LEAST(GREATEST(COALESCE(pf.day_of_week, 0), 0), 6)::DOUBLE PRECISION AS day_of_week,
  LEAST(GREATEST(COALESCE(pf.hour_of_day, 0), 0), 23)::DOUBLE PRECISION AS hour_of_day,
  LEAST(GREATEST(COALESCE(pf.month, 0), 0), 12)::DOUBLE PRECISION AS month,
  LEAST(GREATEST(COALESCE(pf.days_open, 0), 0), 100000)::DOUBLE PRECISION AS days_open,
  CASE pf.main_category
    WHEN 'doesnt_contribute' THEN 0::INTEGER
    WHEN 'contributes_with_change' THEN 1::INTEGER
  END AS main_category
FROM dwh.v_note_ml_training_features pf
WHERE pf.main_category IS NOT NULL;

COMMENT ON VIEW dwh.v_note_ml_train_main_category IS
  'pgml.train: finite DOUBLE PRECISION features (coerced/clamped); main_category INTEGER 0/1.';

CREATE OR REPLACE VIEW dwh.v_note_ml_train_specific_type AS
SELECT
  comment_length,
  has_url_int,
  has_mention_int,
  hashtag_number,
  total_comments_on_note,
  hashtag_count,
  has_fire_keyword,
  has_air_keyword,
  has_access_keyword,
  has_campaign_keyword,
  has_fix_keyword,
  is_assisted_app,
  is_mobile_app,
  country_resolution_rate,
  country_avg_resolution_days,
  country_notes_health_score,
  user_response_time,
  user_total_notes,
  user_experience_level,
  user_contributor_type_id,
  day_of_week,
  hour_of_day,
  month,
  days_open,
  specific_type
FROM dwh.v_note_ml_training_features
WHERE specific_type IS NOT NULL;

COMMENT ON VIEW dwh.v_note_ml_train_specific_type IS
  'pgml.train relation for specific_type label; features match inference ARRAY order.';

CREATE OR REPLACE VIEW dwh.v_note_ml_train_action AS
SELECT
  comment_length,
  has_url_int,
  has_mention_int,
  hashtag_number,
  total_comments_on_note,
  hashtag_count,
  has_fire_keyword,
  has_air_keyword,
  has_access_keyword,
  has_campaign_keyword,
  has_fix_keyword,
  is_assisted_app,
  is_mobile_app,
  country_resolution_rate,
  country_avg_resolution_days,
  country_notes_health_score,
  user_response_time,
  user_total_notes,
  user_experience_level,
  user_contributor_type_id,
  day_of_week,
  hour_of_day,
  month,
  days_open,
  recommended_action
FROM dwh.v_note_ml_training_features
WHERE recommended_action IS NOT NULL;

COMMENT ON VIEW dwh.v_note_ml_train_action IS
  'pgml.train relation for recommended_action label; features match inference ARRAY order.';

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
