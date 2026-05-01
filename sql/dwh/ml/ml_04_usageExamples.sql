-- Usage examples: How to consume pgml models after training
-- This script shows practical examples of using trained models
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20
-- Purpose: Demonstrate how to use pgml models in production

-- ============================================================================
-- 1. Basic Prediction: Single Note
-- ============================================================================
-- Get classification for a specific note

SELECT
  id_note,
  opened_dimension_id_date,
  -- Level 1: Main Category
  pgml.predict(
    'note_classification_main_category',
    ARRAY[
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
    ]
  )::VARCHAR AS predicted_category,
  -- Level 2: Specific Type
  pgml.predict(
    'note_classification_specific_type',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS predicted_type,
  -- Level 3: Action Recommendation
  pgml.predict(
    'note_classification_action',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS recommended_action
FROM dwh.v_note_ml_prediction_features
WHERE id_note = 12345;  -- Replace with actual note ID

-- ============================================================================
-- 2. Batch Prediction: Multiple Notes
-- ============================================================================
-- Classify all new notes (not yet classified)

SELECT
  id_note,
  opened_dimension_id_date,
  pgml.predict(
    'note_classification_main_category',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS predicted_category,
  pgml.predict(
    'note_classification_specific_type',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS predicted_type,
  pgml.predict(
    'note_classification_action',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS recommended_action
FROM dwh.v_note_ml_prediction_features
WHERE id_note NOT IN (
  SELECT ntc.id_note FROM dwh.note_type_classifications AS ntc
)
LIMIT 1000;

-- ============================================================================
-- 3. Prediction with Confidence Scores
-- ============================================================================
-- Get prediction probabilities for confidence assessment

SELECT
  id_note,
  -- Prediction
  pgml.predict(
    'note_classification_main_category',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR AS predicted_category,
  -- Probabilities (returns JSON with all class probabilities)
  pgml.predict_proba(
    'note_classification_main_category',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level, user_contributor_type_id,
      day_of_week, hour_of_day, month, days_open
    ]
  ) AS category_probabilities
FROM dwh.v_note_ml_prediction_features
WHERE id_note = 12345;

-- Extract confidence from probabilities (requires JSON keys to match predicted class labels)
WITH scored AS (
  SELECT
    id_note,
    pgml.predict(
      'note_classification_main_category',
      ARRAY[
        comment_length, has_url_int, has_mention_int, hashtag_number,
        total_comments_on_note, hashtag_count, has_fire_keyword,
        has_air_keyword, has_access_keyword, has_campaign_keyword,
        has_fix_keyword, is_assisted_app, is_mobile_app,
        country_resolution_rate, country_avg_resolution_days,
        country_notes_health_score, user_response_time,
        user_total_notes, user_experience_level, user_contributor_type_id,
        day_of_week, hour_of_day, month, days_open
      ]
    )::VARCHAR AS predicted_category,
    pgml.predict_proba(
      'note_classification_main_category',
      ARRAY[
        comment_length, has_url_int, has_mention_int, hashtag_number,
        total_comments_on_note, hashtag_count, has_fire_keyword,
        has_air_keyword, has_access_keyword, has_campaign_keyword,
        has_fix_keyword, is_assisted_app, is_mobile_app,
        country_resolution_rate, country_avg_resolution_days,
        country_notes_health_score, user_response_time,
        user_total_notes, user_experience_level, user_contributor_type_id,
        day_of_week, hour_of_day, month, days_open
      ]
    ) AS category_probabilities
  FROM dwh.v_note_ml_prediction_features
  WHERE id_note = 12345
)

SELECT
  id_note,
  predicted_category,
  (category_probabilities ->> predicted_category)::NUMERIC AS confidence_score
FROM scored;

-- ============================================================================
-- 4. Integration with Dashboards: High-Priority Notes
-- ============================================================================
-- Get notes that need processing (high priority)

SELECT
  f.id_note,
  f.opened_dimension_id_date,
  d.date_id AS opened_date,
  c.country_name_en,
  u.username,
  pgml.predict(
    'note_classification_main_category',
    ARRAY[
      pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
      pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
      pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
      pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
      pf.country_resolution_rate, pf.country_avg_resolution_days,
      pf.country_notes_health_score, pf.user_response_time,
      pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
      pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
    ]
  )::VARCHAR AS predicted_category,
  pgml.predict(
    'note_classification_action',
    ARRAY[
      pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
      pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
      pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
      pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
      pf.country_resolution_rate, pf.country_avg_resolution_days,
      pf.country_notes_health_score, pf.user_response_time,
      pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
      pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
    ]
  )::VARCHAR AS recommended_action
FROM dwh.facts f
JOIN dwh.v_note_ml_prediction_features pf ON f.id_note = pf.id_note
JOIN dwh.dimension_days d ON f.opened_dimension_id_date = d.dimension_day_id
JOIN dwh.dimension_countries c ON f.dimension_id_country = c.dimension_country_id
JOIN dwh.dimension_users u ON f.opened_dimension_id_user = u.dimension_user_id
WHERE f.action_comment = 'opened'
  AND pgml.predict(
    'note_classification_main_category',
    ARRAY[
      pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
      pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
      pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
      pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
      pf.country_resolution_rate, pf.country_avg_resolution_days,
      pf.country_notes_health_score, pf.user_response_time,
      pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
      pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
    ]
  )::VARCHAR = 'contributes_with_change'
  AND pgml.predict(
    'note_classification_action',
    ARRAY[
      pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
      pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
      pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
      pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
      pf.country_resolution_rate, pf.country_avg_resolution_days,
      pf.country_notes_health_score, pf.user_response_time,
      pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
      pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
    ]
  )::VARCHAR = 'process'
ORDER BY f.opened_dimension_id_date DESC
LIMIT 50;

-- ============================================================================
-- 5. Create Helper Function for Predictions
-- ============================================================================
-- Function to simplify prediction calls

CREATE OR REPLACE FUNCTION dwh.predict_note_category_pgml(
  p_note_id INTEGER
)
RETURNS TABLE (
  id_note INTEGER,
  predicted_category VARCHAR,
  predicted_type VARCHAR,
  recommended_action VARCHAR,
  category_confidence NUMERIC,
  type_confidence NUMERIC,
  action_confidence NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_features RECORD;
  v_category VARCHAR;
  v_type VARCHAR;
  v_action VARCHAR;
  v_category_proba JSONB;
  v_type_proba JSONB;
  v_action_proba JSONB;
BEGIN
  -- Get features for the note
  SELECT * INTO v_features
  FROM dwh.v_note_ml_prediction_features
  WHERE id_note = p_note_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Note % not found in prediction features', p_note_id;
  END IF;

  -- Make predictions
  v_category := pgml.predict(
    'note_classification_main_category',
    ARRAY[
      v_features.comment_length, v_features.has_url_int, v_features.has_mention_int,
      v_features.hashtag_number, v_features.total_comments_on_note,
      v_features.hashtag_count, v_features.has_fire_keyword,
      v_features.has_air_keyword, v_features.has_access_keyword,
      v_features.has_campaign_keyword, v_features.has_fix_keyword,
      v_features.is_assisted_app, v_features.is_mobile_app,
      v_features.country_resolution_rate, v_features.country_avg_resolution_days,
      v_features.country_notes_health_score, v_features.user_response_time,
      v_features.user_total_notes, v_features.user_experience_level,
      v_features.user_contributor_type_id,
      v_features.day_of_week, v_features.hour_of_day,
      v_features.month, v_features.days_open
    ]
  )::VARCHAR;

  v_type := pgml.predict(
    'note_classification_specific_type',
    ARRAY[
      v_features.comment_length, v_features.has_url_int, v_features.has_mention_int,
      v_features.hashtag_number, v_features.total_comments_on_note,
      v_features.hashtag_count, v_features.has_fire_keyword,
      v_features.has_air_keyword, v_features.has_access_keyword,
      v_features.has_campaign_keyword, v_features.has_fix_keyword,
      v_features.is_assisted_app, v_features.is_mobile_app,
      v_features.country_resolution_rate, v_features.country_avg_resolution_days,
      v_features.country_notes_health_score, v_features.user_response_time,
      v_features.user_total_notes, v_features.user_experience_level,
      v_features.user_contributor_type_id,
      v_features.day_of_week, v_features.hour_of_day,
      v_features.month, v_features.days_open
    ]
  )::VARCHAR;

  v_action := pgml.predict(
    'note_classification_action',
    ARRAY[
      v_features.comment_length, v_features.has_url_int, v_features.has_mention_int,
      v_features.hashtag_number, v_features.total_comments_on_note,
      v_features.hashtag_count, v_features.has_fire_keyword,
      v_features.has_air_keyword, v_features.has_access_keyword,
      v_features.has_campaign_keyword, v_features.has_fix_keyword,
      v_features.is_assisted_app, v_features.is_mobile_app,
      v_features.country_resolution_rate, v_features.country_avg_resolution_days,
      v_features.country_notes_health_score, v_features.user_response_time,
      v_features.user_total_notes, v_features.user_experience_level,
      v_features.user_contributor_type_id,
      v_features.day_of_week, v_features.hour_of_day,
      v_features.month, v_features.days_open
    ]
  )::VARCHAR;

  -- Get probabilities for confidence scores
  v_category_proba := pgml.predict_proba(
    'note_classification_main_category',
    ARRAY[
      v_features.comment_length, v_features.has_url_int, v_features.has_mention_int,
      v_features.hashtag_number, v_features.total_comments_on_note,
      v_features.hashtag_count, v_features.has_fire_keyword,
      v_features.has_air_keyword, v_features.has_access_keyword,
      v_features.has_campaign_keyword, v_features.has_fix_keyword,
      v_features.is_assisted_app, v_features.is_mobile_app,
      v_features.country_resolution_rate, v_features.country_avg_resolution_days,
      v_features.country_notes_health_score, v_features.user_response_time,
      v_features.user_total_notes, v_features.user_experience_level,
      v_features.user_contributor_type_id,
      v_features.day_of_week, v_features.hour_of_day,
      v_features.month, v_features.days_open
    ]
  );

  -- Return results
  RETURN QUERY SELECT
    p_note_id,
    v_category,
    v_type,
    v_action,
    (v_category_proba ->> v_category)::NUMERIC AS category_confidence,
    (v_type_proba ->> v_type)::NUMERIC AS type_confidence,
    (v_action_proba ->> v_action)::NUMERIC AS action_confidence;
END;
$$;

COMMENT ON FUNCTION dwh.predict_note_category_pgml IS
  'Predict note classification using pgml models. Returns category, type, action, and confidence scores.';

-- Usage example:
-- SELECT * FROM dwh.predict_note_category_pgml(12345);

-- ============================================================================
-- 6. Integration with ETL: Automatic Classification
-- ============================================================================
-- Procedure to classify new notes automatically

CREATE OR REPLACE PROCEDURE dwh.classify_new_notes_pgml(
  p_batch_size INTEGER DEFAULT 100
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_processed INTEGER := 0;
BEGIN
  -- Insert predictions into classification table
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
    c.id_note,
    c.main_category,
    c.category_confidence,
    c.category_method,
    c.specific_type,
    c.type_confidence,
    c.type_method,
    c.recommended_action,
    c.action_confidence,
    c.action_method,
    CASE
      WHEN c.main_category = 'contributes_with_change'
           AND c.recommended_action = 'process'
      THEN 9
      WHEN c.recommended_action = 'needs_more_data'
      THEN 6
      WHEN c.recommended_action = 'close'
      THEN 3
      ELSE 5
    END AS priority_score,
    c.classification_version,
    c.classification_timestamp
  FROM (
    SELECT
      pf.id_note,
      (pgml.predict(
        'note_classification_main_category',
        ARRAY[
          pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
          pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
          pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
          pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
          pf.country_resolution_rate, pf.country_avg_resolution_days,
          pf.country_notes_health_score, pf.user_response_time,
          pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
          pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
        ]
      ))::VARCHAR AS main_category,
      0.8 AS category_confidence,
      'ml_based' AS category_method,
      (pgml.predict(
        'note_classification_specific_type',
        ARRAY[
          pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
          pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
          pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
          pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
          pf.country_resolution_rate, pf.country_avg_resolution_days,
          pf.country_notes_health_score, pf.user_response_time,
          pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
          pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
        ]
      ))::VARCHAR AS specific_type,
      0.75 AS type_confidence,
      'ml_based' AS type_method,
      (pgml.predict(
        'note_classification_action',
        ARRAY[
          pf.comment_length, pf.has_url_int, pf.has_mention_int, pf.hashtag_number,
          pf.total_comments_on_note, pf.hashtag_count, pf.has_fire_keyword,
          pf.has_air_keyword, pf.has_access_keyword, pf.has_campaign_keyword,
          pf.has_fix_keyword, pf.is_assisted_app, pf.is_mobile_app,
          pf.country_resolution_rate, pf.country_avg_resolution_days,
          pf.country_notes_health_score, pf.user_response_time,
          pf.user_total_notes, pf.user_experience_level, pf.user_contributor_type_id,
          pf.day_of_week, pf.hour_of_day, pf.month, pf.days_open
        ]
      ))::VARCHAR AS recommended_action,
      0.8 AS action_confidence,
      'ml_based' AS action_method,
      'pgml_v1.0' AS classification_version,
      CURRENT_TIMESTAMP AS classification_timestamp
    FROM dwh.v_note_ml_prediction_features pf
    WHERE pf.id_note NOT IN (
      SELECT ntc.id_note FROM dwh.note_type_classifications AS ntc
    )
    LIMIT p_batch_size
  ) AS c;

  GET DIAGNOSTICS v_processed = ROW_COUNT;

  RAISE NOTICE 'Classified % notes', v_processed;
END;
$$;

COMMENT ON PROCEDURE dwh.classify_new_notes_pgml IS
  'Automatically classify new notes using pgml models. Processes notes in batches.';

-- Usage:
-- CALL dwh.classify_new_notes_pgml(1000);
