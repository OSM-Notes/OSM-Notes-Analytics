#!/bin/bash
#
# Intelligent ML model training/retraining script
# Automatically detects system state and decides what to do:
# - No data → do nothing
# - Facts + dimensions ready → initial training (basic features)
# - Datamarts populated → full training (all features)
# - Models exist → retraining (if needed)
#
# Author: Andres Gomez (AngocA)
# Version: 2026-05-02

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source logging and common functions
if [[ -f "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh" ]]; then
 source "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh"
else
 # Fallback logging
 __logi() { echo "[INFO] $*"; }
 __logw() { echo "[WARN] $*"; }
 __loge() { echo "[ERROR] $*"; }
fi

# Database configuration (DBNAME_DWH may be readonly if sourced from etc/properties.sh)
DWH_DB="${DBNAME_DWH:-notes_dwh}"
PSQL_CMD="${PSQL_CMD:-psql}"

# ML scripts directory
ML_DIR="${PROJECT_ROOT}/sql/dwh/ml"

# Minimum training samples required
MIN_TRAINING_SAMPLES=1000

# ============================================================================
# Functions
# ============================================================================

show_help() {
 cat << EOF
Intelligent ML model training/retraining script

Automatically detects system state and decides what to do:
- No data → do nothing (exit silently)
- Facts + dimensions ready → initial training (basic features)
- Datamarts populated → full training (all features)
- Models exist → retraining (if needed)

Usage: $0

This script has no options - it's fully automatic. Just run it from cron.

Examples:
  # Run manually
  $0

  # Add to cron (monthly)
  0 2 1 * * /path/to/OSM-Notes-Analytics/bin/dwh/ml_retrain.sh >> /var/log/ml-retrain.log 2>&1

EOF
}

check_pgml_extension() {
 if ! "${PSQL_CMD}" -d "${DWH_DB}" -t -c "SELECT 1 FROM pg_extension WHERE extname = 'pgml';" | grep -q 1; then
  __loge "pgml extension is not enabled in database ${DWH_DB}"
  __loge "Run: psql -d ${DWH_DB} -c 'CREATE EXTENSION IF NOT EXISTS pgml;'"
  return 1
 fi
 return 0
}

# Narrow views expose 24 feature columns plus one label; must stay in sync with ml_01_setupPgML.sql.
readonly _ML_NARROW_TRAIN_VIEW_COLUMNS=25

validate_pgml_train_scripts_use_narrow_relations() {
 local f
 for f in "${ML_DIR}/ml_02_trainPgMLModels.sql" "${ML_DIR}/ml_05_retrainModels.sql"; do
  if [[ ! -f "${f}" ]]; then
   __loge "Missing training SQL: ${f}"
   return 1
  fi
  if grep -Eq "relation_name[[:space:]]*=>[[:space:]]*'dwh\\.v_note_ml_training_features'" "${f}"; then
   __loge "$(basename "${f}") uses wide relation_name 'dwh.v_note_ml_training_features' in pgml.train()."
   __loge "That matches pgML Rust panics (\`Option::unwrap()\` on None) with ~29 columns (ids/dates)."
   __loge "Update this repo copy: pgml.train must use dwh.v_note_ml_train_main_category (and sibling views)."
   return 1
  fi
 done
 return 0
}

validate_narrow_ml_train_views_deployed() {
 local v cols
 for v in v_note_ml_train_main_category v_note_ml_train_specific_type v_note_ml_train_action; do
  cols=$("${PSQL_CMD}" -d "${DWH_DB}" -tAc "
			SELECT COUNT(*)::TEXT
			FROM information_schema.columns
			WHERE table_schema = 'dwh'
			  AND table_name = '${v}';
		" 2> /dev/null | tr -d '[:space:]' || echo "0")

  if [[ "${cols}" != "${_ML_NARROW_TRAIN_VIEW_COLUMNS}" ]]; then
   __loge "dwh.${v} column count is ${cols}, expected ${_ML_NARROW_TRAIN_VIEW_COLUMNS} (wide/stale ML views?)."
   __loge "Re-run ml_01_setupPgML.sql from the current repo, or git pull OSM-Notes-Analytics."
   return 1
  fi
 done
 return 0
}

ensure_training_view() {
 # Always apply ml_01: views are CREATE OR REPLACE; otherwise a stale DB keeps an old
 # definition (e.g. after fixing SQL on disk) and training fails while the file looks correct.
 __logi "Applying ML setup (views, ${ML_DIR}/ml_01_setupPgML.sql)..."
 local setup_log
 setup_log="$(mktemp)"
 if ! "${PSQL_CMD}" -d "${DWH_DB}" -v ON_ERROR_STOP=1 \
  -f "${ML_DIR}/ml_01_setupPgML.sql" > "${setup_log}" 2>&1; then
  __loge "Failed to apply ML setup / training views"
  cat "${setup_log}" >&2
  rm -f "${setup_log}"
  return 1
 fi
 rm -f "${setup_log}"
 return 0
}

check_core_tables() {
 # Check if facts and dimensions exist and have data
 local facts_count
 facts_count=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM dwh.facts
		WHERE action_comment = 'opened'
		  AND closed_dimension_id_date IS NOT NULL
		  AND comment_length > 0;
	" 2> /dev/null | tr -d ' ' || echo "0")

 if [[ ${facts_count} -lt ${MIN_TRAINING_SAMPLES} ]]; then
  return 1
 fi

 # Check dimensions exist
 if ! "${PSQL_CMD}" -d "${DWH_DB}" -t -c "SELECT 1 FROM dwh.dimension_days LIMIT 1;" > /dev/null 2>&1; then
  return 1
 fi

 if ! "${PSQL_CMD}" -d "${DWH_DB}" -t -c "SELECT 1 FROM dwh.dimension_applications LIMIT 1;" > /dev/null 2>&1; then
  return 1
 fi

 return 0
}

check_datamarts_populated() {
 # Check if datamarts exist and have meaningful data
 local countries_count
 local users_count

 countries_count=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM dwh.datamartcountries
		WHERE resolution_rate IS NOT NULL;
	" 2> /dev/null | tr -d ' ' || echo "0")

 users_count=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM dwh.datamartusers
		WHERE user_response_time IS NOT NULL;
	" 2> /dev/null | tr -d ' ' || echo "0")

 # Consider datamarts populated if we have at least some data
 if [[ ${countries_count} -gt 0 ]] && [[ ${users_count} -gt 0 ]]; then
  return 0
 fi

 return 1
}

check_models_exist() {
 # Check if any models are already trained
 local model_count
 model_count=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM pgml.deployed_models
		WHERE project_name LIKE 'note_classification%';
	" 2> /dev/null | tr -d ' ' || echo "0")

 if [[ ${model_count} -gt 0 ]]; then
  return 0
 fi

 return 1
}

check_retraining_needed() {
 # Check if retraining is needed (10%+ new data or 30+ days old)
 local days_since_training
 local new_samples
 local total_samples
 local new_percentage

 days_since_training=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COALESCE(EXTRACT(DAY FROM NOW() - MAX(created_at))::INTEGER, 999)
		FROM pgml.deployed_models
		WHERE project_name LIKE 'note_classification%';
	" 2> /dev/null | tr -d ' ' || echo "999")

 if [[ ${days_since_training} -ge 30 ]]; then
  return 0
 fi

 # Check for new training data
 new_samples=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM dwh.v_note_ml_training_features
		WHERE main_category IS NOT NULL
		  AND opened_dimension_id_date > (
		    SELECT MAX(created_at) - INTERVAL '30 days'
		    FROM pgml.deployed_models
		    WHERE project_name = 'note_classification_main_category'
		  );
	" 2> /dev/null | tr -d ' ' || echo "0")

 total_samples=$("${PSQL_CMD}" -d "${DWH_DB}" -t -c "
		SELECT COUNT(*)
		FROM dwh.v_note_ml_training_features
		WHERE main_category IS NOT NULL;
	" 2> /dev/null | tr -d ' ' || echo "0")

 if [[ ${total_samples} -gt 0 ]]; then
  new_percentage=$((new_samples * 100 / total_samples))
 else
  new_percentage=0
 fi

 if [[ ${new_percentage} -ge 10 ]]; then
  return 0
 fi

 return 1
}

train_models() {
 local script_file="$1"
 local training_type="$2"

 __logi "Starting ${training_type}..."

 local start_time
 start_time=$(date +%s)

 local train_log
 train_log="$(mktemp)"

 if "${PSQL_CMD}" -d "${DWH_DB}" -v ON_ERROR_STOP=1 -f "${script_file}" \
  > "${train_log}" 2>&1; then
  rm -f "${train_log}"
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  __logi "✅ ${training_type} completed successfully in ${minutes}m ${seconds}s"

  # Show model metrics
  __logi "Model metrics:"
  "${PSQL_CMD}" -d "${DWH_DB}" -c "
			SELECT
				project_name,
				ROUND((metrics->>'accuracy')::numeric * 100, 2) as accuracy_pct,
				ROUND((metrics->>'f1')::numeric * 100, 2) as f1_pct,
				created_at
			FROM pgml.deployed_models
			WHERE project_name LIKE 'note_classification%'
			ORDER BY created_at DESC
			LIMIT 3;
		" 2> /dev/null || true

  return 0
 else
  __loge "❌ ${training_type} failed"
  __loge "psql output (first failure stops the script when ON_ERROR_STOP=1):"
  cat "${train_log}" >&2
  rm -f "${train_log}"
  return 1
 fi
}

# ============================================================================
# Main Decision Logic
# ============================================================================

main() {
 # Parse arguments (only --help)
 if [[ $# -gt 0 ]]; then
  case $1 in
  --help | -h)
   show_help
   exit 0
   ;;
  *)
   __loge "Unknown option: $1 (use --help for usage)"
   exit 1
   ;;
  esac
 fi

 __logi "ML Model Training Script (Intelligent Mode)"
 __logi "Database: ${DWH_DB}"

 # Step 1: Check pgml extension
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! check_pgml_extension; then
  __loge "Prerequisites not met. Exiting."
  exit 1
 fi

 # Step 2: Fail fast if this checkout still points pgml.train at the wide relation
 # shellcheck disable=SC2310
 if ! validate_pgml_train_scripts_use_narrow_relations; then
  __loge "Fix training SQL scripts (or update the repo). Exiting."
  exit 1
 fi

 # Step 3: Ensure training view exists
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! ensure_training_view; then
  __loge "Failed to setup training views. Exiting."
  exit 1
 fi

 # Step 4: Confirm narrow pgML relations exist after ml_01
 # shellcheck disable=SC2310
 if ! validate_narrow_ml_train_views_deployed; then
  __loge "ML views do not match expected schema. Exiting."
  exit 1
 fi

 # Step 5: Check if we have enough data
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! check_core_tables; then
  # No data or insufficient data - exit silently (normal for early stages)
  exit 0
 fi

 # Step 6: Check current state and decide what to do
 local has_datamarts=false
 local has_models=false

 # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
 if check_datamarts_populated; then
  has_datamarts=true
  __logi "✅ Datamarts are populated (will use enhanced features)"
 fi

 # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
 if check_models_exist; then
  has_models=true
  __logi "✅ Models already exist (checking if retraining needed)"
 fi

 # Decision tree:
 if [[ "${has_models}" == true ]]; then
  # Models exist - check if retraining is needed
  # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
  if check_retraining_needed; then
   __logi "Retraining needed - starting retraining..."
   # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
   if train_models "${ML_DIR}/ml_05_retrainModels.sql" "Model retraining"; then
    __logi "✅ Retraining completed successfully"
    exit 0
   else
    __loge "❌ Retraining failed"
    exit 1
   fi
  else
   __logi "Models are up to date - no retraining needed"
   exit 0
  fi
 elif [[ "${has_datamarts}" == true ]]; then
  # No models but datamarts ready - full initial training
  __logi "Datamarts ready - starting full initial training..."
  # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
  if train_models "${ML_DIR}/ml_02_trainPgMLModels.sql" "Full initial training"; then
   __logi "✅ Full training completed successfully"
   exit 0
  else
   __loge "❌ Full training failed"
   exit 1
  fi
 else
  # No models, no datamarts - basic initial training
  __logi "Core tables ready (datamarts not yet populated) - starting basic training..."
  __logw "Note: Training with basic features. Re-train later when datamarts are populated for better accuracy."
  # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
  if train_models "${ML_DIR}/ml_02_trainPgMLModels.sql" "Basic initial training"; then
   __logi "✅ Basic training completed successfully"
   exit 0
  else
   __loge "❌ Basic training failed"
   exit 1
  fi
 fi
}

main "$@"
