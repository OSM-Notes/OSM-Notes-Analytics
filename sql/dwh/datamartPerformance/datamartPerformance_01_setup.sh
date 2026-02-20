#!/bin/bash

# Setup script for datamart performance monitoring.
# Creates the performance log table.
#
# Author: Andres Gomez (AngocA)
# Version: 2025-12-14

set -euo pipefail

# Base directory
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." &> /dev/null && pwd)"

# Load properties if available
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"
fi

# SQL file
CREATE_TABLE_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_11_createTable.sql"

# Database name (default from properties or environment)
DBNAME="${DBNAME_DWH:-${DBNAME:-notes_dwh}}"

echo "Creating datamart performance log table..."
echo "Database: ${DBNAME}"
echo "SQL file: ${CREATE_TABLE_FILE}"

psql -d "${DBNAME}" -v ON_ERROR_STOP=1 -f "${CREATE_TABLE_FILE}"

echo "✅ Performance log table created successfully!"
