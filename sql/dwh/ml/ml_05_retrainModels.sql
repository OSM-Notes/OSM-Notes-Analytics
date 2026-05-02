-- Retrain pgml models for note classification
-- This script retrains models with updated data
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-27
-- Purpose: Retrain ML models with fresh data

\set ON_ERROR_STOP on

-- ============================================================================
-- Prerequisites
-- ============================================================================
-- 1. pgml extension must be installed and enabled
-- 2. Narrow training views from ml_01_setupPgML.sql (dwh.v_note_ml_train_*); wide v_note_ml_training_features is exploratory only.
-- 3. Sufficient new training data (recommended: 10%+ new resolved notes since last training)

-- ============================================================================
-- Check Training Data Freshness
-- ============================================================================

-- Check when models were last trained (pgml 2.x: timestamps live on pgml.models)
SELECT
  p.name AS project_name,
  MAX(m.created_at) AS last_trained_at,
  NOW() - MAX(m.created_at) AS age
FROM pgml.models m
JOIN pgml.projects p ON p.id = m.project_id
WHERE p.name LIKE 'note_classification%'
GROUP BY p.name;

-- Check how many new training samples are available
SELECT
  COUNT(*) AS total_training_samples,
  COUNT(*) FILTER (WHERE opened_dimension_id_date > (
    SELECT MAX(m.created_at) - INTERVAL '30 days'
    FROM pgml.models m
    JOIN pgml.projects p ON p.id = m.project_id
    WHERE p.name = 'note_classification_main_category'
  )) AS new_samples_last_30_days
FROM dwh.v_note_ml_training_features
WHERE main_category IS NOT NULL;

-- ============================================================================
-- Retrain Level 1 Model: Main Category (2 classes)
-- ============================================================================

SELECT * FROM pgml.train(
  project_name => 'note_classification_main_category',
  task => 'classification',
  relation_name => 'dwh.v_note_ml_train_main_category',
  y_column_name => 'main_category',
  algorithm => 'lightgbm',
  hyperparams => '{
    "n_estimators": 100,
    "num_leaves": 63,
    "learning_rate": 0.1,
    "verbosity": -1
  }'::JSONB,
  test_size => 0.2,
  test_sampling => 'random'
);

-- ============================================================================
-- Retrain Level 2 Model: Specific Type (18+ classes)
-- ============================================================================

SELECT * FROM pgml.train(
  project_name => 'note_classification_specific_type',
  task => 'classification',
  relation_name => 'dwh.v_note_ml_train_specific_type',
  y_column_name => 'specific_type',
  algorithm => 'xgboost',
  hyperparams => '{
    "n_estimators": 200,
    "max_depth": 8,
    "learning_rate": 0.05,
    "class_weight": "balanced"
  }'::JSONB,
  test_size => 0.2,
  test_sampling => 'random'
);

-- ============================================================================
-- Retrain Level 3 Model: Action Recommendation (3 classes)
-- ============================================================================

SELECT * FROM pgml.train(
  project_name => 'note_classification_action',
  task => 'classification',
  relation_name => 'dwh.v_note_ml_train_action',
  y_column_name => 'recommended_action',
  algorithm => 'xgboost',
  hyperparams => '{
    "n_estimators": 150,
    "max_depth": 7,
    "learning_rate": 0.1
  }'::JSONB,
  test_size => 0.2,
  test_sampling => 'random'
);

-- ============================================================================
-- Compare Old vs New Model Performance
-- ============================================================================

WITH model_comparison AS (
  SELECT
    p.name AS project_name,
    m.created_at,
    m.metrics ->> 'accuracy' AS accuracy,
    m.metrics ->> 'f1' AS f1_score,
    ROW_NUMBER() OVER (PARTITION BY p.name ORDER BY m.created_at DESC) AS rn
  FROM pgml.models m
  JOIN pgml.projects p ON p.id = m.project_id
  WHERE p.name LIKE 'note_classification%'
)

SELECT
  project_name,
  MAX(CASE WHEN rn = 1 THEN accuracy END) AS new_accuracy,
  MAX(CASE WHEN rn = 2 THEN accuracy END) AS previous_accuracy,
  ROUND(
    ((MAX(CASE WHEN rn = 1 THEN accuracy::NUMERIC END)
      - MAX(CASE WHEN rn = 2 THEN accuracy::NUMERIC END)) * 100)::NUMERIC,
    2
  ) AS accuracy_change_pct
FROM model_comparison
GROUP BY project_name
ORDER BY project_name;

-- ============================================================================
-- Notes
-- ============================================================================
-- - Retraining may take several minutes to hours depending on data size
-- - pgml automatically deploys the best model (based on test metrics)
-- - Old models are kept for comparison but not used for predictions
-- - Monitor model performance over time to detect drift
-- - Consider retraining when:
--   * 10%+ new training data available
--   * Model accuracy drops significantly
--   * Data distribution changes (e.g., new note types emerge)
--   * Monthly/quarterly schedule (recommended)
