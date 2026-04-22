#!/usr/bin/env bash
#
# Batch note classification using trained pgml models (dwh.predict_note_classification_pgml).
# Run after ETL/datamarts and training; safe to schedule from cron.
#
# Prerequisites: PostgreSQL 14+, pgml extension, models trained, and ml_03_predictWithPgML.sql applied.
# See: sql/dwh/ml/README.md and README.md Quick Start Step 9.
#
# Usage:
#   ./bin/dwh/ml_batch_classify.sh
#   ML_BATCH_SIZE=1000 ./bin/dwh/ml_batch_classify.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-22

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ -f "${PROJECT_ROOT}/etc/properties.sh" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/etc/properties.sh"
fi
if [[ -f "${PROJECT_ROOT}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/etc/properties.sh.local"
fi

DBNAME_DWH="${DBNAME_DWH:-notes_dwh}"
PSQL_CMD="${PSQL_CMD:-psql}"
ML_BATCH_SIZE="${ML_BATCH_SIZE:-500}"

if [[ -f "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh" ]]; then
 # shellcheck disable=SC1091
 source "${PROJECT_ROOT}/lib/osm-common/bash_logger.sh"
else
 __logi() { echo "[INFO] $*"; }
 __loge() { echo "[ERROR] $*"; }
fi

if ! "${PSQL_CMD}" -d "${DBNAME_DWH}" -t -Aqc "SELECT 1 FROM pg_extension WHERE extname = 'pgml';" 2> /dev/null | grep -qx 1; then
 __loge "pgml extension is not enabled in ${DBNAME_DWH}. Install and enable per sql/dwh/ml/README.md"
 exit 1
fi

__logi "Batch classification: database=${DBNAME_DWH} ML_BATCH_SIZE=${ML_BATCH_SIZE}"
"${PSQL_CMD}" -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
 -c "SELECT * FROM dwh.predict_note_classification_pgml(${ML_BATCH_SIZE});"
