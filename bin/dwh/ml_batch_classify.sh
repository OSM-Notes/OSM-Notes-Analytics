#!/bin/bash
#
# Batch note classification using trained pgml models (dwh.predict_note_classification_pgml).
# Run after ETL/datamarts and training; safe to schedule from cron.
#
# Prerequisites: PostgreSQL 14+, pgml extension, models trained. If dwh.predict_note_classification_pgml
# is missing, this script applies sql/dwh/ml/ml_03_predictWithPgML.sql once (DDL on DWH DB).
# See: sql/dwh/ml/README.md and README.md Quick Start Step 9.
#
# Usage:
#   ./bin/dwh/ml_batch_classify.sh
#   ML_BATCH_SIZE=1000 ./bin/dwh/ml_batch_classify.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2026-05-02

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ML_DIR="${PROJECT_ROOT}/sql/dwh/ml"

if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/etc/properties.sh"
fi
if [[ -f "${PROJECT_ROOT}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/etc/properties.sh.local"
fi

# DBNAME_DWH may be readonly after sourcing etc/properties.sh (declare -r).
DWH_DB="${DBNAME_DWH:-notes_dwh}"
PSQL_CMD="${PSQL_CMD:-psql}"
ML_BATCH_SIZE="${ML_BATCH_SIZE:-500}"

if [[ -f "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh"
else
 __logi() { echo "[INFO] $*"; }
 __loge() { echo "[ERROR] $*"; }
fi

# Reject any non-integer or out-of-range value so it cannot be injected into -c SQL.
if ! [[ "${ML_BATCH_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
 __loge "ML_BATCH_SIZE must be a positive integer (digits only, no leading zeros)"
 exit 1
fi
if ((ML_BATCH_SIZE > 1000000)); then
 __loge "ML_BATCH_SIZE must be at most 1000000"
 exit 1
fi

if ! "${PSQL_CMD}" -d "${DWH_DB}" -t -Aqc "SELECT 1 FROM pg_extension WHERE extname = 'pgml';" 2> /dev/null | grep -qx 1; then
 __loge "pgml extension is not enabled in ${DWH_DB}. Install and enable per sql/dwh/ml/README.md"
 exit 1
fi

_prediction_function_installed() {
 "${PSQL_CMD}" -d "${DWH_DB}" -t -Aqc "
SELECT 1 FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'dwh' AND p.proname = 'predict_note_classification_pgml'
LIMIT 1;
" 2> /dev/null | grep -qx 1
}

if ! _prediction_function_installed; then
 __logi "Applying prediction routine (${ML_DIR}/ml_03_predictWithPgML.sql)..."
 ml03_log="$(mktemp)"
 if ! "${PSQL_CMD}" -d "${DWH_DB}" -v ON_ERROR_STOP=1 \
  -f "${ML_DIR}/ml_03_predictWithPgML.sql" > "${ml03_log}" 2>&1; then
  __loge "Failed to apply ml_03_predictWithPgML.sql"
  cat "${ml03_log}" >&2
  rm -f "${ml03_log}"
  exit 1
 fi
 rm -f "${ml03_log}"
fi

if ! _prediction_function_installed; then
 __loge "Function dwh.predict_note_classification_pgml is still missing after ml_03. Manual apply:"
 __loge "  ${PSQL_CMD} -d ${DWH_DB} -v ON_ERROR_STOP=1 -f ${ML_DIR}/ml_03_predictWithPgML.sql"
 __loge "See sql/dwh/ml/README.md (ml_01, trained models, and compatible pgml)."
 exit 1
fi

__logi "Batch classification: database=${DWH_DB} ML_BATCH_SIZE=${ML_BATCH_SIZE}"
"${PSQL_CMD}" -d "${DWH_DB}" -v ON_ERROR_STOP=1 \
 -c "SELECT * FROM dwh.predict_note_classification_pgml(${ML_BATCH_SIZE});"
