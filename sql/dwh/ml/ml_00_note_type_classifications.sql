-- ML classification storage (rule-based and/or pgml batch output).
-- Included from ml_01_setupPgML.sql and ml_03_predictWithPgML.sql (idempotent).
--
-- Author: OSM Notes Analytics Project
-- Date: 2026-05-02

CREATE TABLE IF NOT EXISTS dwh.note_type_classifications (
  classification_id BIGSERIAL PRIMARY KEY,
  id_note INTEGER NOT NULL,

  main_category VARCHAR(255) NOT NULL,
  category_confidence NUMERIC(9, 4) NOT NULL,
  category_method VARCHAR(32) NOT NULL,

  specific_type VARCHAR(255) NOT NULL,
  type_confidence NUMERIC(9, 4) NOT NULL,
  type_probabilities JSONB,
  type_method VARCHAR(32) NOT NULL,

  recommended_action VARCHAR(255) NOT NULL,
  action_confidence NUMERIC(9, 4) NOT NULL,
  action_method VARCHAR(32) NOT NULL,
  priority_score INTEGER NOT NULL,

  classification_factors JSONB,
  similar_notes INTEGER[],
  estimated_resolution_time INTEGER,

  classification_version VARCHAR(128),
  classification_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT uq_note_type_classifications_note_version UNIQUE (id_note, classification_version)
);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_note
  ON dwh.note_type_classifications (id_note);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_category
  ON dwh.note_type_classifications (main_category);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_type
  ON dwh.note_type_classifications (specific_type);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_action
  ON dwh.note_type_classifications (recommended_action);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_priority
  ON dwh.note_type_classifications (priority_score DESC);

CREATE INDEX IF NOT EXISTS idx_note_type_classifications_method
  ON dwh.note_type_classifications (type_method);

COMMENT ON TABLE dwh.note_type_classifications IS
  'Unified note classification results (rules, hashtags, pgml batch, etc.). See ML_Implementation_Plan.md';
