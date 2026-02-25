#!/bin/bash

# Copy base tables from Ingestion DB to Analytics DB for initial load.
# This script is part of the hybrid strategy: copy tables for initial load,
# then use Foreign Data Wrappers for incremental processing.
#
# After DWH population, these tables will be dropped by dropCopiedBaseTables.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2025-12-29

set -euo pipefail

# Base directory for the project.
# Allow SCRIPT_BASE_DIRECTORY to be set externally (e.g., by tests)
declare SCRIPT_BASE_DIRECTORY
if [[ -z "${SCRIPT_BASE_DIRECTORY:-}" ]]; then
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
fi
readonly SCRIPT_BASE_DIRECTORY

# Load logger
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/bash_logger.sh" ]]; then
 source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/bash_logger.sh"
else
 # Minimal logger if file doesn't exist
 __logi() { echo "[INFO] $*"; }
 __loge() { echo "[ERROR] $*" >&2; }
 __logw() { echo "[WARN] $*"; }
 __log_start() { echo "[START]"; }
 __log_finish() { echo "[FINISH]"; }
fi

# Save original state of user variables before loading properties
# This allows tests to unset them for peer authentication
USER_INGESTION_WAS_UNSET=false
USER_DWH_WAS_UNSET=false
if [[ -z "${DB_USER_INGESTION+x}" ]]; then
 USER_INGESTION_WAS_UNSET=true
fi
if [[ -z "${DB_USER_DWH+x}" ]]; then
 USER_DWH_WAS_UNSET=true
fi

# Load properties (handle missing file gracefully for testing)
# shellcheck disable=SC1091
set +e
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh" ]]; then
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh" 2> /dev/null || true
fi
set -e

# Load local properties if they exist
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local" 2> /dev/null || true
fi

# Database configuration
# Use explicit database names - no fallback to avoid confusion
INGESTION_DB="${DBNAME_INGESTION:-notes}"
ANALYTICS_DB="${DBNAME_DWH:-notes_dwh}"
# Only set user if explicitly provided (allows peer authentication when not set)
# If variables were unset before loading properties, restore empty state for peer auth
if [[ "${USER_INGESTION_WAS_UNSET}" == "true" ]]; then
 INGESTION_USER=""
else
 INGESTION_USER="${DB_USER_INGESTION:-}"
fi
if [[ "${USER_DWH_WAS_UNSET}" == "true" ]]; then
 ANALYTICS_USER=""
else
 ANALYTICS_USER="${DB_USER_DWH:-}"
fi

# Helper function to build psql command array
build_psql_array() {
 local dbname="$1"
 local dbuser="${2:-}"
 local -n psql_array="$3" # nameref to array

 psql_array=()
 # Use CI/CD environment variables if available
 if [[ -n "${TEST_DBHOST:-}" ]] || [[ -n "${PGHOST:-}" ]]; then
  psql_array+=(-h "${TEST_DBHOST:-${PGHOST:-localhost}}")
  psql_array+=(-p "${TEST_DBPORT:-${PGPORT:-5432}}")
  psql_array+=(-U "${dbuser:-${TEST_DBUSER:-${PGUSER:-postgres}}}")
  psql_array+=(-d "${dbname}")
 else
  # Local environment - use peer authentication
  if [[ -n "${dbuser}" ]]; then
   psql_array+=(-U "${dbuser}")
  fi
  psql_array+=(-d "${dbname}")
 fi
}

# Tables to copy (in order of dependencies)
TABLES=("countries" "users" "notes" "note_comments" "note_comments_text")

__log_start
__logi "=== COPYING BASE TABLES FOR INITIAL LOAD ==="
__logi "Source DB: ${INGESTION_DB} (user: ${INGESTION_USER})"
__logi "Target DB: ${ANALYTICS_DB} (user: ${ANALYTICS_USER})"

# Skip copying if source and target are the same database (hybrid test mode)
if [[ "${INGESTION_DB}" == "${ANALYTICS_DB}" ]]; then
 __logi "Source and target databases are the same (${INGESTION_DB}), skipping table copy"
 __logi "Tables are already accessible in the same database"
 __log_finish
 exit 0
fi

# Build psql command arrays for source and target databases
declare -a INGESTION_PSQL_ARGS
declare -a ANALYTICS_PSQL_ARGS
build_psql_array "${INGESTION_DB}" "${INGESTION_USER}" INGESTION_PSQL_ARGS
build_psql_array "${ANALYTICS_DB}" "${ANALYTICS_USER}" ANALYTICS_PSQL_ARGS

# Set passwords for CI/CD environments
if [[ -n "${TEST_DBHOST:-}" ]] || [[ -n "${PGHOST:-}" ]]; then
 INGESTION_PGPASSWORD="${TEST_DBPASSWORD:-${PGPASSWORD:-postgres}}"
 ANALYTICS_PGPASSWORD="${TEST_DBPASSWORD:-${PGPASSWORD:-postgres}}"
else
 INGESTION_PGPASSWORD=""
 ANALYTICS_PGPASSWORD=""
fi

# Validate source database connection
set +e
CONNECTION_OUTPUT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -c "SELECT 1;" 2>&1)
CONNECTION_EXIT_CODE=$?
set -e
if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
 __loge "ERROR: Cannot connect to source database ${INGESTION_DB}"
 __loge "Connection error: ${CONNECTION_OUTPUT}"
 exit 1
fi

# Validate target database connection
set +e
CONNECTION_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "SELECT 1;" 2>&1)
CONNECTION_EXIT_CODE=$?
set -e
if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
 __loge "ERROR: Cannot connect to target database ${ANALYTICS_DB}"
 __loge "Connection error: ${CONNECTION_OUTPUT}"
 exit 1
fi

# Create schema if not exists
__logi "Ensuring public schema exists in target database"
PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "CREATE SCHEMA IF NOT EXISTS public;" > /dev/null 2>&1 || true

# Copy enum types and custom types before copying tables
# pg_dump with -t only copies table structure, not the types they depend on
__logi "Copying enum types and custom types from source database"
set +e
# Extract and copy all enum types from the source database
ENUM_TYPES=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -A -c "
 SELECT DISTINCT t.typname
 FROM pg_type t
 JOIN pg_enum e ON t.oid = e.enumtypid
 JOIN pg_namespace n ON t.typnamespace = n.oid
 WHERE n.nspname = 'public'
 ORDER BY t.typname;
" 2>&1)
ENUM_EXIT_CODE=$?
set -e

if [[ ${ENUM_EXIT_CODE} -eq 0 ]] && [[ -n "${ENUM_TYPES}" ]]; then
 while IFS= read -r enum_type; do
  if [[ -n "${enum_type}" ]]; then
   __logi "Copying enum type: ${enum_type}"
   # Check if enum already exists in target
   ENUM_EXISTS=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c \
    "SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname = '${enum_type}');" 2>&1 | tr -d ' ')
   if [[ "${ENUM_EXISTS}" != "t" ]]; then
    # Create enum type with all its values
    ENUM_VALUES=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -A -c "
     SELECT quote_literal(enumlabel)
     FROM pg_enum e
     JOIN pg_type t ON e.enumtypid = t.oid
     WHERE t.typname = '${enum_type}'
     ORDER BY e.enumsortorder;
    " 2>&1 | tr '\n' ',' | sed 's/,$//')
    if [[ -n "${ENUM_VALUES}" ]]; then
     CREATE_ENUM_SQL="CREATE TYPE ${enum_type} AS ENUM (${ENUM_VALUES});"
     set +e
     CREATE_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "${CREATE_ENUM_SQL}" 2>&1)
     CREATE_EXIT_CODE=$?
     set -e
     if [[ ${CREATE_EXIT_CODE} -ne 0 ]]; then
      __logw "Warning: Failed to create enum type ${enum_type}: ${CREATE_OUTPUT}"
     else
      __logi "Enum type ${enum_type} created successfully"
     fi
    fi
   else
    __logi "Enum type ${enum_type} already exists in target database"
   fi
  fi
 done <<< "${ENUM_TYPES}"
fi

# Capture maximum note_id at the start to ensure consistency between notes, note_comments, and note_comments_text
# This prevents race conditions where new notes are inserted while copying tables
__logi "Capturing maximum note_id for consistent snapshot"
set +e
MAX_NOTE_ID=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c "SELECT COALESCE(MAX(note_id), 0) FROM public.notes;" 2>&1 | tr -d ' ')
STATUS=("${PIPESTATUS[@]}")
MAX_NOTE_ID_EXIT_CODE=${STATUS[0]}
set -e
if [[ ${MAX_NOTE_ID_EXIT_CODE} -ne 0 ]] || [[ -z "${MAX_NOTE_ID}" ]]; then
 __loge "ERROR: Failed to get maximum note_id from source database"
 __loge "This is required to ensure consistency between notes, note_comments, and note_comments_text"
 exit 1
fi
__logi "Maximum note_id captured: ${MAX_NOTE_ID}"
__logi "All tables will be copied with note_id <= ${MAX_NOTE_ID} to ensure referential integrity"

# Copy each table
for table in "${TABLES[@]}"; do
 __logi "Copying table: ${table}"

 # Verify source database connection before checking table
 set +e
 CONNECTION_OUTPUT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -c "SELECT 1;" 2>&1)
 CONNECTION_EXIT_CODE=$?
 set -e
 if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
  __loge "ERROR: Cannot connect to source database ${INGESTION_DB} while copying table ${table}"
  __loge "Source database may have been dropped or is unavailable"
  __loge "Connection error: ${CONNECTION_OUTPUT}"
  exit 1
 fi

 # Check if table exists in source
 if ! PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c \
  "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}';" \
  | grep -q 1; then
  __logw "Table ${table} does not exist in source database, skipping"
  continue
 fi

 # Check if table or foreign table already exists in target (should not happen, but handle gracefully)
 # First check for foreign tables (from previous FDW setup)
 if PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c \
  "SELECT 1 FROM information_schema.foreign_tables WHERE foreign_table_schema = 'public' AND foreign_table_name = '${table}';" \
  | grep -q 1; then
  __logw "Foreign table ${table} already exists in target database, dropping first"
  set +e
  DROP_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "DROP FOREIGN TABLE IF EXISTS public.${table} CASCADE;" 2>&1)
  DROP_EXIT_CODE=$?
  set -e
  if [[ ${DROP_EXIT_CODE} -ne 0 ]]; then
   __logw "Warning: Failed to drop existing foreign table ${table}: ${DROP_OUTPUT}"
  fi
 fi
 # Then check for regular tables
 if PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c \
  "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '${table}' AND table_type = 'BASE TABLE';" \
  | grep -q 1; then
  __logw "Table ${table} already exists in target database, dropping first"
  set +e
  DROP_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "DROP TABLE IF EXISTS public.${table} CASCADE;" 2>&1)
  DROP_EXIT_CODE=$?
  set -e
  if [[ ${DROP_EXIT_CODE} -ne 0 ]]; then
   __logw "Warning: Failed to drop existing table ${table}: ${DROP_OUTPUT}"
  fi
 fi

 # Get table structure and create in target
 __logi "Creating table structure for ${table}"

 # Special handling for countries table: only copy needed columns (no geom, no zone columns)
 if [[ "${table}" == "countries" ]]; then
  __logi "Creating countries table with only required columns (excluding geom and zone columns)"
  set +e
  CREATE_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "
  CREATE TABLE IF NOT EXISTS public.countries (
   country_id INTEGER NOT NULL,
   country_name VARCHAR(100) NOT NULL,
   country_name_es VARCHAR(100),
   country_name_en VARCHAR(100)
  );
 " 2>&1)
  CREATE_EXIT_CODE=$?
  set -e
  if [[ ${CREATE_EXIT_CODE} -ne 0 ]]; then
   __loge "ERROR: Failed to create table structure for ${table}"
   __loge "Schema creation error: ${CREATE_OUTPUT}"
   exit 1
  fi
 else
  # Build pg_dump command array
  declare -a PGDUMP_ARGS
  if [[ -n "${TEST_DBHOST:-}" ]] || [[ -n "${PGHOST:-}" ]]; then
   PGDUMP_ARGS=(-h "${TEST_DBHOST:-${PGHOST:-localhost}}" -p "${TEST_DBPORT:-${PGPORT:-5432}}" -U "${INGESTION_USER:-${TEST_DBUSER:-${PGUSER:-postgres}}}" -d "${INGESTION_DB}")
  else
   PGDUMP_ARGS=(-d "${INGESTION_DB}")
   [[ -n "${INGESTION_USER}" ]] && PGDUMP_ARGS+=(-U "${INGESTION_USER}")
  fi

  set +e
  SCHEMA_OUTPUT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" pg_dump "${PGDUMP_ARGS[@]}" \
   -t "public.${table}" \
   --schema-only \
   --no-owner --no-acl \
   2>&1 | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -q 2>&1)
  SCHEMA_EXIT_CODE=${PIPESTATUS[0]}
  set -e
  if [[ ${SCHEMA_EXIT_CODE} -ne 0 ]]; then
   __loge "ERROR: Failed to create table structure for ${table}"
   __loge "Schema creation error: ${SCHEMA_OUTPUT}"
   exit 1
  fi
 fi

 # Copy data using COPY (fastest method)
 __logi "Copying data for ${table}"
 set +e
 # For notes, note_comments, and note_comments_text, use MAX_NOTE_ID to ensure consistency
 if [[ "${table}" == "notes" ]]; then
  ROW_COUNT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID};" 2>&1 | tr -d ' ')
  STATUS=("${PIPESTATUS[@]}")
 elif [[ "${table}" == "note_comments" ]]; then
  ROW_COUNT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID};" 2>&1 | tr -d ' ')
  STATUS=("${PIPESTATUS[@]}")
 elif [[ "${table}" == "note_comments_text" ]]; then
  ROW_COUNT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID};" 2>&1 | tr -d ' ')
  STATUS=("${PIPESTATUS[@]}")
 else
  ROW_COUNT=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table};" 2>&1 | tr -d ' ')
  STATUS=("${PIPESTATUS[@]}")
 fi
 ROW_COUNT_EXIT_CODE=${STATUS[0]}
 set -e
 if [[ ${ROW_COUNT_EXIT_CODE} -ne 0 ]]; then
  __loge "ERROR: Failed to get row count for ${table}"
  exit 1
 fi
 __logi "Copying ${ROW_COUNT} rows from ${table}"

 # Special handling for countries table: copy only required columns
 if [[ "${table}" == "countries" ]]; then
  set +e
  COPY_ERRORS=$(mktemp)
  # Copy only the columns we need (no geom, no zone columns)
  PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" \
   -c "\COPY (SELECT country_id, country_name, country_name_es, country_name_en FROM public.${table}) TO STDOUT" 2>&1 \
   | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" \
    -c "\COPY public.${table} (country_id, country_name, country_name_es, country_name_en) FROM STDIN" > "${COPY_ERRORS}" 2>&1
  COPY_EXIT_CODE_1=${PIPESTATUS[0]:-1}
  COPY_EXIT_CODE_2=${PIPESTATUS[1]:-1}
  COPY_ERROR_CONTENT=$(cat "${COPY_ERRORS}")
  rm -f "${COPY_ERRORS}"
  set -e

  # Verify row count first - if it matches, COPY was successful regardless of exit code
  # (psql may return non-zero exit code even on successful COPY if there are warnings/notices)
  TARGET_COUNT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table};" 2>&1 | tr -d ' ' || echo "0")
  if [[ "${ROW_COUNT}" == "${TARGET_COUNT}" ]]; then
   __logi "COPY successful: ${TARGET_COUNT} rows copied (verified by row count)"
  elif [[ ${COPY_EXIT_CODE_1} -ne 0 ]] || [[ ${COPY_EXIT_CODE_2} -ne 0 ]]; then
   __loge "ERROR: Failed to copy data for ${table}"
   __loge "COPY TO STDOUT exit code: ${COPY_EXIT_CODE_1}"
   __loge "COPY FROM STDIN exit code: ${COPY_EXIT_CODE_2}"
   __loge "COPY error details: ${COPY_ERROR_CONTENT}"
   __loge "Row count mismatch: source=${ROW_COUNT}, target=${TARGET_COUNT}"
   exit 1
  fi
 else
  # Capture errors from both psql commands in the pipeline
  set +e
  COPY_ERRORS=$(mktemp)
  # For notes, note_comments, and note_comments_text, filter by MAX_NOTE_ID to ensure consistency
  if [[ "${table}" == "notes" ]]; then
   # Copy notes with note_id <= MAX_NOTE_ID
   PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" \
    -c "\COPY (SELECT * FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID}) TO STDOUT" 2>&1 \
    | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" \
     -c "\COPY public.${table} FROM STDIN" > "${COPY_ERRORS}" 2>&1
  elif [[ "${table}" == "note_comments" ]]; then
   # Copy note_comments with note_id <= MAX_NOTE_ID
   PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" \
    -c "\COPY (SELECT * FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID}) TO STDOUT" 2>&1 \
    | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" \
     -c "\COPY public.${table} FROM STDIN" > "${COPY_ERRORS}" 2>&1
  elif [[ "${table}" == "note_comments_text" ]]; then
   # Copy note_comments_text with note_id <= MAX_NOTE_ID to ensure referential integrity
   PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" \
    -c "\COPY (SELECT * FROM public.${table} WHERE note_id <= ${MAX_NOTE_ID}) TO STDOUT" 2>&1 \
    | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" \
     -c "\COPY public.${table} FROM STDIN" > "${COPY_ERRORS}" 2>&1
  else
   # For other tables, copy all rows
   PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" \
    -c "\COPY public.${table} TO STDOUT" 2>&1 \
    | PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" \
     -c "\COPY public.${table} FROM STDIN" > "${COPY_ERRORS}" 2>&1
  fi
  # Capture PIPESTATUS immediately after the pipeline (it resets after each command)
  # Use default values if PIPESTATUS array doesn't have enough elements
  COPY_EXIT_CODE_1=${PIPESTATUS[0]:-1}
  COPY_EXIT_CODE_2=${PIPESTATUS[1]:-1}
  COPY_ERROR_CONTENT=$(cat "${COPY_ERRORS}")
  rm -f "${COPY_ERRORS}"
  set -e

  # Verify row count first - if it matches, COPY was successful regardless of exit code
  # (psql may return non-zero exit code even on successful COPY if there are warnings/notices)
  TARGET_COUNT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table};" 2>&1 | tr -d ' ' || echo "0")
  if [[ "${ROW_COUNT}" == "${TARGET_COUNT}" ]]; then
   __logi "COPY successful: ${TARGET_COUNT} rows copied (verified by row count)"
  elif [[ ${COPY_EXIT_CODE_1} -ne 0 ]] || [[ ${COPY_EXIT_CODE_2} -ne 0 ]]; then
   __loge "ERROR: Failed to copy data for ${table}"
   __loge "COPY TO STDOUT exit code: ${COPY_EXIT_CODE_1}"
   __loge "COPY FROM STDIN exit code: ${COPY_EXIT_CODE_2}"
   __loge "COPY error details: ${COPY_ERROR_CONTENT}"
   __loge "Row count mismatch: source=${ROW_COUNT}, target=${TARGET_COUNT}"
   exit 1
  fi
 fi

 # Verify row count (if not already verified above)
 if [[ "${table}" != "countries" ]]; then
  TARGET_COUNT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -t -c "SELECT COUNT(*) FROM public.${table};" 2>&1 | tr -d ' ' || echo "0")
  if [[ "${ROW_COUNT}" != "${TARGET_COUNT}" ]]; then
   __loge "ERROR: Row count mismatch for ${table}: source=${ROW_COUNT}, target=${TARGET_COUNT}"
   exit 1
  fi
  __logi "Verified: ${TARGET_COUNT} rows copied for ${table}"
 fi

 # Create indexes (copy from source, or only needed ones for slim tables)
 __logi "Creating indexes for ${table}"
 set +e
 if [[ "${table}" == "countries" ]]; then
  # Slim countries table has only country_id, country_name, country_name_es, country_name_en.
  # Create only the primary key; skip source indexes (geom, is_maritime, etc.) to avoid WARNs.
  index_output=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c \
   "ALTER TABLE public.countries ADD PRIMARY KEY (country_id);" 2>&1)
  index_exit_code=$?
  if [[ ${index_exit_code} -ne 0 ]]; then
   # May already exist from a previous run
   __logw "Warning: Failed to add primary key on countries (may already exist): ${index_output}"
  fi
 else
  index_list=$(PGPASSWORD="${INGESTION_PGPASSWORD}" psql "${INGESTION_PSQL_ARGS[@]}" -t -A -c \
   "SELECT 'CREATE INDEX IF NOT EXISTS ' || indexname || ' ON public.${table} ' ||
           regexp_replace(indexdef, '^CREATE (UNIQUE )?INDEX .* ON public\.${table} ', '') || ';'
    FROM pg_indexes
    WHERE tablename = '${table}' AND schemaname = 'public'
    AND indexname NOT LIKE '%_pkey';" 2>&1)
  index_list_exit_code=$?
  set -e
  if [[ ${index_list_exit_code} -eq 0 ]] && [[ -n "${index_list}" ]]; then
   while IFS= read -r index_sql; do
    if [[ -n "${index_sql}" ]]; then
     set +e
     index_output=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "${index_sql}" 2>&1)
     index_exit_code=$?
     set -e
     if [[ ${index_exit_code} -ne 0 ]]; then
      # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
      __logw "Warning: Failed to create index for ${table}: ${index_output}"
     fi
    fi
   done <<< "${index_list}"
  fi
 fi
 set -e

 # Analyze table for better query performance
 __logi "Analyzing table ${table}"
 set +e
 analyze_output=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "ANALYZE public.${table};" 2>&1)
 analyze_exit_code=$?
 set -e
 if [[ ${analyze_exit_code} -ne 0 ]]; then
  __logw "Warning: Failed to analyze table ${table}: ${analyze_output}"
 fi

 __logi "Table ${table} copied successfully"
done

# Save MAX_NOTE_ID to properties table for incremental processing
# This ensures the next incremental ETL knows where to start
__logi "Saving maximum note_id (${MAX_NOTE_ID}) to properties table for incremental processing"
set +e
# Ensure properties table exists (it should, but be safe)
PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "
CREATE SCHEMA IF NOT EXISTS dwh;
CREATE TABLE IF NOT EXISTS dwh.properties (
 key VARCHAR(16) PRIMARY KEY,
 value VARCHAR(26)
);
" > /dev/null 2>&1 || true

# Save MAX_NOTE_ID to properties
SAVE_PROPERTIES_OUTPUT=$(PGPASSWORD="${ANALYTICS_PGPASSWORD}" psql "${ANALYTICS_PSQL_ARGS[@]}" -c "
INSERT INTO dwh.properties (key, value)
VALUES ('max_note_id', '${MAX_NOTE_ID}')
ON CONFLICT (key) DO UPDATE SET value = '${MAX_NOTE_ID}';
" 2>&1)
SAVE_PROPERTIES_EXIT_CODE=$?
set -e
if [[ ${SAVE_PROPERTIES_EXIT_CODE} -ne 0 ]]; then
 __logw "Warning: Failed to save MAX_NOTE_ID to properties table: ${SAVE_PROPERTIES_OUTPUT}"
 __logw "Incremental processing may not know where to start"
else
 __logi "MAX_NOTE_ID saved successfully to dwh.properties"
fi

__logi "=== BASE TABLES COPY COMPLETED ==="
__logi "Maximum note_id processed: ${MAX_NOTE_ID}"
__logi "Next incremental ETL will process notes with note_id > ${MAX_NOTE_ID}"
__log_finish
exit 0
