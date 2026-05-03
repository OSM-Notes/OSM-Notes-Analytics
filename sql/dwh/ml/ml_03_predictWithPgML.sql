-- Deploy PostgresML prediction objects for DWH batch classification.
-- Used by bin/dwh/ml_batch_classify.sh and bin/dwh/ml_retrain.sh (apply_ml03).
--
-- Applies: dwh.note_type_classifications DDL (via \ir), dwh.note_ml_feature_vector,
-- dwh.predict_note_classification_pgml (batch INSERT into classifications).
--
-- Ad-hoc SELECT / sample INSERT examples live in ml_03_predict_demo_queries.sql (manual only).
-- Running pgml.predict over large parallel scans during this deploy hit:
--   ERROR: cannot assign transaction IDs during a parallel operation
-- on some PostgreSQL + pgml builds, so this file intentionally runs no prediction queries.
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20

\ir ml_00_note_type_classifications.sql
\ir ml_00_note_ml_feature_vector.sql

-- ============================================================================
-- Batch prediction function (bin/dwh/ml_batch_classify.sh)
-- ============================================================================

CREATE OR REPLACE FUNCTION dwh.predict_note_classification_pgml(
  p_batch_size INTEGER DEFAULT 100
)
RETURNS TABLE(
  notes_processed INTEGER,
  notes_with_high_confidence INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_processed INTEGER := 0;
  v_limit INTEGER;
BEGIN
  -- Discourage parallel plans for the INSERT...SELECT scan; pgml internal work may need XIDs.
  PERFORM set_config('max_parallel_workers_per_gather', '0', true);
  PERFORM set_config('parallel_setup_cost', '1000000000000', true);
  PERFORM set_config('parallel_tuple_cost', '1000000000000', true);
  PERFORM set_config('parallel_leader_participation', 'off', true);

  v_limit := COALESCE(NULLIF(p_batch_size, 0), 100);
  IF v_limit < 1 THEN
    v_limit := 1;
  END IF;

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
    LIMIT v_limit
  ) AS pred;

  GET DIAGNOSTICS v_processed = ROW_COUNT;

  -- Second column: intentionally 0 until we count high-confidence rows via pgml.predict_proba.
  RETURN QUERY SELECT v_processed, 0::INTEGER;
END;
$$;

COMMENT ON FUNCTION dwh.predict_note_classification_pgml IS
  'Batch-classify notes with pgml (same 24-feature order as dwh.note_ml_feature_vector / train '
  'narrow views). Returns (notes_processed, notes_with_high_confidence). Second column reserved '
  'for future pgml.predict_proba threshold counts. Interactive examples: '
  'sql/dwh/ml/ml_03_predict_demo_queries.sql.';
