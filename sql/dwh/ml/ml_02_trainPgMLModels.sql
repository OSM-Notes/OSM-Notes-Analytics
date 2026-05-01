-- Train pgml models for note classification
-- This script trains hierarchical classification models using pgml
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20
-- Purpose: Train ML models for note classification

\set ON_ERROR_STOP on

-- ============================================================================
-- Prerequisites
-- ============================================================================
-- 1. pgml extension must be installed (see ml_01_setupPgML.sql)
-- 2. Narrow training relations and full feature view (see ml_01_setupPgML.sql):
--    dwh.v_note_ml_train_main_category, v_note_ml_train_specific_type, v_note_ml_train_action
-- 3. Sufficient training data (minimum 1000+ notes per class recommended)

-- ============================================================================
-- 1. Train Level 1 Model: Main Category (2 classes)
-- ============================================================================
-- Predicts: contributes_with_change vs doesnt_contribute

SELECT * FROM pgml.train(
  project_name => 'note_classification_main_category',
  task => 'classification',
  relation_name => 'dwh.v_note_ml_train_main_category',
  y_column_name => 'main_category',
  algorithm => 'xgboost',  -- Gradient boosting for good performance
  hyperparams => '{
    "n_estimators": 100,
    "max_depth": 6,
    "learning_rate": 0.1
  }'::jsonb,
  test_size => 0.2,  -- 20% for testing
  test_sampling => 'random'
);

-- Check training results
SELECT
  project_name,
  algorithm,
  status,
  created_at,
  metrics
FROM pgml.deployed_models
WHERE project_name = 'note_classification_main_category'
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- 2. Train Level 2 Model: Specific Type (18+ classes)
-- ============================================================================
-- Predicts: adds_to_map, modifies_map, personal_data, empty, etc.

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
    "class_weight": "balanced"  -- Handle class imbalance
  }'::jsonb,
  test_size => 0.2,
  test_sampling => 'random'
);

-- Check training results
SELECT
  project_name,
  algorithm,
  status,
  created_at,
  metrics
FROM pgml.deployed_models
WHERE project_name = 'note_classification_specific_type'
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- 3. Train Level 3 Model: Action Recommendation (3 classes)
-- ============================================================================
-- Predicts: process, close, needs_more_data

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
  }'::jsonb,
  test_size => 0.2,
  test_sampling => 'random'
);

-- Check training results
SELECT
  project_name,
  algorithm,
  status,
  created_at,
  metrics
FROM pgml.deployed_models
WHERE project_name = 'note_classification_action'
ORDER BY created_at DESC
LIMIT 1;

-- ============================================================================
-- 4. View All Trained Models
-- ============================================================================

SELECT
  project_name,
  algorithm,
  status,
  created_at,
  metrics ->> 'accuracy' AS accuracy,
  metrics ->> 'f1' AS f1_score,
  metrics ->> 'precision' AS precision,
  metrics ->> 'recall' AS recall
FROM pgml.deployed_models
WHERE project_name LIKE 'note_classification%'
ORDER BY created_at DESC;

-- ============================================================================
-- 5. Compare Model Performance
-- ============================================================================

WITH model_metrics AS (
  SELECT
    project_name,
    algorithm,
    created_at,
    metrics ->> 'accuracy' AS accuracy,
    metrics ->> 'f1' AS f1_score,
    metrics ->> 'precision' AS precision,
    metrics ->> 'recall' AS recall
  FROM pgml.deployed_models
  WHERE project_name LIKE 'note_classification%'
)

SELECT
  project_name,
  ROUND((accuracy::numeric) * 100, 2) AS accuracy_pct,
  ROUND((f1_score::numeric) * 100, 2) AS f1_pct,
  ROUND((precision::numeric) * 100, 2) AS precision_pct,
  ROUND((recall::numeric) * 100, 2) AS recall_pct,
  created_at
FROM model_metrics
ORDER BY project_name ASC, created_at DESC;

-- ============================================================================
-- Notes
-- ============================================================================
-- - Training may take several minutes depending on data size
-- - Monitor training progress in pgml.training_runs table
-- - Best models are automatically deployed
-- - Can retrain with different hyperparameters for better performance
-- - Consider class weights for imbalanced datasets
