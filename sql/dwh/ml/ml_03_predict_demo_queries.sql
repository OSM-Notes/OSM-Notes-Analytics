-- Optional interactive demos and sample INSERT for pgml prediction (run manually).
-- Requires `psql -f sql/dwh/ml/ml_03_predictWithPgML.sql` (or equivalent) deployed first.
--
-- Some PostgreSQL + pgml builds error on parallel scans:
--   ERROR: cannot assign transaction IDs during a parallel operation
-- Session settings below discourage parallel gather / leader participation for these ad-hoc queries.

SET max_parallel_workers_per_gather = 0;
SET parallel_setup_cost = '1000000000000';
SET parallel_tuple_cost = '1000000000000';
SET parallel_leader_participation = off;

-- ============================================================================
-- 1. Predict Main Category (Level 1)
-- ============================================================================

SELECT
  id_note,
  opened_dimension_id_date,
  CASE ROUND(pgml.predict(
    'note_classification_main_category'::TEXT,
    dwh.note_ml_feature_vector(
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
      days_open
    )
  )::NUMERIC)::INTEGER
    WHEN 1 THEN 'contributes_with_change'::VARCHAR
    ELSE 'doesnt_contribute'::VARCHAR
  END AS predicted_category
FROM dwh.v_note_ml_prediction_features
WHERE id_note NOT IN (
  SELECT id_note FROM dwh.note_type_classifications
)
LIMIT 100;

-- ============================================================================
-- 2. Predict Specific Type (Level 2)
-- ============================================================================

SELECT
  id_note,
  opened_dimension_id_date,
  pgml.predict(
    'note_classification_specific_type'::TEXT,
    dwh.note_ml_feature_vector(
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
      days_open
    )
  ) AS predicted_type
FROM dwh.v_note_ml_prediction_features
WHERE id_note NOT IN (
  SELECT id_note FROM dwh.note_type_classifications
)
LIMIT 100;

-- ============================================================================
-- 3. Predict Action Recommendation (Level 3)
-- ============================================================================

SELECT
  id_note,
  opened_dimension_id_date,
  pgml.predict(
    'note_classification_action'::TEXT,
    dwh.note_ml_feature_vector(
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
      days_open
    )
  ) AS recommended_action
FROM dwh.v_note_ml_prediction_features
WHERE id_note NOT IN (
  SELECT id_note FROM dwh.note_type_classifications
)
LIMIT 100;

-- ============================================================================
-- 4. Complete Hierarchical Prediction (All Levels)
-- ============================================================================
-- Predict all three levels and store in classification table

INSERT INTO dwh.note_type_classifications (
  id_note,
  main_category,
  category_confidence,
  category_method,
  specific_type,
  type_confidence,
  type_method,
  recommended_action,
  action_confidence,
  action_method,
  priority_score,
  classification_version,
  classification_timestamp
)
SELECT
  pred.id_note,
  pred.main_category,
  pred.category_confidence,
  pred.category_method,
  pred.specific_type,
  pred.type_confidence,
  pred.type_method,
  pred.recommended_action,
  pred.action_confidence,
  pred.action_method,
  CASE
    WHEN pred.main_category = 'contributes_with_change'
      AND pred.recommended_action = 'process'
    THEN 9
    WHEN pred.recommended_action = 'needs_more_data'
    THEN 6
    WHEN pred.recommended_action = 'close'
    THEN 3
    ELSE 5
  END AS priority_score,
  pred.classification_version,
  pred.classification_timestamp
FROM (
  SELECT
    pf.id_note,
    CASE ROUND(pgml.predict(
      'note_classification_main_category'::TEXT,
      dwh.note_ml_feature_vector(
        pf.comment_length,
        pf.has_url_int,
        pf.has_mention_int,
        pf.hashtag_number,
        pf.total_comments_on_note,
        pf.hashtag_count,
        pf.has_fire_keyword,
        pf.has_air_keyword,
        pf.has_access_keyword,
        pf.has_campaign_keyword,
        pf.has_fix_keyword,
        pf.is_assisted_app,
        pf.is_mobile_app,
        pf.country_resolution_rate,
        pf.country_avg_resolution_days,
        pf.country_notes_health_score,
        pf.user_response_time,
        pf.user_total_notes,
        pf.user_experience_level,
        pf.user_contributor_type_id,
        pf.day_of_week,
        pf.hour_of_day,
        pf.month,
        pf.days_open
      )
    )::NUMERIC)::INTEGER
      WHEN 1 THEN 'contributes_with_change'::VARCHAR
      ELSE 'doesnt_contribute'::VARCHAR
    END AS main_category,
    0.8 AS category_confidence,
    'ml_based' AS category_method,
    pgml.predict(
      'note_classification_specific_type'::TEXT,
      dwh.note_ml_feature_vector(
        pf.comment_length,
        pf.has_url_int,
        pf.has_mention_int,
        pf.hashtag_number,
        pf.total_comments_on_note,
        pf.hashtag_count,
        pf.has_fire_keyword,
        pf.has_air_keyword,
        pf.has_access_keyword,
        pf.has_campaign_keyword,
        pf.has_fix_keyword,
        pf.is_assisted_app,
        pf.is_mobile_app,
        pf.country_resolution_rate,
        pf.country_avg_resolution_days,
        pf.country_notes_health_score,
        pf.user_response_time,
        pf.user_total_notes,
        pf.user_experience_level,
        pf.user_contributor_type_id,
        pf.day_of_week,
        pf.hour_of_day,
        pf.month,
        pf.days_open
      )
    )::VARCHAR AS specific_type,
    0.75 AS type_confidence,
    'ml_based' AS type_method,
    pgml.predict(
      'note_classification_action'::TEXT,
      dwh.note_ml_feature_vector(
        pf.comment_length,
        pf.has_url_int,
        pf.has_mention_int,
        pf.hashtag_number,
        pf.total_comments_on_note,
        pf.hashtag_count,
        pf.has_fire_keyword,
        pf.has_air_keyword,
        pf.has_access_keyword,
        pf.has_campaign_keyword,
        pf.has_fix_keyword,
        pf.is_assisted_app,
        pf.is_mobile_app,
        pf.country_resolution_rate,
        pf.country_avg_resolution_days,
        pf.country_notes_health_score,
        pf.user_response_time,
        pf.user_total_notes,
        pf.user_experience_level,
        pf.user_contributor_type_id,
        pf.day_of_week,
        pf.hour_of_day,
        pf.month,
        pf.days_open
      )
    )::VARCHAR AS recommended_action,
    0.8 AS action_confidence,
    'ml_based' AS action_method,
    'pgml_v1.0' AS classification_version,
    CURRENT_TIMESTAMP AS classification_timestamp
  FROM dwh.v_note_ml_prediction_features pf
  WHERE pf.id_note NOT IN (
    SELECT id_note FROM dwh.note_type_classifications
  )
  LIMIT 1000
) AS pred;

-- ============================================================================
-- 5. Get Prediction Probabilities (for confidence scores)
-- ============================================================================
-- Note: pgml.predict_proba() probabilities use string keys aligned with INTEGER class labels,
-- typically "0" and "1" for the narrow main-category training view.

SELECT
  id_note,
  pgml.predict_proba(
    'note_classification_main_category'::TEXT,
    dwh.note_ml_feature_vector(
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
      days_open
    )
  ) AS category_probabilities
FROM dwh.v_note_ml_prediction_features
WHERE id_note = 12345;  -- Example note ID
