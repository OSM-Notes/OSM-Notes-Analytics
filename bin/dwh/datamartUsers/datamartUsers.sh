#!/bin/bash

# Creates a datamart for user data with pre-computed analytics.
#
# DM-005/DM-006: Implements intelligent prioritization and parallel processing:
# - Users with recent activity (last 7/30/90 days) processed first
# - High-activity users (>100 actions) prioritized
# - Parallel processing with work queue (nproc-1 threads) for dynamic load balancing
# - Better CPU utilization: fast users don't leave threads idle
# - Atomic transactions ensure data consistency
# - Processes MAX_USERS_PER_CYCLE users per cycle (default: 4000) to allow ETL
#   to complete quickly and update data promptly
#
# To follow the progress you can execute:
#   tail -40f $(ls -1rtd /tmp/datamartUsers_* | tail -1)/datamartUsers.log
#
# Documentation: See PARALLEL_PROCESSING.md for detailed information about
#                 the prioritization and parallel processing system.
#
# This is the list of error codes:
# 1) Help message.
# 241) Library or utility missing.
# 242) Invalid argument for script invocation.
# 243) Logger utility is not available.
#
# For contributing, please execute these commands at the end:
# * shellcheck -x -o all datamartUsers.sh
# * shfmt -w -i 1 -sr -bn datamartUsers.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2025-12-27
VERSION="2025-12-27"

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
LOCK="/tmp/${BASENAME}.lock"
readonly LOCK

# Type of process to run in the script.
# Empty string "" is a valid value (means default processing)
if [[ -z "${PROCESS_TYPE:-}" ]]; then
 declare PROCESS_TYPE=${1:-}
 declare -r PROCESS_TYPE
fi

# Name of the SQL script that contains the objects to create in the DB.
declare -r POSTGRES_11_CHECK_OBJECTS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_10_checkDatamartUsersTables.sql"

# Name of the SQL script that contains the tables to create in the DB.
declare -r POSTGRES_12_CREATE_TABLES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"

# Name of the SQL script that contains the procedures to create in the DB.
declare -r POSTGRES_13_CREATE_PROCEDURES_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"

# Last year activities script.
declare -r POSTGRES_14_LAST_YEAR_ACTITIES_SCRIPT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"

# Badge system: definitions and assign_badges_to_user / assign_badges_to_all_users (DM-004).
declare -r POSTGRES_15_BADGE_SYSTEM_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts/62_createBadgeSystem.sql"

# Generic script to add years.
declare -r POSTGRES_21_ADD_YEARS_SCRIPT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_20_alterTableAddYears.sql"

# Name of the SQL script to analyse only users with few actions.
declare -r POSTGRES_31_POPULATE_OLD_USERS_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_30_populateOldUsers.sql"

# Name of the SQL script that contains the ETL process.
declare -r POSTGRES_32_POPULATE_FILE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_31_populateDatamartUsersTable.sql"

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
 echo "This script populates the user datamart with pre-computed analytics."
 echo "The datamart aggregates note statistics by user from the fact table."
 echo
 echo "DM-005/DM-006: Intelligent Prioritization and Parallel Processing"
 echo "  - Users with recent activity (last 7/30/90 days) processed first"
 echo "  - High-activity users (>100 actions) prioritized"
 echo "  - Parallel processing with work queue (nproc-1 threads)"
 echo "  - Dynamic load balancing for optimal CPU utilization"
 echo "  - Processes MAX_USERS_PER_CYCLE users per cycle (default: 4000)"
 echo "  - Allows ETL to complete quickly and update data promptly"
 echo
 echo "Documentation: See PARALLEL_PROCESSING.md for detailed information"
 echo "               about prioritization and parallel processing."
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
  "${POSTGRES_11_CHECK_OBJECTS_FILE}"
  "${POSTGRES_12_CREATE_TABLES_FILE}"
  "${POSTGRES_13_CREATE_PROCEDURES_FILE}"
  "${POSTGRES_14_LAST_YEAR_ACTITIES_SCRIPT}"
  "${POSTGRES_15_BADGE_SYSTEM_FILE}"
  "${POSTGRES_21_ADD_YEARS_SCRIPT}"
  "${POSTGRES_31_POPULATE_OLD_USERS_FILE}"
  "${POSTGRES_32_POPULATE_FILE}"
 )

 # Validate each SQL file
 for SQL_FILE in "${SQL_FILES[@]}"; do
  # shellcheck disable=SC2310
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
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_12_CREATE_TABLES_FILE}"
 # PROCESS_OLD_USERS is now configurable via environment variable or properties.sh
 # Default is 'no' to prioritize modified users with intelligent prioritization
 # Set PROCESS_OLD_USERS=yes only if you need to process all users (initial load)
 PROCESS_OLD_USERS="${PROCESS_OLD_USERS:-no}"
 __log_finish
}

# Checks the tables are created.
function __checkBaseTables {
 __log_start
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_11_CHECK_OBJECTS_FILE}"
 RET=${?}
 set -e
 if [[ "${RET}" -ne 0 ]]; then
  __logw "Creating datamart users tables."
  __createBaseTables
  __logw "Datamart users tables created."
  # Reset return code to 0 since we successfully created the tables
  RET=0
 fi
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_13_CREATE_PROCEDURES_FILE}"
 local proc_ret=${?}
 set -e
 if [[ "${proc_ret}" -ne 0 ]]; then
  __loge "Failed to create procedures, but continuing..."
 fi
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_14_LAST_YEAR_ACTITIES_SCRIPT}"
 local last_year_ret=${?}
 set -e
 if [[ "${last_year_ret}" -ne 0 ]]; then
  __loge "Failed to create last year activities, but continuing..."
 fi
 # Create export view if SQL file exists (excludes internal _partial_* columns)
 local export_view_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_14_createExportView.sql"
 if [[ -f "${export_view_file}" ]]; then
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${export_view_file}"
  local view_ret=${?}
  set -e
  if [[ "${view_ret}" -ne 0 ]]; then
   __loge "Failed to create export view, but continuing..."
  fi
 fi
 # Apply badge system (DM-004): populate badges and create assign_badges_to_user / assign_badges_to_all_users
 if [[ -f "${POSTGRES_15_BADGE_SYSTEM_FILE}" ]]; then
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_15_BADGE_SYSTEM_FILE}"
  local badge_ret=${?}
  set -e
  if [[ "${badge_ret}" -ne 0 ]]; then
   __loge "Failed to apply badge system, but continuing..."
  fi
 fi
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
  __psql_with_appname -d "${DBNAME_DWH}" -c "$(envsubst '$YEAR' \
   < "${POSTGRES_21_ADD_YEARS_SCRIPT}" || true)" 2>&1
  set -e
 done
 __log_finish
}

# Processes initial batch of users.
# Processes users in small batches with periodic commits to avoid long transactions
# and reduce lock contention between parallel processes.
function __processOldUsers {
 __log_start
 MAX_USER_ID=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq \
  -c "SELECT MAX(user_id) FROM dwh.dimension_users" -v ON_ERROR_STOP=1)
 MAX_USER_ID=$(("MAX_USER_ID" + 1))

 # Processes the users in parallel.
 # Uses n-1 cores, if number of cores is greater than 1.
 # This prevents monopolization of the CPUs.
 if [[ "${MAX_THREADS}" -gt 6 ]]; then
  MAX_THREADS=$((MAX_THREADS - 2))
 elif [[ "${MAX_THREADS}" -gt 1 ]]; then
  MAX_THREADS=$((MAX_THREADS - 1))
 fi

 SIZE=$((MAX_USER_ID / MAX_THREADS))
 LOWER_VALUE=1
 HIGH_VALUE="${SIZE}"
 ITER=1
 local BATCH_SIZE=50
 __logw "Starting parallel process for datamartUsers (batch size: ${BATCH_SIZE} users per transaction)..."
 while [[ "${ITER}" -le "${MAX_THREADS}" ]]; do
  (
   __logi "Starting user batch ${LOWER_VALUE}-${HIGH_VALUE} - ${BASHPID}."

   export LOWER_VALUE
   export HIGH_VALUE
   export BATCH_SIZE
   local batch_offset=0
   local total_processed=0
   local batch_num=1
   local batch_count=0

   # Set up date properties once at the beginning
   set +e
   __psql_with_appname "datamartUsers-batch-${LOWER_VALUE}-${HIGH_VALUE}" -d "${DBNAME_DWH}" -c "
    DELETE FROM dwh.properties WHERE key IN ('year', 'month', 'day');
    INSERT INTO dwh.properties VALUES ('year', DATE_PART('year', CURRENT_DATE));
    INSERT INTO dwh.properties VALUES ('month', DATE_PART('month', CURRENT_DATE));
    INSERT INTO dwh.properties VALUES ('day', DATE_PART('day', CURRENT_DATE));
   " >> "${LOG_FILENAME}.${BASHPID}" 2>&1
   set -e

   # Process users in small batches with periodic commits
   while true; do
    export BATCH_OFFSET="${batch_offset}"

    # Process batch of users in a single transaction
    set +e
    local batch_result
    # shellcheck disable=SC2016  # Single quotes intentional for envsubst variable list
    batch_result=$(__psql_with_appname "datamartUsers-batch-${LOWER_VALUE}-${HIGH_VALUE}" -d "${DBNAME_DWH}" -c "$(envsubst '$LOWER_VALUE,$HIGH_VALUE,$BATCH_SIZE,$BATCH_OFFSET' \
     < "${POSTGRES_31_POPULATE_OLD_USERS_FILE}" || true)" \
     2>&1)
    local batch_exit_code=$?
    set -e

    if [[ ${batch_exit_code} -eq 0 ]]; then
     # Extract number of users processed from NOTICE messages
     batch_count=$(echo "${batch_result}" | grep -oP 'Processed \K[0-9]+' | tail -1 || echo "0")
     if [[ -z "${batch_count}" ]] || ! [[ "${batch_count}" =~ ^[0-9]+$ ]]; then
      batch_count=0
     fi

     if [[ ${batch_count} -gt 0 ]]; then
      total_processed=$((total_processed + batch_count))
      batch_offset=$((batch_offset + batch_count))

      if [[ $((total_processed % 500)) -eq 0 ]]; then
       __logi "Batch ${LOWER_VALUE}-${HIGH_VALUE}: Processed ${total_processed} users (committed)"
      fi
     fi

     # If batch returned fewer users than batch_size, we've reached the end
     if [[ ${batch_count} -lt ${BATCH_SIZE} ]] || [[ ${batch_count} -eq 0 ]]; then
      break
     fi
    else
     __loge "Batch ${LOWER_VALUE}-${HIGH_VALUE}: Error processing batch ${batch_num} (offset ${batch_offset}), continuing..."
     # Try next batch even if current batch failed
     batch_offset=$((batch_offset + BATCH_SIZE))
     # Limit retries to avoid infinite loops
     if [[ ${batch_num} -gt 1000 ]]; then
      __loge "Batch ${LOWER_VALUE}-${HIGH_VALUE}: Too many batch attempts, stopping"
      break
     fi
    fi

    batch_num=$((batch_num + 1))
   done

   __logi "Finished user batch ${LOWER_VALUE}-${HIGH_VALUE} - ${BASHPID}. Total processed: ${total_processed}"
  ) &
  ITER=$((ITER + 1))
  LOWER_VALUE=$((HIGH_VALUE + 1))
  HIGH_VALUE=$((HIGH_VALUE + SIZE))
  __logi "Check log per thread for more information."
  sleep 5
 done

 local failed_jobs=0
 for pid in $(jobs -p); do
  if ! wait "${pid}"; then
   failed_jobs=$((failed_jobs + 1))
  fi
 done

 if [[ ${failed_jobs} -eq 0 ]]; then
  __logi "SUCCESS: All old user batches processed successfully"
 else
  __loge "ERROR: ${failed_jobs} old user batch(es) failed. Check individual log files for details."
 fi
 __logw "Waited for all jobs, restarting in main thread."

 __log_finish
 if [[ ${failed_jobs} -gt 0 ]]; then
  return 1
 fi
 return 0
}
# Thread-safe function to get next user from shared work queue.
# Uses file locking (flock) to ensure atomic queue operations.
# This function is used by worker threads to get the next user to process.
# Usage: user_id=$(__get_next_user_from_queue)
# Returns: user ID as string, or empty string if queue is empty
# Exit code: 0 = success (got user or queue empty), 1 = lock failed (should retry)
__get_next_user_from_queue() {
 local result_file="${work_queue_file}.result.${BASHPID}"
 local user_id=""

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

  # Read first line (next user to process)
  if [[ -f "${work_queue_file}" ]] && [[ -s "${work_queue_file}" ]]; then
   head -n 1 "${work_queue_file}" 2> /dev/null > "${result_file}" || echo "" > "${result_file}"

   # If we got a user ID, remove it from queue
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
  user_id=$(cat "${result_file}" 2> /dev/null || echo "")
  rm -f "${result_file}" 2> /dev/null || true
 fi

 echo "${user_id}"
 return 0
}

# Processes users in parallel using a shared work queue for dynamic load balancing.
# Each worker thread takes the next available user from the queue after finishing one.
# This ensures better load balancing: fast users don't leave threads idle while
# slow users are being processed by other threads.
# DM-006: Migrated from static pool to work queue for optimal CPU utilization.
function __processNotesUser {
 __log_start
 if [[ "${PROCESS_OLD_USERS}" == "yes" ]]; then
  __logw "WARNING: PROCESS_OLD_USERS=yes is enabled. This will process ALL users including inactive ones."
  __logw "This uses OFFSET pagination which is extremely slow and can take days/weeks to complete."
  __logw "Consider using PROCESS_OLD_USERS=no to only process modified users with intelligent prioritization."
  __processOldUsers
 else
  __logi "PROCESS_OLD_USERS=no: Only processing modified users with intelligent prioritization (recommended)"
 fi

 __logi "=== PROCESSING USERS IN PARALLEL (WORK QUEUE) ==="

 # Get MAX_THREADS for parallel processing
 local MAX_THREADS="${MAX_THREADS:-$(nproc)}"
 local adjusted_threads
 adjusted_threads=$((MAX_THREADS - 1))
 if [[ "${adjusted_threads}" -lt 1 ]]; then
  adjusted_threads=1
 fi
 __logi "Using ${adjusted_threads} parallel threads (nproc-1: ${MAX_THREADS} - 1)"

 # Get total modified users count first (needed for catch-up limit decision)
 local total_modified_users
 set +e
 total_modified_users=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "
  SELECT COUNT(DISTINCT f.action_dimension_id_user)
  FROM dwh.facts f
   JOIN dwh.dimension_users u
   ON (f.action_dimension_id_user = u.dimension_user_id)
  WHERE u.modified = TRUE
 ")
 local query_ret=${?}
 set -e
 if [[ ${query_ret} -ne 0 ]] || [[ -z "${total_modified_users}" ]]; then
  total_modified_users="0"
 fi

 # Base limit per cycle (normal operation); allow ETL to complete in time (e.g. 15 min)
 local max_users_per_cycle="${MAX_USERS_PER_CYCLE:-4000}"
 local effective_limit="${max_users_per_cycle}"
 local catchup_threshold="${CATCHUP_THRESHOLD:-10000}"

 # Catch-up mode: when backlog is large (e.g. 500K historical), process more per cycle
 if [[ "${total_modified_users}" -ge "${catchup_threshold}" ]]; then
  if [[ -n "${MAX_USERS_PER_CYCLE_CATCHUP:-}" ]] && [[ "${MAX_USERS_PER_CYCLE_CATCHUP}" -gt 0 ]]; then
   if [[ "${MAX_USERS_PER_CYCLE_CATCHUP}" -lt "${total_modified_users}" ]]; then
    effective_limit="${MAX_USERS_PER_CYCLE_CATCHUP}"
   else
    effective_limit="${total_modified_users}"
   fi
   __logi "Catch-up mode: backlog ${total_modified_users} >= ${catchup_threshold}, using MAX_USERS_PER_CYCLE_CATCHUP=${effective_limit}"
  elif [[ -n "${CATCHUP_MULTIPLIER:-}" ]] && [[ "${CATCHUP_MULTIPLIER}" -gt 0 ]]; then
   local catchup_cap=$((max_users_per_cycle * CATCHUP_MULTIPLIER))
   if [[ "${catchup_cap}" -lt "${total_modified_users}" ]]; then
    effective_limit="${catchup_cap}"
   else
    effective_limit="${total_modified_users}"
   fi
   __logi "Catch-up mode: backlog ${total_modified_users} >= ${catchup_threshold}, using ${max_users_per_cycle}*${CATCHUP_MULTIPLIER}=${effective_limit}"
  fi
 fi

 # Get list of modified users to process with intelligent prioritization
 # DM-005: Prioritize users by relevance using refined criteria:
 # 1. Users with recent activity (last 7 days) - CRITICAL priority
 # 2. Users with activity in last 30 days - HIGH priority
 # 3. Users with activity in last 90 days - MEDIUM priority
 # 4. Users with high historical activity (>100 actions) - MEDIUM priority
 # 5. Users with moderate activity (10-100 actions) - LOW priority
 # 6. Inactive users (<10 actions or >2 years inactive) - LOWEST priority
 #
 # IMPORTANT: Process only effective_limit users per cycle (normal: MAX_USERS_PER_CYCLE;
 # catch-up: higher when backlog >= CATCHUP_THRESHOLD) so ETL can complete and backlog drains.
 __logi "Fetching modified users with intelligent prioritization (max ${effective_limit} per cycle)..."
 local user_ids
 user_ids=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "
  SELECT /* Notes-datamartUsers-parallel */
   f.action_dimension_id_user
  FROM dwh.facts f
   JOIN dwh.dimension_users u
   ON (f.action_dimension_id_user = u.dimension_user_id)
  WHERE u.modified = TRUE
  GROUP BY f.action_dimension_id_user
  ORDER BY
   -- Priority 1: Very recent activity (last 7 days) = highest
   CASE WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '7 days' THEN 1
        WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '30 days' THEN 2
        WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '90 days' THEN 3
        ELSE 4 END,
   -- Priority 2: High activity users (>100 actions) get priority
   CASE WHEN COUNT(*) > 100 THEN 1
        WHEN COUNT(*) > 10 THEN 2
        ELSE 3 END,
   -- Priority 3: Most active users historically
   COUNT(*) DESC,
   -- Priority 4: Most recent activity first
   MAX(f.action_at) DESC NULLS LAST
  LIMIT ${effective_limit}
 ")

 local total_users
 total_users=$(echo "${user_ids}" | grep -c . || echo "0")
 total_users=$(echo "${total_users}" | tr -d '[:space:]') # Remove all whitespace including newlines
 total_users=$((total_users))                             # Ensure numeric

 if [[ "${total_modified_users}" -gt "${effective_limit}" ]]; then
  __logi "Found ${total_users} users to process this cycle (prioritized by relevance)"
  __logi "Total modified users: ${total_modified_users} (will process ${effective_limit} per cycle)"
 else
  __logi "Found ${total_users} users to process (prioritized by relevance)"
 fi

 if [[ "${total_users}" -eq 0 ]]; then
  __logi "No users to process"
  __log_finish
  return 0
 fi

 # Create shared work queue file
 local work_queue_file="${TMP_DIR}/user_work_queue.txt"
 echo "${user_ids}" > "${work_queue_file}"

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
 if [[ "${queue_count}" -ne "${total_users}" ]]; then
  __logw "WARN: Queue file count (${queue_count}) differs from expected (${total_users}), but continuing..."
 fi

 # Create lock file for queue access
 local queue_lock_file="${TMP_DIR}/user_queue.lock"
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
   local thread_processed=0
   local thread_failed=0
   local user_id
   local empty_retries=0
   local max_empty_retries=3
   local retry_delay=0.2

   while true; do
    # Get next user from shared queue (thread-safe)
    # Functions and exported variables are automatically available in subshells
    user_id=$(__get_next_user_from_queue)
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
    if [[ -z "${user_id}" ]]; then
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

    # Reset empty retries counter once we successfully get a user
    empty_retries=0

    # Process user in atomic transaction
    # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
    if ! __psql_with_appname "datamartUsers-user-${user_id}-thread${thread_num}" \
     -d "${DBNAME_DWH}" -c "
      BEGIN;
       CALL dwh.update_datamart_user(${user_id});
       UPDATE dwh.dimension_users
        SET modified = FALSE
        WHERE dimension_user_id = ${user_id};
       -- DM-004: Assign badges only for this user (just updated); avoids full scan every run
       SELECT dwh.assign_badges_to_user(${user_id});
      COMMIT;
    " 2>&1; then
     thread_failed=$((thread_failed + 1))
     __loge "Thread ${thread_num}: ERROR: Failed to process user ${user_id}"
    else
     thread_processed=$((thread_processed + 1))
     # Log every 100 users per thread
     if [[ $((thread_processed % 100)) -eq 0 ]]; then
      __logi "Thread ${thread_num}: Processed ${thread_processed} users (current: user ${user_id})"
     fi
    fi
   done

   # Report thread completion
   if [[ ${thread_failed} -eq 0 ]]; then
    __logi "Thread ${thread_num}: Completed successfully (${thread_processed} users processed)"
   else
    __loge "Thread ${thread_num}: Completed with ${thread_failed} failures (${thread_processed} users processed)"
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
 __logi "Waiting for all user processing to complete..."
 local total_failed=0
 for pid in "${pids[@]}"; do
  wait "${pid}"
  local thread_exit_code=$?
  if [[ ${thread_exit_code} -ne 0 ]]; then
   total_failed=$((total_failed + thread_exit_code))
  fi
 done

 local end_time
 end_time=$(date +%s)
 local total_time=$((end_time - start_time))

 # Count total processed (check remaining queue)
 local remaining_users
 remaining_users=$(wc -l < "${work_queue_file}" 2> /dev/null || echo "0")
 remaining_users=$(echo "${remaining_users}" | tr -d '[:space:]') # Remove all whitespace including newlines
 remaining_users=$((remaining_users))                             # Ensure numeric
 local actually_processed=$((total_users - remaining_users))

 if [[ ${total_failed} -eq 0 ]]; then
  __logi "SUCCESS: Datamart users population completed successfully"
  __logi "Processed ${actually_processed} users in parallel (${total_users} this cycle)"
  if [[ "${total_modified_users:-0}" -gt "${effective_limit}" ]]; then
   local remaining=$((total_modified_users - actually_processed))
   __logi "Remaining modified users: ${remaining} (will be processed in next cycle)"
  fi
  __logi "Users processed with intelligent prioritization (recent → active → inactive)"
  __logi "⏱️  TIME: Parallel user processing took ${total_time} seconds"
  __log_finish
  rm -f "${work_queue_file}" "${queue_lock_file}" 2> /dev/null || true
  return 0
 else
  __loge "ERROR: Datamart users population had ${total_failed} failed user(s)"
  __loge "Processed ${actually_processed}/${total_users} users successfully"
  __loge "⏱️  TIME: Parallel user processing took ${total_time} seconds (with ${total_failed} failures)"
  __log_finish
  rm -f "${work_queue_file}" "${queue_lock_file}" 2> /dev/null || true
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

 # This variable controls processing of users with <=20 actions (95% of users).
 # Default: 'no' - Only process modified users with intelligent prioritization (recommended)
 # Set to 'yes' only for initial load or when you need to process all users.
 # WARNING: Processing old users uses OFFSET which is very slow. It's better to
 # process them incrementally via modified flag in subsequent ETL cycles.
 # Note: PROCESS_OLD_USERS is already set in __createBaseTables() or from properties.sh
 # Only set default if not already set (to avoid readonly variable error)
 if [[ -z "${PROCESS_OLD_USERS:-}" ]]; then
  PROCESS_OLD_USERS="no"
 fi

 set +E
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! __checkBaseTables; then
  __loge "Failed to check/create base tables"
  exit 1
 fi
 # Add new columns for years after 2013.
 __addYears
 set -E
 # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
 if __processNotesUser; then
  __logi "SUCCESS: Datamart users processing completed successfully"
 else
  __loge "ERROR: Datamart users processing failed"
  __loge "Check log file: ${LOG_FILENAME}"
  exit 1
 fi

 __logw "Ending process."
 __log_finish
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
