#!/bin/bash

# Creates a datamart for country data with pre-computed analytics.
#
# DM-006: Implements parallel processing with work queue for dynamic load balancing:
# - Countries processed in parallel using nproc-2 threads
# - Shared work queue: each thread takes next available country after finishing one
# - Better load balancing: fast countries don't leave threads idle
# - Atomic transactions ensure data consistency
#
# Documentation: See PARALLEL_PROCESSING.md for detailed information about
#                 the work queue and parallel processing system.
#
# To follow the progress you can execute:
#   tail -40f $(ls -1rtd /tmp/datamartCountries_* | tail -1)/datamartCountries.log
#
# This is the list of error codes:
# 1) Help message.
# 241) Library or utility missing.
# 242) Invalid argument for script invocation.
# 243) Logger utility is not available.
#
# For contributing, please execute these commands at the end:
# * shellcheck -x -o all datamartCountries.sh
# * shfmt -w -i 1 -sr -bn datamartCountries.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2025-08-11
VERSION="2025-08-11"

#set -xv
# Fails when a variable is not initialized.
set -u
# Fails with a non-zero return code.
set -e
# Fails if the commands of a pipe return non-zero.
set -o pipefail
# Fails if an internal function fails.
set -E

# If all files should be deleted. In case of an error, this could be disabled.
# You can define when calling: export CLEAN=false
# CLEAN is now defined in etc/properties.sh, no need to declare it here

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-ERROR}"

# Base directory for the project.
declare SCRIPT_BASE_DIRECTORY
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." \
 &> /dev/null && pwd)"
readonly SCRIPT_BASE_DIRECTORY

# Loads the global properties.
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"

# Load local properties if they exist (overrides global settings)
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local"
fi

declare BASENAME
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME
# Temporary directory for all files.
declare TMP_DIR
TMP_DIR=$(mktemp -d "/tmp/${BASENAME}_XXXXXX")
readonly TMP_DIR
chmod 777 "${TMP_DIR}"
# Log file for output.
declare LOG_FILENAME
LOG_FILENAME="${TMP_DIR}/${BASENAME}.log"
readonly LOG_FILENAME

# Lock file for single execution.
declare LOCK
LOCK="${TMP_DIR}/${BASENAME}.lock"
readonly LOCK

# Type of process to run in the script.
# Empty string "" is a valid value (means default processing)
if [[ -z "${PROCESS_TYPE:-}" ]]; then
 declare PROCESS_TYPE=${1:-}
 declare -r PROCESS_TYPE
fi

# Name of the SQL script that contains the objects to create in the DB.
declare -r CHECK_OBJECTS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_10_checkDatamartCountriesTables.sql"

# Name of the SQL script that contains the tables to create in the DB.
declare -r CREATE_TABLES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql"

# Name of the SQL script that contains the procedures to create in the DB.
declare -r CREATE_PROCEDURES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"

# Generic script to add years.
declare -r ADD_YEARS_SCRIPT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_23_alterTableAddYears.sql"

# Name of the SQL script that contains the ETL process.
declare -r POPULATE_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_30_populateDatamartCountriesTable.sql"

# Last year activities script.
declare -r LAST_YEAR_ACTITIES_SCRIPT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"

# Performance optimization scripts (applied automatically on setup)
declare -r OPTIMIZE_INDEXES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_14_optimize_indexes.sql"
declare -r INCREMENTAL_YEAR_PROCESSING_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_13_incremental_year_processing.sql"
declare -r CONSOLIDATE_METRICS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_17_consolidate_basic_metrics.sql"
declare -r CONSOLIDATE_RANKINGS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_20_consolidate_user_rankings.sql"
declare -r CONSOLIDATE_HASHTAGS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_21_consolidate_hashtags.sql"
declare -r CONSOLIDATE_YEAR_ACTIVITY_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_22_consolidate_year_activity.sql"
declare -r CONSOLIDATE_DATES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_21_consolidate_dates_metrics.sql"
declare -r CONSOLIDATE_WORKING_HOURS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_24_consolidate_working_hours.sql"
declare -r CONSOLIDATE_APPLICATIONS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_25_consolidate_applications.sql"
declare -r CONSOLIDATE_COMMENTS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_26_consolidate_comments.sql"
declare -r CONSOLIDATE_NOTES_AGE_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_27_consolidate_notes_age.sql"

###########
# FUNCTIONS

# Load common functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

# Load validation functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"

# Load error handling functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"

# Shows the help information.
function __show_help {
 echo "${0} version ${VERSION}"
 echo "This script populates the country datamart with pre-computed analytics."
 echo "The datamart aggregates note statistics by country from the fact table."
 echo
 echo "Written by: Andres Gomez (AngocA)"
 echo "OSM-LatAm, OSM-Colombia, MaptimeBogota."
 exit "${ERROR_HELP_MESSAGE}"
}

# Wrapper for psql that sets application_name for better process identification
# Usage: __psql_with_appname [appname] [psql_args...]
# If appname is not provided, uses BASENAME (script name without .sh)
# If first argument starts with '-', it's a psql option, not an appname
function __psql_with_appname {
 local appname
 if [[ "${1:-}" =~ ^- ]]; then
  # First argument is a psql option, use default appname
  appname="${BASENAME}"
 else
  # First argument is an appname
  appname="${1}"
  shift
 fi
 PGAPPNAME="${appname}" psql "$@"
}

# Checks prerequisites to run the script.
function __checkPrereqs {
 __log_start
 if [[ "${PROCESS_TYPE}" != "" ]] && [[ "${PROCESS_TYPE}" != "--help" ]] \
  && [[ "${PROCESS_TYPE}" != "-h" ]]; then
  echo "ERROR: Invalid parameter. It should be:"
  echo " * Empty string, nothing."
  echo " * --help"
  exit "${ERROR_INVALID_ARGUMENT}"
 fi

 __checkPrereqsCommands

 ## Validate SQL script files using centralized validation
 __logi "Validating SQL script files..."

 # Create array of SQL files to validate
 local SQL_FILES=(
  "${CHECK_OBJECTS_FILE}"
  "${CREATE_TABLES_FILE}"
  "${CREATE_PROCEDURES_FILE}"
  "${POPULATE_FILE}"
  "${ADD_YEARS_SCRIPT}"
  "${LAST_YEAR_ACTITIES_SCRIPT}"
 )

 # Add optimization scripts if they exist (optional, don't fail if missing)
 if [[ -f "${OPTIMIZE_INDEXES_FILE}" ]]; then
  SQL_FILES+=("${OPTIMIZE_INDEXES_FILE}")
 fi
 if [[ -f "${INCREMENTAL_YEAR_PROCESSING_FILE}" ]]; then
  SQL_FILES+=("${INCREMENTAL_YEAR_PROCESSING_FILE}")
 fi
 if [[ -f "${CONSOLIDATE_METRICS_FILE}" ]]; then
  SQL_FILES+=("${CONSOLIDATE_METRICS_FILE}")
 fi
 if [[ -f "${CONSOLIDATE_RANKINGS_FILE}" ]]; then
  SQL_FILES+=("${CONSOLIDATE_RANKINGS_FILE}")
 fi

 # Validate each SQL file
 for SQL_FILE in "${SQL_FILES[@]}"; do
  # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
  if ! __validate_sql_structure "${SQL_FILE}"; then
   __loge "ERROR: SQL file validation failed: ${SQL_FILE}"
   exit "${ERROR_MISSING_LIBRARY}"
  fi
 done

 __log_finish
}

# Creates base tables that hold the whole history.
function __createBaseTables {
 __log_start
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${CREATE_TABLES_FILE}"
 __log_finish
}

# Checks the tables are created.
function __checkBaseTables {
 __log_start
 set +e
 # Redirect stderr to avoid SQL error messages from causing issues
 # The error is expected when tables don't exist yet
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${CHECK_OBJECTS_FILE}" 2> /dev/null
 RET=${?}
 set -e
 if [[ "${RET}" -ne 0 ]]; then
  __logw "Creating datamart countries tables."
  __createBaseTables
  __logw "Datamart countries tables created."
  # Reset return code to 0 since we successfully created the tables
  RET=0
 fi
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${CREATE_PROCEDURES_FILE}"
 local proc_ret=${?}
 set -e
 if [[ "${proc_ret}" -ne 0 ]]; then
  __loge "Failed to create procedures, but continuing..."
 fi
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${LAST_YEAR_ACTITIES_SCRIPT}"
 local last_year_ret=${?}
 set -e
 if [[ "${last_year_ret}" -ne 0 ]]; then
  __loge "Failed to create last year activities, but continuing..."
 fi

 # Apply performance optimizations (idempotent - safe to run multiple times)
 __logi "Applying performance optimizations..."
 set +e
 if [[ -f "${OPTIMIZE_INDEXES_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${OPTIMIZE_INDEXES_FILE}" > /dev/null 2>&1
  local idx_ret=${?}
  if [[ "${idx_ret}" -eq 0 ]]; then
   __logi "Performance indexes applied successfully"
  else
   __logw "Failed to apply performance indexes (may already exist), continuing..."
  fi
 else
  __logw "Performance indexes script not found: ${OPTIMIZE_INDEXES_FILE}"
 fi

 if [[ -f "${INCREMENTAL_YEAR_PROCESSING_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${INCREMENTAL_YEAR_PROCESSING_FILE}" > /dev/null 2>&1
  local inc_ret=${?}
  if [[ "${inc_ret}" -eq 0 ]]; then
   __logi "Incremental year processing functions applied successfully"
  else
   __logw "Failed to apply incremental year processing (may already exist), continuing..."
  fi
 else
  __logw "Incremental year processing script not found: ${INCREMENTAL_YEAR_PROCESSING_FILE}"
 fi

 if [[ -f "${CONSOLIDATE_METRICS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_METRICS_FILE}" > /dev/null 2>&1
  local cons_ret=${?}
  if [[ "${cons_ret}" -eq 0 ]]; then
   __logi "Consolidated metrics function applied successfully"
  else
   __logw "Failed to apply consolidated metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated metrics script not found: ${CONSOLIDATE_METRICS_FILE}"
 fi

 if [[ -f "${CONSOLIDATE_RANKINGS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_RANKINGS_FILE}" > /dev/null 2>&1
  local rank_ret=${?}
  if [[ "${rank_ret}" -eq 0 ]]; then
   __logi "Consolidated user rankings function applied successfully"
  else
   __logw "Failed to apply consolidated user rankings function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated user rankings script not found: ${CONSOLIDATE_RANKINGS_FILE}"
 fi

 if [[ -f "${CONSOLIDATE_HASHTAGS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_HASHTAGS_FILE}" > /dev/null 2>&1
  local hashtag_ret=${?}
  if [[ "${hashtag_ret}" -eq 0 ]]; then
   __logi "Consolidated hashtag metrics function applied successfully"
  else
   __logw "Failed to apply consolidated hashtag metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated hashtag metrics script not found: ${CONSOLIDATE_HASHTAGS_FILE}"
 fi

 if [[ -f "${CONSOLIDATE_YEAR_ACTIVITY_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_YEAR_ACTIVITY_FILE}" > /dev/null 2>&1
  local year_ret=${?}
  if [[ "${year_ret}" -eq 0 ]]; then
   __logi "Consolidated year activity function applied successfully"
  else
   __logw "Failed to apply consolidated year activity function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated year activity script not found: ${CONSOLIDATE_YEAR_ACTIVITY_FILE}"
 fi
 if [[ -f "${CONSOLIDATE_DATES_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_DATES_FILE}" > /dev/null 2>&1
  local dates_ret=${?}
  if [[ "${dates_ret}" -eq 0 ]]; then
   __logi "Consolidated dates metrics function applied successfully"
  else
   __logw "Failed to apply consolidated dates metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated dates metrics script not found: ${CONSOLIDATE_DATES_FILE}"
 fi
 if [[ -f "${CONSOLIDATE_WORKING_HOURS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_WORKING_HOURS_FILE}" > /dev/null 2>&1
  local hours_ret=${?}
  if [[ "${hours_ret}" -eq 0 ]]; then
   __logi "Consolidated working hours function applied successfully"
  else
   __logw "Failed to apply consolidated working hours function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated working hours script not found: ${CONSOLIDATE_WORKING_HOURS_FILE}"
 fi
 if [[ -f "${CONSOLIDATE_APPLICATIONS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_APPLICATIONS_FILE}" > /dev/null 2>&1
  local apps_ret=${?}
  if [[ "${apps_ret}" -eq 0 ]]; then
   __logi "Consolidated applications metrics function applied successfully"
  else
   __logw "Failed to apply consolidated applications metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated applications metrics script not found: ${CONSOLIDATE_APPLICATIONS_FILE}"
 fi
 if [[ -f "${CONSOLIDATE_COMMENTS_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_COMMENTS_FILE}" > /dev/null 2>&1
  local comments_ret=${?}
  if [[ "${comments_ret}" -eq 0 ]]; then
   __logi "Consolidated comments metrics function applied successfully"
  else
   __logw "Failed to apply consolidated comments metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated comments metrics script not found: ${CONSOLIDATE_COMMENTS_FILE}"
 fi
 if [[ -f "${CONSOLIDATE_NOTES_AGE_FILE}" ]]; then
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=0 -f "${CONSOLIDATE_NOTES_AGE_FILE}" > /dev/null 2>&1
  local notes_age_ret=${?}
  if [[ "${notes_age_ret}" -eq 0 ]]; then
   __logi "Consolidated notes age metrics function applied successfully"
  else
   __logw "Failed to apply consolidated notes age metrics function (may already exist), continuing..."
  fi
 else
  __logw "Consolidated notes age metrics script not found: ${CONSOLIDATE_NOTES_AGE_FILE}"
 fi
 set -e

 __log_finish
 return "${RET}"
}

# Adds the columns up to the current year.
function __addYears {
 __log_start
 YEAR=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${YEAR}" -lt "${CURRENT_YEAR}" ]]; do
  YEAR=$((YEAR + 1))
  export YEAR
  set +e
  # shellcheck disable=SC2016
  __psql_with_appname -d "${DBNAME_DWH}" -c "$(envsubst '$YEAR' < "${ADD_YEARS_SCRIPT}" \
   || true)" 2>&1
  set -e
 done
 __log_finish
}

# Thread-safe function to get next country from shared work queue.
# Uses file locking (flock) to ensure atomic queue operations.
# This function is used by worker threads to get the next country to process.
# Usage: country_id=$(__get_next_country_from_queue)
# Returns: country ID as string, or empty string if queue is empty
# Exit code: 0 = success (got country or queue empty), 1 = lock failed (should retry)
__get_next_country_from_queue() {
 local result_file="${work_queue_file}.result.${BASHPID}"
 local country_id=""

 # Ensure queue file exists before attempting to read
 if [[ ! -f "${work_queue_file}" ]]; then
  echo ""
  return 0
 fi

 (
  # Try to acquire lock (non-blocking)
  # If lock cannot be acquired, exit with code 1 to signal retry needed
  if ! flock -n 200; then
   exit 1
  fi

  # Read first line (next country to process)
  if [[ -f "${work_queue_file}" ]] && [[ -s "${work_queue_file}" ]]; then
   head -n 1 "${work_queue_file}" 2> /dev/null > "${result_file}" || echo "" > "${result_file}"

   # If we got a country ID, remove it from queue
   if [[ -s "${result_file}" ]]; then
    # Remove first line from queue atomically
    if tail -n +2 "${work_queue_file}" > "${work_queue_file}.tmp" 2> /dev/null; then
     mv "${work_queue_file}.tmp" "${work_queue_file}" 2> /dev/null || true
    fi
   fi
  else
   echo "" > "${result_file}"
  fi
  exit 0
 ) 200> "${queue_lock_file}"
 local exit_code=$?

 # If lock acquisition failed, return special marker to indicate retry needed
 if [[ ${exit_code} -eq 1 ]]; then
  echo ""
  return 1
 fi

 # Read result and clean up
 if [[ -f "${result_file}" ]]; then
  country_id=$(cat "${result_file}" 2> /dev/null || echo "")
  rm -f "${result_file}" 2> /dev/null || true
 fi

 echo "${country_id}"
 return 0
}

# Processes countries in parallel using a shared work queue for dynamic load balancing.
# Each worker thread takes the next available country from the queue after finishing one.
# This ensures better load balancing: fast countries don't leave threads idle while
# slow countries are being processed by other threads.
function __processNotesCountriesParallel {
 # Disable exit on error temporarily to handle errors explicitly
 set +e
 __log_start
 __logi "=== PROCESSING COUNTRIES IN PARALLEL (WORK QUEUE) ==="

 # Get MAX_THREADS for parallel processing
 local MAX_THREADS="${MAX_THREADS:-$(nproc)}"
 local adjusted_threads
 if [[ "${MAX_THREADS}" -gt 2 ]]; then
  adjusted_threads=$((MAX_THREADS - 2))
  __logi "Using ${adjusted_threads} parallel threads (nproc-2: ${MAX_THREADS} - 2)"
 else
  adjusted_threads=1
  __logi "Using 1 thread (insufficient CPUs for parallel processing)"
 fi

 # First, handle the "move day" operation (must be done before parallel processing)
 # This updates last_year_activity for all countries
 __logi "Updating last_year_activity for all countries..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -c "
  DO \$\$
  DECLARE
   max_date DATE;
  BEGIN
   SELECT date INTO max_date FROM dwh.max_date_countries_processed;
   IF (max_date < CURRENT_DATE) THEN
    RAISE NOTICE 'Moving activities.';
    UPDATE dwh.datamartCountries
     SET last_year_activity = dwh.move_day(last_year_activity);
    UPDATE dwh.max_date_countries_processed
     SET date = CURRENT_DATE;
   END IF;
  END
  \$\$;
 " 2>&1
 local move_day_exit_code=$?
 set -e
 if [[ ${move_day_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to update last_year_activity (exit code: ${move_day_exit_code})"
  __log_finish
  return 1
 fi

 # Get list of modified countries (ordered by recent activity - most active first)
 __logi "Fetching modified countries..."
 local country_ids
 country_ids=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "
  SELECT /* Notes-datamartCountries-parallel */
   f.dimension_id_country AS dimension_id_country
  FROM dwh.facts f
   JOIN dwh.dimension_countries c
   ON (f.dimension_id_country = c.dimension_country_id)
  WHERE c.modified = TRUE
  GROUP BY f.dimension_id_country
  ORDER BY MAX(f.action_at) DESC
 " 2>&1)

 local total_countries
 total_countries=$(echo "${country_ids}" | grep -c . || echo "0")
 total_countries=$(echo "${total_countries}" | tr -d '[:space:]') # Remove all whitespace including newlines
 total_countries=$((total_countries))                             # Ensure numeric
 __logi "Found ${total_countries} countries to process"

 if [[ "${total_countries}" -eq 0 ]]; then
  __logi "No countries to process"
  __log_finish
  return 0
 fi

 # Create shared work queue file
 local work_queue_file="${TMP_DIR}/country_work_queue.txt"
 echo "${country_ids}" > "${work_queue_file}"

 # Ensure queue file is fully written and readable before starting threads
 # This prevents race conditions where threads start before the file is ready
 if [[ ! -f "${work_queue_file}" ]] || [[ ! -s "${work_queue_file}" ]]; then
  __loge "ERROR: Failed to create work queue file"
  __log_finish
  return 1
 fi

 # Verify queue file has expected content
 local queue_count
 queue_count=$(wc -l < "${work_queue_file}" 2> /dev/null || echo "0")
 queue_count=$(echo "${queue_count}" | tr -d '[:space:]') # Remove all whitespace including newlines
 queue_count=$((queue_count))                             # Ensure numeric
 if [[ "${queue_count}" -ne "${total_countries}" ]]; then
  __logw "WARN: Queue file count (${queue_count}) differs from expected (${total_countries}), but continuing..."
 fi

 # Create lock file for queue access
 local queue_lock_file="${TMP_DIR}/country_queue.lock"
 touch "${queue_lock_file}" 2> /dev/null || true

 # Export variables for use in subshells (functions are automatically inherited)
 export work_queue_file queue_lock_file

 # Small delay to ensure file system synchronization before starting threads
 # This helps prevent race conditions where threads access the queue file
 # before it's fully written to disk
 sleep 0.1

 local pids=()
 local start_time
 start_time=$(date +%s)

 # Start worker threads
 __logi "Starting ${adjusted_threads} parallel worker threads..."
 for ((thread_num = 1; thread_num <= adjusted_threads; thread_num++)); do
  (
   # Disable exit on error to handle errors explicitly in this subshell
   set +e
   local thread_processed=0
   local thread_failed=0
   local country_id
   local empty_retries=0
   local max_empty_retries=3
   local retry_delay=0.2

   while true; do
    # Get next country from shared queue (thread-safe)
    # Functions and exported variables are automatically available in subshells
    country_id=$(__get_next_country_from_queue)
    local queue_exit_code=$?

    # If lock acquisition failed (exit code 1), retry after short delay
    # This handles temporary lock contention from other threads
    if [[ ${queue_exit_code} -eq 1 ]]; then
     empty_retries=$((empty_retries + 1))
     # Limit retries to prevent infinite loops, but allow more retries for lock contention
     if [[ ${empty_retries} -lt $((max_empty_retries * 2)) ]]; then
      sleep "${retry_delay}"
      continue
     else
      __logw "Thread ${thread_num}: Too many lock acquisition failures, exiting"
      break
     fi
    fi

    # If queue is empty, check if we should retry (handles race condition at startup)
    if [[ -z "${country_id}" ]]; then
     # If this is the first attempt and queue appears empty, retry a few times
     # This handles the case where threads start before the queue file is fully ready
     if [[ ${thread_processed} -eq 0 ]] && [[ ${empty_retries} -lt ${max_empty_retries} ]]; then
      empty_retries=$((empty_retries + 1))
      sleep "${retry_delay}"
      continue
     fi
     # Queue is truly empty or we've exhausted retries, exit thread
     break
    fi

    # Reset empty retries counter once we successfully get a country
    empty_retries=0

    # Process country in atomic transaction
    # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
    if ! __psql_with_appname "datamartCountries-country-${country_id}-thread${thread_num}" \
     -d "${DBNAME_DWH}" -c "
      BEGIN;
       CALL dwh.update_datamart_country(${country_id});
       UPDATE dwh.dimension_countries
        SET modified = FALSE
        WHERE dimension_country_id = ${country_id};
      COMMIT;
    " 2>&1; then
     thread_failed=$((thread_failed + 1))
     __loge "Thread ${thread_num}: ERROR: Failed to process country ${country_id}"
    else
     thread_processed=$((thread_processed + 1))
     # Log every 5 countries per thread
     if [[ $((thread_processed % 5)) -eq 0 ]]; then
      __logi "Thread ${thread_num}: Processed ${thread_processed} countries (current: country ${country_id})"
     fi
    fi
   done

   # Report thread completion
   if [[ ${thread_failed} -eq 0 ]]; then
    __logi "Thread ${thread_num}: Completed successfully (${thread_processed} countries processed)"
   else
    __loge "Thread ${thread_num}: Completed with ${thread_failed} failures (${thread_processed} countries processed)"
   fi

   exit "${thread_failed}"
  ) &
  pids+=($!)
  __logi "Started worker thread ${thread_num} (PID: ${!})"

  # Small delay between thread starts to reduce lock contention
  # This helps prevent all threads from trying to acquire the lock simultaneously
  if [[ ${thread_num} -lt ${adjusted_threads} ]]; then
   sleep 0.05
  fi
 done

 # Wait for all worker threads to complete
 __logi "Waiting for all worker threads to complete..."
 local total_failed=0
 for pid in "${pids[@]}"; do
  set +e # Temporarily disable exit on error to capture wait exit code
  wait "${pid}"
  local thread_exit_code=$?
  set -e # Re-enable exit on error
  if [[ ${thread_exit_code} -ne 0 ]]; then
   total_failed=$((total_failed + thread_exit_code))
   __logw "Thread with PID ${pid} exited with code ${thread_exit_code}"
  fi
 done

 local end_time
 end_time=$(date +%s)
 local total_time=$((end_time - start_time))

 # Count total processed (check remaining queue)
 local remaining_countries=0
 if [[ -f "${work_queue_file}" ]]; then
  remaining_countries=$(wc -l < "${work_queue_file}" 2> /dev/null || echo "0")
  remaining_countries=$(echo "${remaining_countries}" | tr -d '[:space:]') # Remove all whitespace including newlines
  remaining_countries=$((remaining_countries))                             # Ensure numeric
 fi
 local actually_processed=$((total_countries - remaining_countries))

 if [[ ${total_failed} -eq 0 ]]; then
  __logi "SUCCESS: Datamart countries population completed successfully"
  __logi "Processed ${actually_processed} countries in parallel (${total_countries} total)"
  __logi "⏱️  TIME: Parallel country processing took ${total_time} seconds"
  __log_finish
  rm -f "${work_queue_file}" "${queue_lock_file}" 2> /dev/null || true
  set -e
  return 0
 else
  __loge "ERROR: Datamart countries population had ${total_failed} failed country(ies)"
  __loge "Processed ${actually_processed}/${total_countries} countries successfully"
  __loge "⏱️  TIME: Parallel country processing took ${total_time} seconds (with ${total_failed} failures)"
  __log_finish
  rm -f "${work_queue_file}" "${queue_lock_file}" 2> /dev/null || true
  set -e
  return 1
 fi
}

# Function that activates the error trap.
function __trapOn() {
 __log_start
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 trap '{
  local ERROR_LINE="${LINENO}"
  local ERROR_COMMAND="${BASH_COMMAND}"
  local ERROR_EXIT_CODE="$?"

  # Only report actual errors, not successful returns
  if [[ "${ERROR_EXIT_CODE}" -ne 0 ]]; then
   # Get the main script name (the one that was executed, not the library)
   local MAIN_SCRIPT_NAME
   MAIN_SCRIPT_NAME=$(basename "${0}" .sh)

   printf "%s ERROR: The script %s did not finish correctly. Temporary directory: ${TMP_DIR:-} - Line number: %d.\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}" "${ERROR_LINE}";
   printf "ERROR: Failed command: %s (exit code: %d)\n" "${ERROR_COMMAND}" "${ERROR_EXIT_CODE}";
   if [[ "${GENERATE_FAILED_FILE:-false}" = true ]]; then
    local FAILED_EXECUTION_FILE="${FAILED_EXECUTION_FILE:-/tmp/etl_failed_${MAIN_SCRIPT_NAME}_$$.log}"
    {
     echo "Error occurred at $(date +%Y%m%d_%H:%M:%S)"
     echo "Script: ${MAIN_SCRIPT_NAME}"
     echo "Line number: ${ERROR_LINE}"
     echo "Failed command: ${ERROR_COMMAND}"
     echo "Exit code: ${ERROR_EXIT_CODE}"
     echo "Temporary directory: ${TMP_DIR:-unknown}"
     echo "Process ID: $$"
    } > "${FAILED_EXECUTION_FILE}"
   fi;
   exit "${ERROR_EXIT_CODE}";
  fi;
 }' ERR
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 trap '{
  # Get the main script name (the one that was executed, not the library)
  local MAIN_SCRIPT_NAME
  MAIN_SCRIPT_NAME=$(basename "${0}" .sh)

  printf "%s WARN: The script %s was terminated. Temporary directory: ${TMP_DIR:-}\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}";
  if [[ "${GENERATE_FAILED_FILE:-false}" = true ]]; then
   local FAILED_EXECUTION_FILE="${FAILED_EXECUTION_FILE:-/tmp/etl_failed_${MAIN_SCRIPT_NAME}_$$.log}"
   {
    echo "Script terminated at $(date +%Y%m%d_%H:%M:%S)"
    echo "Script: ${MAIN_SCRIPT_NAME}"
    echo "Temporary directory: ${TMP_DIR:-unknown}"
    echo "Process ID: $$"
    echo "Signal: SIGTERM/SIGINT"
   } > "${FAILED_EXECUTION_FILE}"
  fi;
  exit "${ERROR_GENERAL}";
 }' SIGINT SIGTERM
 __log_finish
}

######
# MAIN

function main() {
 __log_start
 __logi "Preparing environment."
 __logd "Output saved at: ${TMP_DIR}."
 __logi "Processing: ${PROCESS_TYPE}."

 if [[ "${PROCESS_TYPE}" == "-h" ]] \
  || [[ "${PROCESS_TYPE}" == "--help" ]]; then
  __show_help
 fi

 # If no parameters provided, show help and return error
 # Note: Empty string "" is a valid value for PROCESS_TYPE (means default processing)
 if [[ "${PROCESS_TYPE}" != "" ]] && [[ "${PROCESS_TYPE}" != "--help" ]] && [[ "${PROCESS_TYPE}" != "-h" ]]; then
  __loge "Invalid process type specified: ${PROCESS_TYPE}"
  echo "${0} version ${VERSION}"
  echo "Invalid process type parameter."
  echo ""
  echo "Usage:"
  echo "  ${0} [OPTIONS]"
  echo ""
  echo "Run with --help for more information."
  return 1
 fi

 __checkPrereqs

 __logw "Starting process."
 # Sets the trap in case of any signal.
 __trapOn
 exec 7> "${LOCK}"
 __logw "Validating single execution."
 # shellcheck disable=SC2034
 ONLY_EXECUTION="no"
 flock -n 7
 # shellcheck disable=SC2034
 ONLY_EXECUTION="yes"

 set +E
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! __checkBaseTables; then
  __loge "Failed to check/create base tables"
  exit 1
 fi
 # Add new columns for years after 2013.
 __addYears
 set -E
 # Process countries in parallel using work queue for dynamic load balancing
 set +e
 __processNotesCountriesParallel
 local process_exit_code=$?
 set -e
 if [[ ${process_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to process countries (exit code: ${process_exit_code})"
  __log_finish
  return 1
 fi

 __logw "Ending process."
 __log_finish
 return 0
}

# Allows to other user read the directory.
chmod go+x "${TMP_DIR}"

__start_logger
if [[ "${SKIP_MAIN:-}" != "true" ]]; then
 if [[ ! -t 1 ]]; then
  __set_log_file "${LOG_FILENAME}"
  main >> "${LOG_FILENAME}"
  EXIT_CODE=$?
  if [[ -n "${CLEAN}" ]] && [[ "${CLEAN}" = true ]]; then
   mv "${LOG_FILENAME}" "/tmp/${BASENAME}_$(date +%Y-%m-%d_%H-%M-%S \
    || true).log"
   rmdir "${TMP_DIR}" 2> /dev/null || rm -rf "${TMP_DIR}" 2> /dev/null || true
  fi
  exit "${EXIT_CODE}"
 else
  main
  EXIT_CODE=$?
  exit "${EXIT_CODE}"
 fi
fi
