#!/bin/bash

# ETL process that transforms notes and comments from base tables into a star
# schema data warehouse with facts and dimensions.
# This ETL runs independently from the ingestion process that retrieves notes
# from Planet and API. This separation allows for longer execution times than
# the periodic ingestion polls.
#
# To follow the progress you can execute:
#   tail -40f $(ls -1rtd /tmp/ETL_* | tail -1)/ETL.log
#
# This is the list of error codes:
# 1) Help message.
# 241) Library or utility missing.
# 242) Invalid argument for script invocation.
# 243) Logger utility is not available.
#
# For contributing, please execute these commands before submitting:
# * shellcheck -x -o all ETL.sh
# * shfmt -w -i 1 -sr -bn ETL.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2026-01-07
VERSION="2026-01-07"

#set -xv
# Fails when a variable is not initialized.
set -u
# Fails with a non-zero return code.
set -e
# Fails if the commands of a pipe return non-zero.
set -o pipefail
# Fails if an internal function fails.
set -E

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-ERROR}"

# Base directory for the project.
# Allow SCRIPT_BASE_DIRECTORY to be set externally (e.g., by tests)
declare SCRIPT_BASE_DIRECTORY
if [[ -z "${SCRIPT_BASE_DIRECTORY:-}" ]]; then
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
  &> /dev/null && pwd)"
fi
readonly SCRIPT_BASE_DIRECTORY

# Loads the global properties.
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh" ]]; then
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"
else
 # If properties.sh doesn't exist, set minimal defaults for testing
 if [[ -z "${DBNAME_DWH:-}" ]]; then
  export DBNAME_DWH="${DBNAME_DWH:-notes_dwh}"
 fi
 if [[ -z "${DBNAME_INGESTION:-}" ]]; then
  export DBNAME_INGESTION="${DBNAME_INGESTION:-notes}"
 fi
fi

# Load local properties if they exist (overrides global settings)
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local"
fi

# Export database name variables to make them available to subprocesses
# These variables are initialized in etc/properties.sh
export DBNAME_DWH
export DBNAME_INGESTION

declare BASENAME
# Use BASH_SOURCE[0] when sourced, $0 when executed directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
 # Script is being sourced
 BASENAME=$(basename -s .sh "${BASH_SOURCE[0]}")
else
 # Script is being executed
 BASENAME=$(basename -s .sh "${0}")
fi
readonly BASENAME

# Main script name for trap handlers (must be global, not local)
declare MAIN_SCRIPT_NAME
# Use BASH_SOURCE[0] when sourced, $0 when executed directly
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
 # Script is being sourced
 MAIN_SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}" .sh)
else
 # Script is being executed
 MAIN_SCRIPT_NAME=$(basename "${0}" .sh)
fi
readonly MAIN_SCRIPT_NAME

# Original process start time and PID (to preserve in lock file).
declare PROCESS_START_TIME
PROCESS_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
readonly PROCESS_START_TIME
declare -r ORIGINAL_PID=$$

# Temporary directory for all files.
# Only create temp directory if not being sourced for testing
if [[ -z "${TMP_DIR:-}" ]]; then
 declare TMP_DIR
 if [[ "${SKIP_MAIN:-}" != "true" ]]; then
  TMP_DIR=$(mktemp -d "/tmp/${BASENAME}_XXXXXX" 2> /dev/null || echo "/tmp/${BASENAME}_$$")
  chmod 777 "${TMP_DIR}" 2> /dev/null || true
 else
  # When sourced for testing, use a default temp directory
  TMP_DIR="/tmp/${BASENAME}_test_$$"
 fi
 readonly TMP_DIR
else
 # TMP_DIR already set (e.g., by test framework)
 declare -r TMP_DIR
fi

# Log file for output.
declare LOG_FILENAME
if [[ -n "${TMP_DIR:-}" ]]; then
 LOG_FILENAME="${TMP_DIR}/${BASENAME}.log"
else
 LOG_FILENAME="/tmp/${BASENAME}.log"
fi
readonly LOG_FILENAME

# Lock file for single execution.
# Use fixed location in /tmp/ to ensure all executions share the same lock
declare LOCK
LOCK="/tmp/${BASENAME}.lock"
readonly LOCK

# Failed execution marker file
# This file is created when a critical error occurs to prevent repeated failures
declare FAILED_EXECUTION_FILE
FAILED_EXECUTION_FILE="/tmp/${BASENAME}.failed"
readonly FAILED_EXECUTION_FILE

# Type of process to run in the script.
if [[ -z "${PROCESS_TYPE:-}" ]]; then
 declare -r PROCESS_TYPE=${1:-}
fi

# Load common functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

# Load validation functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"

# Load error handling functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"

# Load alert functions for failed execution markers
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/alertFunctions.sh"

# Configure log file early if running from cron (not a terminal)
# This prevents logger from writing to stdout which would be sent by email
# Redirect stdout and stderr to log file immediately when running from cron
# Skip redirection when sourced for testing or when showing help
if [[ "${SKIP_MAIN:-}" != "true" ]] && [[ ! -t 1 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
 # Redirect all output to log file to prevent cron from sending emails
 exec >> "${LOG_FILENAME}" 2>&1
 __set_log_file "${LOG_FILENAME}"
fi

# Initialize logger (skip if sourced for testing and logger already initialized)
if [[ "${SKIP_MAIN:-}" != "true" ]] || ! type -t __logi > /dev/null 2>&1; then
 __start_logger
fi

# PostgreSQL SQL script files.
# Check ingestion base tables.
declare -r POSTGRES_10_CHECK_BASE_TABLES="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_10_checkBaseTables.sql"
# Check DWH base tables.
declare -r POSTGRES_11_CHECK_DWH_BASE_TABLES="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_11_checkDWHTables.sql"
# Drop datamart objects.
declare -r POSTGRES_12_DROP_DATAMART_OBJECTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_12_removeDatamartObjects.sql"
# Drop DWH objects.
declare -r POSTGRES_13_DROP_DWH_OBJECTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_13_removeDWHObjects.sql"

# Create DWH tables.
declare -r POSTGRES_22_CREATE_DWH_TABLES="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql"
# Create fact partitions.
declare -r POSTGRES_22A_CREATE_FACT_PARTITIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_21_createFactPartitions.sql"
# Populates regions per country.
declare -r POSTGRES_23_GET_WORLD_REGIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_22_getWorldRegion.sql"
# Add functions.
declare -r POSTGRES_24_ADD_FUNCTIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_23_addFunctions.sql"
# Populate ISO country codes.
declare -r POSTGRES_24A_POPULATE_ISO_CODES="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_24_populateISOCodes.sql"
# Populate dimension tables.
declare -r POSTGRES_25_POPULATE_DIMENSIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_25_populateDimensionTables.sql"
# Update dimension tables.
declare -r POSTGRES_26_UPDATE_DIMENSIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_26_updateDimensionTables.sql"

# Staging SQL script files.
# Create shared helper functions for staging (ETL-006: factorize CREATE and INITIAL)
declare -r POSTGRES_30_SHARED_HELPER_FUNCTIONS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_30_sharedHelperFunctions.sql"
# Create base staging objects.
declare -r POSTGRES_31_CREATE_BASE_STAGING_OBJECTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_31_createBaseStagingObjects.sql"
# Create staging objects.
declare -r POSTGRES_32_CREATE_STAGING_OBJECTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"
# Create initial facts base objects.
declare -r POSTGRES_33_CREATE_FACTS_BASE_OBJECTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_33_initialFactsBaseObjects.sql"
declare -r POSTGRES_33_CREATE_FACTS_BASE_OBJECTS_SIMPLE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_33a_initialFactsBaseObjects_Simple.sql"
# Create initial facts load.
declare -r POSTGRES_34_CREATE_FACTS_YEAR_LOAD="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_34_initialFactsLoadCreate.sql"
# Execute initial facts load.
declare -r POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_35_initialFactsLoadExecute.sql"
declare -r POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD_SIMPLE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_35a_initialFactsLoadExecute_Simple.sql"
declare -r POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD_PHASE2="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_35b_initialFactsLoadExecute_Phase2.sql"
declare -r POSTGRES_35B_UPDATE_CLOSED_DIMENSION_ID_DATE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_35c_updateClosedDimensionIdDate.sql"
declare -r POSTGRES_34_INITIAL_FACTS_LOAD_PARALLEL="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_34a_initialFactsLoadCreate_Parallel.sql"
# Drop initial facts load.
declare -r POSTGRES_36_DROP_FACTS_YEAR_LOAD="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_36_initialFactsLoadDrop.sql"
# Add constraints, indexes and triggers.
declare -r POSTGRES_41_ADD_CONSTRAINTS_INDEXES_TRIGGERS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_40_addConstraintsIndexesTriggers.sql"
# Create automation detection system.
declare -r POSTGRES_50_CREATE_AUTOMATION_DETECTION="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_50_createAutomationDetection.sql"
# Create experience levels system.
declare -r POSTGRES_51_CREATE_EXPERIENCE_LEVELS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_51_createExperienceLevels.sql"
# Create note activity metrics trigger.
declare -r POSTGRES_52_CREATE_NOTE_ACTIVITY_METRICS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_52_createNoteActivityMetrics.sql"
# Create hashtag analysis views.
declare -r POSTGRES_53_CREATE_HASHTAG_VIEWS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_53_createHashtagViews.sql"
# Enhance datamarts with hashtag metrics.
declare -r POSTGRES_53A_ENHANCE_DATAMARTS_HASHTAGS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/improvements/13_enhance_datamarts_hashtags.sql"
# Create specialized hashtag indexes.
declare -r POSTGRES_53B_CREATE_HASHTAG_INDEXES="${SCRIPT_BASE_DIRECTORY}/sql/dwh/improvements/13_create_hashtag_indexes.sql"
# Unify facts.
declare -r POSTGRES_54_UNIFY_FACTS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_50_unify.sql"
# Create note current status table and procedures (ETL-003, ETL-004)
declare -r POSTGRES_55_CREATE_NOTE_CURRENT_STATUS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_55_createNoteCurrentStatus.sql"
declare -r POSTGRES_56_GENERATE_ETL_REPORT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_56_generateETLReport.sql"
# Validate ETL integrity (MON-001, MON-002)
declare -r POSTGRES_57_VALIDATE_ETL_INTEGRITY="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_57_validateETLIntegrity.sql"
# Complete hashtag analysis (DM-002)
declare -r POSTGRES_63_COMPLETE_HASHTAG_ANALYSIS="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts/63_completeHashtagAnalysis.sql"

# Load notes staging.
declare -r POSTGRES_61_LOAD_NOTES_STAGING="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_60_loadNotes.sql"

# Setup Foreign Data Wrappers for incremental processing.
declare -r POSTGRES_60_SETUP_FDW="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_60_setupFDW.sql"

# Backfill application version from note_comments_text (so version_adoption_rates is populated).
declare -r POSTGRES_27_BACKFILL_APPLICATION_VERSION="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_27_backfill_application_version.sql"

# Scripts for hybrid strategy (copy tables for initial load).
declare -r COPY_BASE_TABLES_SCRIPT="${SCRIPT_BASE_DIRECTORY}/bin/dwh/copyBaseTables.sh"
declare -r DROP_COPIED_BASE_TABLES_SCRIPT="${SCRIPT_BASE_DIRECTORY}/bin/dwh/dropCopiedBaseTables.sh"

# Datamart script files.
declare -r DATAMART_COUNTRIES_SCRIPT="${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh"
declare -r DATAMART_USERS_SCRIPT="${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh"
declare -r DATAMART_GLOBAL_SCRIPT="${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartGlobal/datamartGlobal.sh"
# Create datamart performance log table.
declare -r POSTGRES_DATAMART_PERFORMANCE_CREATE_TABLE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql"
# Create logs table for debugging (only needed when Ingestion and Analytics databases are different).
declare -r POSTGRES_CREATE_LOGS_TABLE="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_54_createLogsTable.sql"

###########
# FUNCTIONS

# ETL Configuration file.
declare -r ETL_CONFIG_FILE="${SCRIPT_BASE_DIRECTORY}/etc/etl.properties"

# ETL Recovery and monitoring variables.

# Load ETL configuration if available.
if [[ -f "${ETL_CONFIG_FILE}" ]]; then
 # shellcheck disable=SC1090
 source "${ETL_CONFIG_FILE}"
 # Only log if there's a problem - configuration loading is expected
else
 # Only log warning if logger is available (not when sourced for testing)
 if type -t __logw > /dev/null 2>&1; then
  __logw "ETL configuration file not found, using defaults"
 fi
fi

# Load local ETL configuration if available (overrides global settings)
declare -r ETL_CONFIG_FILE_LOCAL="${SCRIPT_BASE_DIRECTORY}/etc/etl.properties.local"
if [[ -f "${ETL_CONFIG_FILE_LOCAL}" ]]; then
 # shellcheck disable=SC1090
 source "${ETL_CONFIG_FILE_LOCAL}"
 # Only log if there's a problem - configuration loading is expected
fi

# Set default values for ETL configuration if not defined.
declare -r ETL_BATCH_SIZE="${ETL_BATCH_SIZE:-1000}"
declare -r ETL_COMMIT_INTERVAL="${ETL_COMMIT_INTERVAL:-100}"
declare -r ETL_VACUUM_AFTER_LOAD="${ETL_VACUUM_AFTER_LOAD:-true}"
declare -r ETL_ANALYZE_AFTER_LOAD="${ETL_ANALYZE_AFTER_LOAD:-true}"
declare -r ETL_ANALYZE_FDW_TABLES="${ETL_ANALYZE_FDW_TABLES:-false}"
declare -r MAX_MEMORY_USAGE="${MAX_MEMORY_USAGE:-80}"
declare -r MAX_DISK_USAGE="${MAX_DISK_USAGE:-90}"
declare -r ETL_TIMEOUT="${ETL_TIMEOUT:-7200}"
declare -r ETL_RECOVERY_ENABLED="${ETL_RECOVERY_ENABLED:-true}"
declare -r ETL_RECOVERY_FILE="${ETL_RECOVERY_FILE:-${TMP_DIR}/ETL_recovery.json}"
declare -r ETL_VALIDATE_INTEGRITY="${ETL_VALIDATE_INTEGRITY:-true}"
declare -r ETL_VALIDATE_DIMENSIONS="${ETL_VALIDATE_DIMENSIONS:-true}"
declare -r ETL_VALIDATE_FACTS="${ETL_VALIDATE_FACTS:-true}"
declare -r ETL_PARALLEL_ENABLED="${ETL_PARALLEL_ENABLED:-true}"
declare -r ETL_MAX_PARALLEL_JOBS="${ETL_MAX_PARALLEL_JOBS:-4}"
declare -r ETL_MONITOR_RESOURCES="${ETL_MONITOR_RESOURCES:-true}"
# Fail ETL if datamarts fail (default: true for strict mode, set to false for backward compatibility)
declare -r ETL_DATAMART_FAIL_ON_ERROR="${ETL_DATAMART_FAIL_ON_ERROR:-true}"
declare -r ETL_MONITOR_INTERVAL="${ETL_MONITOR_INTERVAL:-30}"
declare -r ETL_TEST_MODE="${ETL_TEST_MODE:-false}"

# Set default value for CLEAN if not defined
declare CLEAN="${CLEAN:-true}"

# Shows the help information.
function __show_help {
 echo "${0} version ${VERSION}"
 echo "This ETL process transforms data from base tables into a star schema"
 echo "data warehouse with fact and dimension tables."
 echo
 echo "Usage:"
 echo "  ${0} [OPTIONS]"
 echo
 echo "Options:"
 echo "  (no arguments)    Auto-detect mode: first execution creates DWH,"
 echo "                    subsequent runs process incremental updates"
 echo "  --help, -h        Show this help"
 echo
 echo "Environment variables:"
 echo "  ETL_BATCH_SIZE       Records per batch (default: 1000)"
 echo "  ETL_COMMIT_INTERVAL  Commit every N records (default: 100)"
 echo "  ETL_TEST_MODE        Test mode: process only 2013-2014 (default: false)"
 echo "  CLEAN                Clean temporary files (default: true)"
 echo "  LOG_LEVEL            Logging level (default: ERROR)"
 echo
 echo "Examples:"
 echo "  ${0}                              # Auto-detect: creates DWH if first run,"
 echo "                                    # otherwise processes incremental updates"
 echo "  ETL_TEST_MODE=true ${0}           # Test mode (2013-2014 only)"
 echo
 echo "Written by: Andres Gomez (AngocA)"
 echo "OSM-LatAm, OSM-Colombia, MaptimeBogota."
 exit 0
}

# Wrapper for psql that sets application_name for better process identification
# Usage: __psql_with_appname [appname] [psql_args...]
# If appname is not provided, uses BASENAME (script name without .sh)
# If first argument starts with '-', it's a psql option, not an appname
# Also configures timeouts from properties.sh if available
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

 # Build timeout SQL commands if configured
 local timeout_sql=""
 if [[ -n "${PSQL_STATEMENT_TIMEOUT:-}" ]]; then
  timeout_sql="${timeout_sql}SET statement_timeout = '${PSQL_STATEMENT_TIMEOUT}'; "
 fi
 if [[ -n "${PSQL_LOCK_TIMEOUT:-}" ]]; then
  timeout_sql="${timeout_sql}SET lock_timeout = '${PSQL_LOCK_TIMEOUT}'; "
 fi
 if [[ -n "${PSQL_IDLE_IN_TRANSACTION_TIMEOUT:-}" ]]; then
  timeout_sql="${timeout_sql}SET idle_in_transaction_session_timeout = '${PSQL_IDLE_IN_TRANSACTION_TIMEOUT}'; "
 fi

 # Execute psql with appname and all arguments
 # If timeouts are configured, prepend them to SQL files or commands
 if [[ -n "${timeout_sql}" ]]; then
  # Check if we're executing a file (-f) or command (-c)
  local args=("$@")
  local i=0
  local modified=false
  local new_args=()
  local temp_files=()

  while [[ ${i} -lt ${#args[@]} ]]; do
   if [[ "${args[${i}]}" == "-f" ]] && [[ $((i + 1)) -lt ${#args[@]} ]]; then
    # Found -f, create temp file with timeouts + original file
    local original_file="${args[$((i + 1))]}"
    local temp_sql
    temp_sql=$(mktemp)
    {
     echo "${timeout_sql}"
     cat "${original_file}"
    } > "${temp_sql}"
    new_args+=("-f" "${temp_sql}")
    temp_files+=("${temp_sql}")
    modified=true
    ((i += 2))
   elif [[ "${args[${i}]}" == "-c" ]] && [[ $((i + 1)) -lt ${#args[@]} ]]; then
    # Found -c, prepend timeouts to command
    new_args+=("-c" "${timeout_sql}${args[$((i + 1))]}")
    modified=true
    ((i += 2))
   else
    new_args+=("${args[${i}]}")
    ((i++))
   fi
  done

  if [[ "${modified}" == "true" ]]; then
   local EXIT_CODE=0
   # Execute psql and capture exit code
   set +e
   PGAPPNAME="${appname}" psql "${new_args[@]}" || EXIT_CODE=$?
   set -e
   # Clean up temp files (always clean up, even on error)
   for temp_file in "${temp_files[@]}"; do
    rm -f "${temp_file}" 2> /dev/null || true
   done
   return "${EXIT_CODE}"
  else
   # No -f or -c found, but we have timeouts
   # If input is from stdin (pipe), prepend timeouts to stdin
   # Otherwise, set timeouts in a separate command
   local EXIT_CODE=0
   if [[ -t 0 ]]; then
    # No stdin, set timeouts in a separate command
    set +e
    PGAPPNAME="${appname}" psql -c "${timeout_sql}" "$@" || EXIT_CODE=$?
    set -e
   else
    # Input from stdin, prepend timeouts
    set +e
    {
     echo "${timeout_sql}"
     cat
    } | PGAPPNAME="${appname}" psql "$@" || EXIT_CODE=$?
    set -e
   fi
   return "${EXIT_CODE}"
  fi
 else
  # No timeouts configured, execute normally
  # Capture exit code to ensure it's returned properly
  local EXIT_CODE=0
  set +e
  PGAPPNAME="${appname}" psql "$@" || EXIT_CODE=$?
  set -e
  return "${EXIT_CODE}"
 fi
}

# Check if a PostgreSQL function exists in a schema
# Usage: __function_exists "schema" "function_name" "database"
# Returns: 0 if exists, 1 if not
function __function_exists {
 local schema="${1}"
 local function_name="${2}"
 local dbname="${3:-${DBNAME_DWH}}"

 local result
 result=$(__psql_with_appname -d "${dbname}" -t -c \
  "SELECT COUNT(*) FROM information_schema.routines
   WHERE routine_schema = '${schema}'
   AND routine_name = '${function_name}';" 2> /dev/null | tr -d ' ')

 if [[ "${result}" == "1" ]]; then
  return 0
 else
  return 1
 fi
}

# Processes experience levels for modified users in parallel.
# Similar to datamartUsers parallel processing, but for experience levels.
function __processExperienceLevels {
 __log_start
 __logi "Updating experience levels for modified users (parallel processing)."

 # Get MAX_THREADS for parallel processing
 local MAX_THREADS="${MAX_THREADS:-$(nproc)}"
 local adjusted_threads
 adjusted_threads=$((MAX_THREADS - 1))
 if [[ "${adjusted_threads}" -lt 1 ]]; then
  adjusted_threads=1
 fi
 __logi "Using ${adjusted_threads} parallel threads for experience level processing"

 # Get list of modified users without experience level
 # Prioritize users with recent activity for faster initial results
 __logi "Fetching modified users without experience level..."
 local user_ids
 user_ids=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "
  SELECT DISTINCT u.dimension_user_id
  FROM dwh.dimension_users u
  JOIN dwh.facts f ON f.action_dimension_id_user = u.dimension_user_id
  WHERE u.modified = TRUE
    AND u.experience_level_id IS NULL
  GROUP BY u.dimension_user_id
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
 ")

 local total_users
 total_users=$(echo "${user_ids}" | grep -c . || echo "0")
 total_users=$(echo "${total_users}" | tr -d '[:space:]') # Remove all whitespace including newlines
 total_users=$((total_users))                             # Ensure numeric
 __logi "Found ${total_users} users to process (prioritized by relevance)"

 if [[ "${total_users}" -eq 0 ]]; then
  __logi "No users to process for experience levels"
  __log_finish
  return 0
 fi

 local pids=()
 local count=0
 local failed_count=0

 # Process users in parallel
 # calculate_user_experience() already marks modified = FALSE internally
 local batch_size=1000
 local processed=0
 local batch_num=1

 for user_id in ${user_ids}; do
  if [[ -n "${user_id}" ]]; then
   (
    # Use transaction to ensure atomicity
    # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
    if ! __psql_with_appname "ETL-experience-${user_id}" -d "${DBNAME_DWH}" -c "
     BEGIN;
      PERFORM dwh.calculate_user_experience(${user_id});
     COMMIT;
    " 2>&1; then
     __loge "ERROR: Failed to process experience level for user ${user_id}"
     exit 1
    fi
   ) &
   pids+=($!)
   count=$((count + 1))
   processed=$((processed + 1))

   # Limit concurrent processes
   if [[ ${#pids[@]} -ge ${adjusted_threads} ]]; then
    local first_pid="${pids[0]}"
    pids=("${pids[@]:1}")
    if ! wait "${first_pid}"; then
     failed_count=$((failed_count + 1))
    fi
   fi

   # Log progress every batch_size users
   if [[ $((processed % batch_size)) -eq 0 ]]; then
    __logi "Progress: Processed ${processed}/${total_users} users (batch ${batch_num})"
    batch_num=$((batch_num + 1))
   fi
  fi
 done

 # Wait for remaining processes and check for errors
 __logi "Waiting for all experience level processing to complete..."
 for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
   failed_count=$((failed_count + 1))
  fi
 done

 if [[ ${failed_count} -eq 0 ]]; then
  __logi "SUCCESS: Experience level processing completed successfully"
  __logi "Processed ${count} users in parallel (${total_users} total)"
 else
  __loge "ERROR: Experience level processing had ${failed_count} failed processes out of ${count} total"
  __loge "Check the log file for details on failed user processing"
 fi
 __log_finish
 if [[ ${failed_count} -gt 0 ]]; then
  return 1
 fi
 return 0
}

# Safely disable note activity metrics trigger (only if function exists)
# Usage: __safe_disable_note_activity_metrics_trigger
# This function checks if the trigger function exists before attempting to disable it,
# avoiding error messages during first execution when the trigger hasn't been created yet.
function __safe_disable_note_activity_metrics_trigger {
 # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
 if __function_exists "dwh" "disable_note_activity_metrics_trigger" "${DBNAME_DWH}"; then
  __logi "Disabling note activity metrics trigger for bulk load performance..."
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
   -c "SELECT dwh.disable_note_activity_metrics_trigger();" 2>&1
 fi
 # If function doesn't exist, silently skip (expected behavior during first execution)
}

# Checks prerequisites to run the script.
function __checkPrereqs {
 __log_start
 __logi "=== STARTING ETL PREREQUISITES CHECK ==="
 if [[ "${PROCESS_TYPE}" != "" ]] \
  && [[ "${PROCESS_TYPE}" != "--help" ]] \
  && [[ "${PROCESS_TYPE}" != "-h" ]]; then
  echo "ERROR: Invalid parameter. It should be:"
  echo " * Empty string, nothing (auto-detect mode)"
  echo " * --help"
  exit "${ERROR_INVALID_ARGUMENT}"
 fi
 set +e
 # Checks prereqs.
 __checkPrereqsCommands

 ## Validate SQL script files using centralized validation
 __logi "Validating SQL script files..."

 # Create array of SQL files to validate
 local SQL_FILES=(
  "${POSTGRES_10_CHECK_BASE_TABLES}"
  "${POSTGRES_11_CHECK_DWH_BASE_TABLES}"
  "${POSTGRES_12_DROP_DATAMART_OBJECTS}"
  "${POSTGRES_13_DROP_DWH_OBJECTS}"
  "${POSTGRES_22_CREATE_DWH_TABLES}"
  "${POSTGRES_22A_CREATE_FACT_PARTITIONS}"
  "${POSTGRES_23_GET_WORLD_REGIONS}"
  "${POSTGRES_24_ADD_FUNCTIONS}"
  "${POSTGRES_24A_POPULATE_ISO_CODES}"
  "${POSTGRES_25_POPULATE_DIMENSIONS}"
  "${POSTGRES_26_UPDATE_DIMENSIONS}"
  "${POSTGRES_30_SHARED_HELPER_FUNCTIONS}"
  "${POSTGRES_31_CREATE_BASE_STAGING_OBJECTS}"
  "${POSTGRES_32_CREATE_STAGING_OBJECTS}"
  "${POSTGRES_33_CREATE_FACTS_BASE_OBJECTS}"
  "${POSTGRES_34_CREATE_FACTS_YEAR_LOAD}"
  "${POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD}"
  "${POSTGRES_36_DROP_FACTS_YEAR_LOAD}"
  "${POSTGRES_41_ADD_CONSTRAINTS_INDEXES_TRIGGERS}"
  "${POSTGRES_50_CREATE_AUTOMATION_DETECTION}"
  "${POSTGRES_51_CREATE_EXPERIENCE_LEVELS}"
  "${POSTGRES_52_CREATE_NOTE_ACTIVITY_METRICS}"
  "${POSTGRES_53_CREATE_HASHTAG_VIEWS}"
  "${POSTGRES_53A_ENHANCE_DATAMARTS_HASHTAGS}"
  "${POSTGRES_53B_CREATE_HASHTAG_INDEXES}"
  "${POSTGRES_54_UNIFY_FACTS}"
  "${POSTGRES_55_CREATE_NOTE_CURRENT_STATUS}"
  "${POSTGRES_56_GENERATE_ETL_REPORT}"
  "${POSTGRES_57_VALIDATE_ETL_INTEGRITY}"
  "${POSTGRES_63_COMPLETE_HASHTAG_ANALYSIS}"
  "${POSTGRES_61_LOAD_NOTES_STAGING}"
 )

 # Validate each SQL file
 for SQL_FILE in "${SQL_FILES[@]}"; do
  # shellcheck disable=SC2310  # invocation in condition is intentional; failures handled explicitly
  if ! __validate_sql_structure "${SQL_FILE}"; then
   __loge "ERROR: SQL file validation failed: ${SQL_FILE}"
   exit "${ERROR_MISSING_LIBRARY}"
  fi
 done

 ## Validate configuration file if it exists
 if [[ -f "${ETL_CONFIG_FILE}" ]]; then
  __logi "ETL configuration file found and loaded"
 else
  __logw "ETL configuration file not found, using defaults"
 fi

 __logi "=== ETL PREREQUISITES CHECK COMPLETED ==="
 __log_finish
}

# Checks if base ingestion tables exist and have required columns.
# Returns 0 if validation passes, 1 if validation fails.
function __checkIngestionBaseTables {
 __log_start
 __logi "=== CHECKING INGESTION BASE TABLES AND COLUMNS ==="
 set +e
 __psql_with_appname -d "${DBNAME_INGESTION}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_10_CHECK_BASE_TABLES}" 2>&1
 RET=${?}
 # Keep set +e here - we're returning the exit code manually
 __logi "Base tables check result code: ${RET}"
 if [[ "${RET}" -ne 0 ]]; then
  __loge "Base ingestion tables validation failed. Please check the error message above."
  __loge "This usually means tables or required columns are missing."
  __loge "Please ensure OSM-Notes-Ingestion system has created the tables with correct schema."
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional - we don't want log_finish to cause exit
  __log_finish || true
  return 1
 fi

 __logi "=== INGESTION BASE TABLES VALIDATION PASSED ==="
 __log_finish
 return 0
}

# Checks if DWH tables exist. Returns 0 if they exist, 1 if they don't.
function __checkBaseTables {
 __log_start
 __logi "=== CHECKING DWH TABLES ==="
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_11_CHECK_DWH_BASE_TABLES}" 2>&1
 RET=${?}
 set -e
 __logi "Check result code: ${RET}"
 if [[ "${RET}" -ne 0 ]]; then
  __logi "DWH tables are missing - will be created by caller"
  __log_finish
  return 1
 fi

 __logi "DWH tables exist, recreating staging objects"
 __logi "Recreating base staging objects."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_31_CREATE_BASE_STAGING_OBJECTS}" 2>&1

 __logi "Recreating staging objects."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_32_CREATE_STAGING_OBJECTS}" 2>&1

 __logi "=== DWH TABLES CHECK COMPLETED ==="
 __log_finish
}

# Creates DWH tables (dimensions and facts) for initial load.
# This includes dropping existing objects and rebuilding from scratch.
function __createBaseTables {
 __log_start
 __logi "=== CREATING DWH TABLES ==="
 __logi "Dropping any existing DWH objects."
 __logi "Executing: ${POSTGRES_12_DROP_DATAMART_OBJECTS}"
 # shellcheck disable=SC2310  # Function invocation in || condition is intentional; failures are ignored
 __psql_with_appname -d "${DBNAME_DWH}" -f "${POSTGRES_12_DROP_DATAMART_OBJECTS}" 2>&1 || true
 __logi "First DROP command completed"
 __logi "Executing: ${POSTGRES_13_DROP_DWH_OBJECTS}"
 # shellcheck disable=SC2310  # Function invocation in || condition is intentional; failures are ignored
 __psql_with_appname -d "${DBNAME_DWH}" -f "${POSTGRES_13_DROP_DWH_OBJECTS}" 2>&1 || true
 __logi "Second DROP command completed"

 __logi "Creating tables for star model if they do not exist."
 __logi "Executing: ${POSTGRES_22_CREATE_DWH_TABLES}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_22_CREATE_DWH_TABLES}" 2>&1
 local create_exit_code=$?
 set -e
 if [[ ${create_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create DWH tables (exit code: ${create_exit_code})"
  __log_finish
  return 1
 fi
 __logi "CREATE DWH TABLES command completed"
 __logi "Creating partitions for facts table."
 __logi "Executing: ${POSTGRES_22A_CREATE_FACT_PARTITIONS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_22A_CREATE_FACT_PARTITIONS}" 2>&1
 local partitions_exit_code=$?
 set -e
 if [[ ${partitions_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create fact partitions (exit code: ${partitions_exit_code})"
  __log_finish
  return 1
 fi
 __logi "CREATE FACT PARTITIONS command completed"

 __logi "Regions for countries."
 __logi "Executing: ${POSTGRES_23_GET_WORLD_REGIONS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_23_GET_WORLD_REGIONS}" 2>&1
 local regions_exit_code=$?
 set -e
 if [[ ${regions_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to get world regions (exit code: ${regions_exit_code})"
  __log_finish
  return 1
 fi
 __logi "GET WORLD REGIONS command completed"

 __logi "Adding functions."
 __logi "Executing: ${POSTGRES_24_ADD_FUNCTIONS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_24_ADD_FUNCTIONS}" 2>&1
 local functions_exit_code=$?
 set -e
 if [[ ${functions_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to add functions (exit code: ${functions_exit_code})"
  __log_finish
  return 1
 fi
 __logi "ADD FUNCTIONS command completed"

 __logi "Populating ISO country codes reference table."
 __logi "Executing: ${POSTGRES_24A_POPULATE_ISO_CODES}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_24A_POPULATE_ISO_CODES}" 2>&1
 local iso_codes_exit_code=$?
 set -e
 if [[ ${iso_codes_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to populate ISO codes (exit code: ${iso_codes_exit_code})"
  __log_finish
  return 1
 fi
 __logi "POPULATE ISO CODES command completed"

 __logi "Initial dimension population."
 __logi "Executing: ${POSTGRES_25_POPULATE_DIMENSIONS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_25_POPULATE_DIMENSIONS}" 2>&1
 local dimensions_exit_code=$?
 set -e
 if [[ ${dimensions_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to populate dimensions (exit code: ${dimensions_exit_code})"
  __log_finish
  return 1
 fi
 __logi "POPULATE DIMENSIONS command completed"

 # Note: ETL_26_updateDimensionTables.sql is now executed in __initialFactsParallel
 # after base tables are copied (Step 1a), not here during __createBaseTables
 # because it needs access to 'users' and 'countries' tables which don't exist yet
 # during initial DWH creation.

 __logi "Creating base staging objects."
 __logi "Executing: ${POSTGRES_31_CREATE_BASE_STAGING_OBJECTS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_31_CREATE_BASE_STAGING_OBJECTS}" 2>&1
 local base_staging_exit_code=$?
 set -e
 if [[ ${base_staging_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create base staging objects (exit code: ${base_staging_exit_code})"
  __log_finish
  return 1
 fi
 __logi "CREATE BASE STAGING OBJECTS command completed"

 __logi "Creating staging objects."
 __logi "Executing: ${POSTGRES_32_CREATE_STAGING_OBJECTS}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_32_CREATE_STAGING_OBJECTS}" 2>&1
 local staging_exit_code=$?
 set -e
 if [[ ${staging_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create staging objects (exit code: ${staging_exit_code})"
  __log_finish
  return 1
 fi
 __logi "CREATE STAGING OBJECTS command completed"

 __logi "Inserting initial load flag into dwh.properties"
 set +e
 echo "INSERT INTO dwh.properties VALUES ('initial load', 'true')" \
  | __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 2>&1
 local properties_exit_code=$?
 set -e
 if [[ ${properties_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to insert initial load flag (exit code: ${properties_exit_code})"
  __log_finish
  return 1
 fi
 __logi "Initial load flag inserted successfully"

 # Note: __initialFacts is called separately by the caller
 # (either __initialFacts or __initialFactsParallel)

 __logi "=== DWH TABLES CREATED SUCCESSFULLY ==="
 __log_finish
}

# Processes notes and comments incrementally.
# Updates dimensions and loads new facts since last run.
function __processNotesETL {
 __log_start
 __logi "=== PROCESSING NOTES ETL ==="

 # Step 1: Setup Foreign Data Wrappers for incremental processing (hybrid strategy)
 # Foreign tables provide access to latest data from Ingestion DB
 # Only setup FDW if Ingestion and Analytics are in different databases
 __logi "Checking database configuration: DBNAME_INGESTION='${DBNAME_INGESTION}', DBNAME_DWH='${DBNAME_DWH}'"

 if [[ "${DBNAME_INGESTION}" != "${DBNAME_DWH}" ]]; then
  __logi "Databases are different, setting up FDW and logs table"
  # Create logs table for debugging dynamic SQL queries in datamart procedures
  __logi "Creating logs table for debugging (databases are different)..."
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
   -f "${POSTGRES_CREATE_LOGS_TABLE}" 2>&1
  local logs_table_exit_code=$?
  set -e
  if [[ ${logs_table_exit_code} -ne 0 ]]; then
   __loge "ERROR: Failed to create logs table (exit code: ${logs_table_exit_code})"
   # Don't fail the ETL, but warn that datamarts may fail
   __logw "Continuing anyway (datamart procedures may fail if they try to log)"
  else
   __logi "Logs table created successfully"
  fi
  __logi "Step 1: Setting up Foreign Data Wrappers for incremental processing (different databases)..."
  if [[ -f "${POSTGRES_60_SETUP_FDW}" ]]; then
   # Export FDW configuration variables if not set (required for envsubst)
   # Temporarily disable exit on error to handle readonly variables gracefully
   set +e
   # Use 127.0.0.1 instead of localhost to avoid IPv6 issues with FDW
   # Force IPv4 even if FDW_INGESTION_HOST is already set to localhost
   if [[ "${FDW_INGESTION_HOST:-}" == "localhost" ]]; then
    export FDW_INGESTION_HOST="127.0.0.1" 2> /dev/null || true
   else
    export FDW_INGESTION_HOST="${FDW_INGESTION_HOST:-127.0.0.1}" 2> /dev/null || true
   fi
   export FDW_INGESTION_DBNAME="${DBNAME_INGESTION}" 2> /dev/null || true
   export FDW_INGESTION_PORT="${FDW_INGESTION_PORT:-5432}" 2> /dev/null || true
   export FDW_INGESTION_USER="${FDW_INGESTION_USER:-${DB_USER_INGESTION:-notes}}" 2> /dev/null || true
   # Try to get password from multiple sources:
   # 1. FDW_INGESTION_PASSWORD_VALUE (already set by calling script, e.g., hybrid test)
   # 2. FDW_INGESTION_PASSWORD (explicit FDW password, may be readonly)
   # 3. PGPASSWORD (general PostgreSQL password)
   # 4. DB_PASSWORD (database password from properties)
   # 5. Empty string (will use .pgpass or peer authentication if available)
   # Use a temporary variable to avoid readonly issues
   # Read readonly variable using parameter expansion (works even if readonly)
   local fdw_password_value
   # Check if FDW_INGESTION_PASSWORD_VALUE is already set (e.g., by hybrid test script)
   if [[ -n "${FDW_INGESTION_PASSWORD_VALUE:-}" ]]; then
    # Already set by calling script (e.g., hybrid test)
    fdw_password_value="${FDW_INGESTION_PASSWORD_VALUE}"
   else
    # Try to read FDW_INGESTION_PASSWORD (may be readonly, but we can read its value)
    fdw_password_value="${FDW_INGESTION_PASSWORD:-}"
    # If FDW_INGESTION_PASSWORD is empty or unset, try other sources
    if [[ -z "${fdw_password_value}" ]]; then
     fdw_password_value="${PGPASSWORD:-${DB_PASSWORD:-}}"
    fi
   fi
   # Export as non-readonly variable for envsubst
   export FDW_INGESTION_PASSWORD_VALUE="${fdw_password_value}"
   # Export ANALYZE configuration for FDW tables
   export ETL_ANALYZE_FDW_TABLES_VALUE="${ETL_ANALYZE_FDW_TABLES}"
   # Debug: log password status (without showing the actual password)
   if [[ -n "${fdw_password_value}" ]]; then
    __logd "FDW password configured (length: ${#fdw_password_value} characters)"
   else
    __logd "FDW password not configured - will try .pgpass or peer authentication"
   fi
   if [[ "${ETL_ANALYZE_FDW_TABLES}" == "true" ]]; then
    __logd "FDW table ANALYZE is enabled (may take 20+ seconds)"
   else
    __logd "FDW table ANALYZE is disabled (skipping for faster execution)"
   fi
   set -e

   # Use envsubst to replace variables in SQL file
   local fdw_output
   fdw_output=$(mktemp)
   # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
   if ! envsubst < "${POSTGRES_60_SETUP_FDW}" \
    | __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 > "${fdw_output}" 2>&1; then
    __loge "ERROR: Failed to setup Foreign Data Wrappers"
    __loge "FDW setup output:"
    cat "${fdw_output}" >&2
    # Check if it's a password-related error
    if grep -q "no password supplied\|password authentication failed\|could not connect" "${fdw_output}" 2> /dev/null; then
     __loge ""
     __loge "PASSWORD CONFIGURATION REQUIRED:"
     __loge "Foreign Data Wrappers require a password to connect to the source database."
     __loge "Options:"
     __loge "  1. Set FDW_INGESTION_PASSWORD in etc/properties.sh"
     __loge "  2. Set PGPASSWORD environment variable"
     __loge "  3. Configure ~/.pgpass file for user 'notes'"
     __loge "     Format: localhost:5432:notes:notes:your_password"
     __loge "     Permissions: chmod 600 ~/.pgpass"
    fi
    rm -f "${fdw_output}"
    return 1
   fi
   cat "${fdw_output}"
   rm -f "${fdw_output}"
   __logi "Foreign Data Wrappers setup completed"
  else
   __loge "ERROR: FDW setup script not found: ${POSTGRES_60_SETUP_FDW}"
   return 1
  fi
 else
  __logi "Step 1: Ingestion and Analytics use same database (${DBNAME_DWH}), skipping FDW setup"
  __logi "Tables are directly accessible, no Foreign Data Wrappers needed"
 fi

 # Load notes into staging.
 __logi "Step 2: Loading notes into staging."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_61_LOAD_NOTES_STAGING}" 2>&1
 local load_staging_exit_code=$?
 set -e
 if [[ ${load_staging_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to load notes into staging (exit code: ${load_staging_exit_code})"
  __loge "This is a critical error. Creating failed execution marker to prevent repeated failures."
  __common_create_failed_marker "${BASENAME}" "${load_staging_exit_code}" \
   "Failed to load notes into staging. Check logs for details." \
   "Review ETL logs and fix the issue causing staging load to fail. Remove ${FAILED_EXECUTION_FILE} after fixing." \
   "${FAILED_EXECUTION_FILE}"
  __log_finish
  return 1
 fi
 __logi "Notes loaded into staging successfully"

 # Create note activity metrics trigger (before processing to ensure metrics are calculated).
 __logi "Creating note activity metrics trigger."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_52_CREATE_NOTE_ACTIVITY_METRICS}" 2>&1
 local create_trigger_exit_code=$?
 set -e
 if [[ ${create_trigger_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create note activity metrics trigger (exit code: ${create_trigger_exit_code})"
  __log_finish
  return 1
 fi

 # Ensure trigger is enabled for incremental loads (needed for metrics calculation)
 __logi "Ensuring note activity metrics trigger is enabled for incremental processing..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "SELECT dwh.enable_note_activity_metrics_trigger();" 2>&1
 local enable_trigger_exit_code=$?
 set -e
 if [[ ${enable_trigger_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to enable note activity metrics trigger (exit code: ${enable_trigger_exit_code})"
  __log_finish
  return 1
 fi
 __logi "Note activity metrics trigger enabled successfully"

 # Process notes actions into DWH.
 __logi "Processing notes actions into DWH."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "CALL staging.process_notes_actions_into_dwh();" 2>&1
 local process_actions_exit_code=$?
 set -e
 if [[ ${process_actions_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to process notes actions into DWH (exit code: ${process_actions_exit_code})"
  __loge "This is a critical error. Creating failed execution marker to prevent repeated failures."
  __common_create_failed_marker "${BASENAME}" "${process_actions_exit_code}" \
   "Failed to process notes actions into DWH. Check logs for details." \
   "Review ETL logs and fix the issue causing process_notes_actions_into_dwh() to fail. Remove ${FAILED_EXECUTION_FILE} after fixing." \
   "${FAILED_EXECUTION_FILE}"
  __log_finish
  return 1
 fi
 __logi "Notes actions processed into DWH successfully"

 # Unify facts, by computing dates between years.
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_54_UNIFY_FACTS}" 2>&1
 local unify_facts_exit_code=$?
 set -e
 if [[ ${unify_facts_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to unify facts (exit code: ${unify_facts_exit_code})"
  __loge "This is a critical error. Creating failed execution marker to prevent repeated failures."
  __common_create_failed_marker "${BASENAME}" "${unify_facts_exit_code}" \
   "Failed to unify facts. Check logs for details." \
   "Review ETL logs and fix the issue causing facts unification to fail. Remove ${FAILED_EXECUTION_FILE} after fixing." \
   "${FAILED_EXECUTION_FILE}"
  __log_finish
  return 1
 fi
 __logi "Facts unified successfully"

 # Create hashtag analysis views.
 __logi "Creating hashtag analysis views."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53_CREATE_HASHTAG_VIEWS}" 2>&1
 local hashtag_views_exit_code=$?
 set -e
 if [[ ${hashtag_views_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create hashtag analysis views (exit code: ${hashtag_views_exit_code})"
  __log_finish
  return 1
 fi

 # Enhance datamarts with hashtag metrics.
 __logi "Enhancing datamarts with hashtag metrics."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53A_ENHANCE_DATAMARTS_HASHTAGS}" 2>&1
 local enhance_hashtags_exit_code=$?
 set -e
 if [[ ${enhance_hashtags_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to enhance datamarts with hashtag metrics (exit code: ${enhance_hashtags_exit_code})"
  __log_finish
  return 1
 fi

 # Create specialized hashtag indexes.
 __logi "Creating specialized hashtag indexes."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53B_CREATE_HASHTAG_INDEXES}" 2>&1
 local hashtag_indexes_exit_code=$?
 set -e
 if [[ ${hashtag_indexes_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create specialized hashtag indexes (exit code: ${hashtag_indexes_exit_code})"
  __log_finish
  return 1
 fi

 # Complete hashtag analysis functions (DM-002).
 __logi "Creating complete hashtag analysis functions."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_63_COMPLETE_HASHTAG_ANALYSIS}" 2>&1
 local complete_hashtag_exit_code=$?
 set -e
 if [[ ${complete_hashtag_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create complete hashtag analysis functions (exit code: ${complete_hashtag_exit_code})"
  __log_finish
  return 1
 fi

 # Ensure automation detection system exists (needed for update procedures).
 __logi "Ensuring automation detection system exists."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_50_CREATE_AUTOMATION_DETECTION}" 2>&1
 local automation_exit_code=$?
 set -e
 if [[ ${automation_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create automation detection system (exit code: ${automation_exit_code})"
  __log_finish
  return 1
 fi

 # Ensure experience levels system exists (needed for update procedures).
 __logi "Ensuring experience levels system exists."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_51_CREATE_EXPERIENCE_LEVELS}" 2>&1
 local experience_exit_code=$?
 set -e
 if [[ ${experience_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create experience levels system (exit code: ${experience_exit_code})"
  __log_finish
  return 1
 fi

 # Update automation levels for modified users.
 # Process in batches of 100 users per transaction to avoid long-running transactions
 # and reduce lock contention. Each batch commits separately.
 __logi "Updating automation levels for modified users (processing in batches of 100)..."
 local AUTOMATION_BATCH_SIZE=100
 local AUTOMATION_TOTAL_PROCESSED=0
 local AUTOMATION_BATCH_NUM=1
 local AUTOMATION_HAS_MORE=true
 while [[ "${AUTOMATION_HAS_MORE}" == "true" ]]; do
  # Count remaining users BEFORE processing batch to calculate actual processed count
  # Note: Count all users without automation, not just those from last 7 days
  # The procedure processes users from last 7 days, but we need to count all to detect completion
  set +e
  local REMAINING_BEFORE
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
  REMAINING_BEFORE=$(__psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT COUNT(DISTINCT action_dimension_id_user) FROM dwh.facts
   WHERE dimension_id_automation IS NULL
     AND action_dimension_id_user IS NOT NULL;
  " 2>&1 | tr -d ' ' || echo "0")
  local CHECK_BEFORE_EXIT_CODE=$?
  set -e
  # Ensure REMAINING_BEFORE has a valid numeric value
  if [[ ${CHECK_BEFORE_EXIT_CODE} -ne 0 ]] || [[ -z "${REMAINING_BEFORE}" ]] || ! [[ "${REMAINING_BEFORE}" =~ ^[0-9]+$ ]]; then
   __logw "Warning: Failed to check remaining automation users count before batch, using batch size estimate"
   REMAINING_BEFORE="${AUTOMATION_BATCH_SIZE}"
  fi
  # Execute batch within a transaction
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -c "
   BEGIN;
    CALL dwh.update_automation_levels_for_modified_users(${AUTOMATION_BATCH_SIZE});
   COMMIT;
  " 2>&1
  local UPDATE_AUTOMATION_EXIT_CODE=$?
  set -e
  if [[ ${UPDATE_AUTOMATION_EXIT_CODE} -ne 0 ]]; then
   __loge "ERROR: Failed to update automation levels for batch ${AUTOMATION_BATCH_NUM} (exit code: ${UPDATE_AUTOMATION_EXIT_CODE})"
   __log_finish
   return 1
  fi
  # Check if there are more users to process
  # Note: Count all users without automation, not just those from last 7 days
  # The procedure processes users from last 7 days, but we need to count all to detect completion
  set +e
  local REMAINING_COUNT
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
  REMAINING_COUNT=$(__psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT COUNT(DISTINCT action_dimension_id_user) FROM dwh.facts
   WHERE dimension_id_automation IS NULL
     AND action_dimension_id_user IS NOT NULL;
  " 2>&1 | tr -d ' ' || echo "0")
  local CHECK_EXIT_CODE=$?
  set -e
  # Ensure REMAINING_COUNT has a valid numeric value
  local ACTUAL_PROCESSED=0
  if [[ ${CHECK_EXIT_CODE} -ne 0 ]] || [[ -z "${REMAINING_COUNT}" ]] || ! [[ "${REMAINING_COUNT}" =~ ^[0-9]+$ ]]; then
   __logw "Warning: Failed to check remaining automation users count, continuing anyway"
   # If we can't get remaining count, try to calculate from REMAINING_BEFORE if available
   if [[ -n "${REMAINING_BEFORE}" ]] && [[ "${REMAINING_BEFORE}" =~ ^[0-9]+$ ]]; then
    # Estimate: assume we processed at least some users (use min of batch size and remaining before)
    if [[ ${REMAINING_BEFORE} -gt 0 ]]; then
     ACTUAL_PROCESSED=$((REMAINING_BEFORE < AUTOMATION_BATCH_SIZE ? REMAINING_BEFORE : AUTOMATION_BATCH_SIZE))
    fi
   else
    # Last resort: use batch size as estimate (may be inaccurate)
    ACTUAL_PROCESSED="${AUTOMATION_BATCH_SIZE}"
   fi
  else
   # Ensure REMAINING_BEFORE is set and numeric before calculation
   if [[ -z "${REMAINING_BEFORE}" ]] || ! [[ "${REMAINING_BEFORE}" =~ ^[0-9]+$ ]]; then
    REMAINING_BEFORE="${REMAINING_COUNT}"
   fi
   # Calculate actual processed count: before - after
   ACTUAL_PROCESSED=$((REMAINING_BEFORE - REMAINING_COUNT))
   # Ensure non-negative (shouldn't happen, but safety check)
   if [[ ${ACTUAL_PROCESSED} -lt 0 ]]; then
    ACTUAL_PROCESSED=0
   fi
   # Cap at batch size (shouldn't exceed batch size, but safety check)
   if [[ ${ACTUAL_PROCESSED} -gt ${AUTOMATION_BATCH_SIZE} ]]; then
    ACTUAL_PROCESSED="${AUTOMATION_BATCH_SIZE}"
   fi
  fi
  AUTOMATION_TOTAL_PROCESSED=$((AUTOMATION_TOTAL_PROCESSED + ACTUAL_PROCESSED))
  __logi "Automation batch ${AUTOMATION_BATCH_NUM} completed. Processed: ${ACTUAL_PROCESSED}, Total processed: ${AUTOMATION_TOTAL_PROCESSED}"
  # Check if there are more users to process (only from last 7 days, as that's what the procedure processes)
  # The procedure only processes users from last 7 days, so we check that specific subset
  set +e
  local REMAINING_7DAYS
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
  REMAINING_7DAYS=$(__psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT COUNT(DISTINCT action_dimension_id_user) FROM dwh.facts
   WHERE dimension_id_automation IS NULL
     AND action_dimension_id_user IS NOT NULL
     AND action_at > NOW() - INTERVAL '7 days';
  " 2>&1 | tr -d ' ' || echo "0")
  local CHECK_7DAYS_EXIT_CODE=$?
  set -e
  if [[ ${CHECK_7DAYS_EXIT_CODE} -ne 0 ]] || [[ -z "${REMAINING_7DAYS}" ]] || ! [[ "${REMAINING_7DAYS}" =~ ^[0-9]+$ ]] || [[ "${REMAINING_7DAYS}" == "0" ]]; then
   AUTOMATION_HAS_MORE=false
   __logi "No more users to process in last 7 days. Automation level detection completed."
  else
   AUTOMATION_BATCH_NUM=$((AUTOMATION_BATCH_NUM + 1))
  fi
 done
 __logi "Completed automation level detection. Total users processed: ${AUTOMATION_TOTAL_PROCESSED}"

 # Update experience levels for modified users.
 # Process in batches of 500 users per transaction to avoid long-running transactions
 # and reduce lock contention. Each batch commits separately.
 __logi "Updating experience levels for modified users (processing in batches of 500)..."
 local EXPERIENCE_BATCH_SIZE=500
 local EXPERIENCE_TOTAL_PROCESSED=0
 local EXPERIENCE_BATCH_NUM=1
 local EXPERIENCE_HAS_MORE=true
 while [[ "${EXPERIENCE_HAS_MORE}" == "true" ]]; do
  # Count remaining users BEFORE processing batch to calculate actual processed count
  set +e
  local REMAINING_BEFORE
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
  REMAINING_BEFORE=$(__psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT COUNT(*) FROM dwh.dimension_users
   WHERE modified = TRUE AND experience_level_id IS NULL;
  " 2>&1 | tr -d ' ' || echo "0")
  local CHECK_BEFORE_EXIT_CODE=$?
  set -e
  if [[ ${CHECK_BEFORE_EXIT_CODE} -ne 0 ]]; then
   __logw "Warning: Failed to check remaining experience users count before batch, using batch size estimate"
   REMAINING_BEFORE="${EXPERIENCE_BATCH_SIZE}"
  fi
  # Execute batch within a transaction
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -c "
   BEGIN;
    CALL dwh.update_experience_levels_for_modified_users(${EXPERIENCE_BATCH_SIZE});
   COMMIT;
  " 2>&1
  local UPDATE_EXPERIENCE_EXIT_CODE=$?
  set -e
  if [[ ${UPDATE_EXPERIENCE_EXIT_CODE} -ne 0 ]]; then
   __loge "ERROR: Failed to update experience levels for batch ${EXPERIENCE_BATCH_NUM} (exit code: ${UPDATE_EXPERIENCE_EXIT_CODE})"
   __log_finish
   return 1
  fi
  # Check if there are more users to process
  set +e
  local REMAINING_COUNT
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
  REMAINING_COUNT=$(__psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT COUNT(*) FROM dwh.dimension_users
   WHERE modified = TRUE AND experience_level_id IS NULL;
  " 2>&1 | tr -d ' ' || echo "0")
  local CHECK_EXIT_CODE=$?
  set -e
  # Ensure REMAINING_COUNT has a valid numeric value
  local ACTUAL_PROCESSED=0
  if [[ ${CHECK_EXIT_CODE} -ne 0 ]] || [[ -z "${REMAINING_COUNT}" ]] || ! [[ "${REMAINING_COUNT}" =~ ^[0-9]+$ ]]; then
   __logw "Warning: Failed to check remaining experience users count, continuing anyway"
   # If we can't get remaining count, try to calculate from REMAINING_BEFORE if available
   if [[ -n "${REMAINING_BEFORE}" ]] && [[ "${REMAINING_BEFORE}" =~ ^[0-9]+$ ]]; then
    # Estimate: assume we processed at least some users (use min of batch size and remaining before)
    if [[ ${REMAINING_BEFORE} -gt 0 ]]; then
     ACTUAL_PROCESSED=$((REMAINING_BEFORE < EXPERIENCE_BATCH_SIZE ? REMAINING_BEFORE : EXPERIENCE_BATCH_SIZE))
    fi
   else
    # Last resort: use batch size as estimate (may be inaccurate)
    ACTUAL_PROCESSED="${EXPERIENCE_BATCH_SIZE}"
   fi
  else
   # Ensure REMAINING_BEFORE is set and numeric before calculation
   if [[ -z "${REMAINING_BEFORE}" ]] || ! [[ "${REMAINING_BEFORE}" =~ ^[0-9]+$ ]]; then
    REMAINING_BEFORE="${REMAINING_COUNT}"
   fi
   # Calculate actual processed count: before - after
   ACTUAL_PROCESSED=$((REMAINING_BEFORE - REMAINING_COUNT))
   # Ensure non-negative (shouldn't happen, but safety check)
   if [[ ${ACTUAL_PROCESSED} -lt 0 ]]; then
    ACTUAL_PROCESSED=0
   fi
   # Cap at batch size (shouldn't exceed batch size, but safety check)
   if [[ ${ACTUAL_PROCESSED} -gt ${EXPERIENCE_BATCH_SIZE} ]]; then
    ACTUAL_PROCESSED="${EXPERIENCE_BATCH_SIZE}"
   fi
  fi
  EXPERIENCE_TOTAL_PROCESSED=$((EXPERIENCE_TOTAL_PROCESSED + ACTUAL_PROCESSED))
  __logi "Experience batch ${EXPERIENCE_BATCH_NUM} completed. Processed: ${ACTUAL_PROCESSED}, Total processed: ${EXPERIENCE_TOTAL_PROCESSED}"
  # Check if there are more users to process
  # The procedure processes users with modified=TRUE and experience_level_id IS NULL
  # If REMAINING_COUNT is 0 or invalid, we're done
  if [[ -z "${REMAINING_COUNT}" ]] || [[ "${REMAINING_COUNT}" == "0" ]] || ! [[ "${REMAINING_COUNT}" =~ ^[0-9]+$ ]]; then
   EXPERIENCE_HAS_MORE=false
   __logi "No more users to process. Experience level detection completed."
  else
   # If we processed 0 users but REMAINING_COUNT > 0, something is wrong - stop to avoid infinite loop
   if [[ ${ACTUAL_PROCESSED} -eq 0 ]] && [[ ${REMAINING_COUNT} -gt 0 ]]; then
    __logw "Warning: Procedure processed 0 users but ${REMAINING_COUNT} users remain. This may indicate an issue. Stopping to avoid infinite loop."
    EXPERIENCE_HAS_MORE=false
   else
    EXPERIENCE_BATCH_NUM=$((EXPERIENCE_BATCH_NUM + 1))
   fi
  fi
 done
 __logi "Completed experience level calculation. Total users processed: ${EXPERIENCE_TOTAL_PROCESSED}"

 # Create note current status table and procedures (ETL-003, ETL-004)
 __logi "Creating note current status table and procedures."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_55_CREATE_NOTE_CURRENT_STATUS}" 2>&1
 local note_status_create_exit_code=$?
 set -e
 if [[ ${note_status_create_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create note current status table and procedures (exit code: ${note_status_create_exit_code})"
  __log_finish
  return 1
 fi

 # Update note current status (for incremental updates)
 __logi "Updating note current status."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "CALL dwh.update_note_current_status();" 2>&1
 local update_note_status_exit_code=$?
 set -e
 if [[ ${update_note_status_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to update note current status (exit code: ${update_note_status_exit_code})"
  __log_finish
  return 1
 fi

 __log_finish
}

# Creates initial facts for all years using parallel processing.
function __initialFactsParallel {
 __log_start
 local INITIAL_FACTS_TOTAL_START_TIME
 INITIAL_FACTS_TOTAL_START_TIME=$(date +%s)
 __logi "=== CREATING INITIAL FACTS (PARALLEL) ==="

 # Step 1: Copy base tables from Ingestion DB to Analytics DB (hybrid strategy)
 # This avoids millions of cross-database queries during initial load
 local STEP1_START_TIME
 STEP1_START_TIME=$(date +%s)
 __logi "Step 1: Copying base tables from Ingestion DB for initial load..."

 # Before copying base tables, ensure no foreign tables exist that could interfere
 # Foreign tables from previous FDW setup need to be dropped before copying local tables
 __logi "Step 1a: Dropping any existing foreign tables that might interfere with base table copy..."
 set +e
 for table in notes note_comments note_comments_text users countries; do
  # shellcheck disable=SC2310  # Function invocation in if condition is intentional for error handling
  if __psql_with_appname -d "${DBNAME_DWH}" -t -c "
   SELECT 1 FROM information_schema.foreign_tables
   WHERE foreign_table_schema = 'public' AND foreign_table_name = '${table}';
  " 2>&1 | grep -q 1; then
   __logi "Dropping foreign table: ${table}"
   # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
   __psql_with_appname -d "${DBNAME_DWH}" -c "DROP FOREIGN TABLE IF EXISTS public.${table} CASCADE;" > /dev/null 2>&1 || true
  fi
 done
 set -e
 __logi "Foreign tables cleanup completed"

 if [[ -f "${COPY_BASE_TABLES_SCRIPT}" ]]; then
  if bash "${COPY_BASE_TABLES_SCRIPT}"; then
   local STEP1_END_TIME
   STEP1_END_TIME=$(date +%s)
   local step1_duration=$((STEP1_END_TIME - STEP1_START_TIME))
   __logi "Base tables copied successfully"
   __logi "⏱️  TIME: Step 1 (Copy base tables) took ${step1_duration} seconds"

   # Step 1a: Update dimensions now that base tables are available
   # This populates dimension_users and dimension_countries from the copied base tables
   __logi "Step 1a: Updating dimensions with data from copied base tables..."
   set +e
   __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
    -f "${POSTGRES_26_UPDATE_DIMENSIONS}" 2>&1
   local update_dimensions_exit_code=$?
   set -e
   if [[ ${update_dimensions_exit_code} -ne 0 ]]; then
    __loge "ERROR: Failed to update dimensions (exit code: ${update_dimensions_exit_code})"
    __log_finish
    return 1
   fi
   __logi "Dimensions updated successfully"
  else
   __loge "ERROR: Failed to copy base tables. Initial load cannot proceed."
   return 1
  fi
 else
  __loge "ERROR: Copy base tables script not found: ${COPY_BASE_TABLES_SCRIPT}"
  return 1
 fi

 # Create initial facts base objects.
 local STEP2_START_TIME
 STEP2_START_TIME=$(date +%s)
 __logi "Step 2: Creating initial facts base objects."
 __logi "Executing: ${POSTGRES_33_CREATE_FACTS_BASE_OBJECTS_SIMPLE}"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_33_CREATE_FACTS_BASE_OBJECTS_SIMPLE}" 2>&1
 local facts_base_exit_code=$?
 set -e
 if [[ ${facts_base_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create initial facts base objects (exit code: ${facts_base_exit_code})"
  __log_finish
  return 1
 fi
 local STEP2_END_TIME
 STEP2_END_TIME=$(date +%s)
 local step2_duration=$((STEP2_END_TIME - STEP2_START_TIME))
 __logi "CREATE INITIAL FACTS BASE OBJECTS command completed"
 __logi "⏱️  TIME: Step 2 (Create base objects) took ${step2_duration} seconds"

 # Disable note activity metrics trigger for performance during bulk load
 # This improves ETL speed by 5-15% during initial load
 # Note: Function checks if trigger exists before attempting to disable
 __logi "Disabling note activity metrics trigger for performance..."
 local PHASE1_START_TIME
 PHASE1_START_TIME=$(date +%s)
 __safe_disable_note_activity_metrics_trigger
 __logi "Note activity metrics trigger disabled"

 # Phase 1: Parallel load by year
 __logi "Phase 1: Starting parallel load by year..."

 # Adjust MAX_THREADS for parallel processing
 # Uses n-1 cores, if number of cores is greater than 1.
 # This prevents monopolization of the CPUs.
 local adjusted_threads="${MAX_THREADS}"
 if [[ "${MAX_THREADS}" -gt 6 ]]; then
  adjusted_threads=$((MAX_THREADS - 2))
  __logi "Reducing MAX_THREADS from ${MAX_THREADS} to ${adjusted_threads} (leaving 2 cores free)"
 elif [[ "${MAX_THREADS}" -gt 1 ]]; then
  adjusted_threads=$((MAX_THREADS - 1))
  __logi "Reducing MAX_THREADS from ${MAX_THREADS} to ${adjusted_threads} (leaving 1 core free)"
 fi

 # Get list of years from 2013 to current year
 # shellcheck disable=SC2155
 local current_year
 current_year=$(date +%Y)
 local start_year=2013

 # In test mode, process only 2013 and 2014 for faster testing
 # This maintains data integrity by processing complete years
 if [[ "${ETL_TEST_MODE}" == "true" ]]; then
  start_year=2013
  local test_end_year=2014
  current_year="${test_end_year}"
  __logi "TEST MODE: Processing years 2013-2014 (small subset for testing)"
  __logi "NOTE: Use incremental mode afterward to process remaining years"
 else
  __logi "PRODUCTION MODE: Processing all years from 2013 to ${current_year}"
 fi

 local year="${start_year}"
 local pids=()

 # Create procedures for each year
 local CREATE_PROCEDURES_START_TIME
 CREATE_PROCEDURES_START_TIME=$(date +%s)
 local failed_procedures=0
 while [[ ${year} -le ${current_year} ]]; do
  __logi "Creating procedure for year ${year}..."
  set +e
  local proc_output
  proc_output=$(YEAR=${year} envsubst < "${POSTGRES_34_INITIAL_FACTS_LOAD_PARALLEL}" \
   | __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 2>&1)
  # Capture exit code from the pipeline
  # Use default value if PIPESTATUS array doesn't have enough elements
  local proc_create_exit_code=${PIPESTATUS[1]:-1}
  set -e

  # Verify procedure was actually created (check database, not just exit code)
  # This handles cases where psql returns non-zero exit code even on successful CREATE PROCEDURE
  local proc_exists
  proc_exists=$(psql -d "${DBNAME_DWH}" -tAc "SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'staging' AND p.proname = 'process_initial_load_by_year_${year}';" 2>&1 | tr -d ' ' || echo "0")

  if [[ "${proc_exists}" == "1" ]]; then
   __logd "Successfully created procedure for year ${year} (verified in database)"
   if [[ -n "${proc_output}" ]]; then
    __logd "Procedure creation output: ${proc_output}"
   fi
  elif [[ ${proc_create_exit_code} -ne 0 ]]; then
   __loge "ERROR: Failed to create procedure for year ${year} (exit code: ${proc_create_exit_code})"
   __loge "Procedure creation output: ${proc_output}"
   failed_procedures=$((failed_procedures + 1))
  else
   # Exit code is 0 but procedure doesn't exist - this shouldn't happen
   __loge "ERROR: Procedure process_initial_load_by_year_${year} was not created (exit code: ${proc_create_exit_code}, found ${proc_exists} procedures)"
   __loge "Procedure creation output: ${proc_output}"
   failed_procedures=$((failed_procedures + 1))
  fi

  year=$((year + 1))
 done
 local CREATE_PROCEDURES_END_TIME
 CREATE_PROCEDURES_END_TIME=$(date +%s)
 local create_procedures_duration=$((CREATE_PROCEDURES_END_TIME - CREATE_PROCEDURES_START_TIME))
 __logi "⏱️  TIME: Creating procedures for all years took ${create_procedures_duration} seconds"

 if [[ ${failed_procedures} -gt 0 ]]; then
  __loge "ERROR: Failed to create ${failed_procedures} procedure(s) out of $((current_year - start_year + 1)) total"
  __loge "Cannot proceed with parallel execution. Please check the errors above."
  return 1
 fi

 # Disable note activity metrics trigger for performance during bulk load
 # This improves ETL speed by 5-15% during initial load
 # Note: Function checks if trigger exists before attempting to disable
 __safe_disable_note_activity_metrics_trigger

 # Verify critical objects exist before parallel execution
 # This ensures all schemas, functions, and procedures are visible to parallel connections
 __logi "Verifying critical objects exist before parallel execution..."
 local verification_retries=0
 local max_retries=5
 local verification_success=false

 while [[ ${verification_retries} -lt ${max_retries} ]] && [[ "${verification_success}" == "false" ]]; do
  set +e
  local verify_output
  verify_output=$(__psql_with_appname -d "${DBNAME_DWH}" -c "
   DO \$\$
   DECLARE
    schema_exists BOOLEAN;
    function_exists BOOLEAN;
    procedure_count INTEGER;
   BEGIN
    -- Check staging schema exists
    SELECT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname = 'staging') INTO schema_exists;
    IF NOT schema_exists THEN
     RAISE EXCEPTION 'staging schema does not exist';
    END IF;

    -- Check dwh.get_date_id function exists
    SELECT EXISTS(
     SELECT 1 FROM pg_proc p
     JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'dwh' AND p.proname = 'get_date_id'
    ) INTO function_exists;
    IF NOT function_exists THEN
     RAISE EXCEPTION 'dwh.get_date_id function does not exist';
    END IF;

    -- Check at least one procedure exists
    SELECT COUNT(*) INTO procedure_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'staging' AND p.proname LIKE 'process_initial_load_by_year_%%';

    IF procedure_count = 0 THEN
     RAISE EXCEPTION 'No staging procedures found. Expected procedures matching pattern process_initial_load_by_year_%% but found 0';
    END IF;

    RAISE NOTICE 'Verification successful: Found % procedures', procedure_count;
   END \$\$;
  " 2>&1)
  local verify_exit_code=$?
  set -e

  if [[ ${verify_exit_code} -eq 0 ]]; then
   verification_success=true
   __logi "Critical objects verified successfully"
   if [[ -n "${verify_output}" ]]; then
    __logd "Verification output: ${verify_output}"
   fi
  else
   verification_retries=$((verification_retries + 1))
   __loge "Verification failed (attempt ${verification_retries}/${max_retries})"
   __loge "Verification error output: ${verify_output}"
   if [[ ${verification_retries} -lt ${max_retries} ]]; then
    __logw "Retrying in 1 second..."
    sleep 1
   else
    __loge "ERROR: Failed to verify critical objects after ${max_retries} attempts"
    __loge "This may indicate a problem with object creation or visibility"
    __loge "Attempting to show current state of objects..."
    {
     # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
     __psql_with_appname -d "${DBNAME_DWH}" -c "
      SELECT 'Schemas:' as info;
      SELECT nspname FROM pg_namespace WHERE nspname IN ('dwh', 'staging');
      SELECT 'Functions:' as info;
      SELECT n.nspname, p.proname FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'dwh' AND p.proname = 'get_date_id';
      SELECT 'Procedures:' as info;
      SELECT n.nspname, p.proname FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'staging' AND p.proname LIKE 'process_initial_load_by_year_%'
      LIMIT 5;
      SELECT 'All staging procedures:' as info;
      SELECT n.nspname, p.proname, p.prokind FROM pg_proc p
      JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname = 'staging'
      ORDER BY p.proname;
     "
    } 2>&1 || true
    return 1
   fi
  fi
 done

 # Verification ensures all objects exist before parallel execution
 # PostgreSQL commits are immediately visible, no delay needed

 # Execute parallel load for each year
 year="${start_year}"
 __logi "Executing parallel load for years ${start_year}-${current_year} (max ${adjusted_threads} concurrent)..."

 while [[ ${year} -le ${current_year} ]]; do
  (
   set +e
   __logi "Starting year ${year} load (PID: $$)..."
   __psql_with_appname "ETL-year-${year}" -d "${DBNAME_DWH}" -c "CALL staging.process_initial_load_by_year_${year}();" 2>&1
   local year_exit_code=$?
   set -e
   if [[ ${year_exit_code} -ne 0 ]]; then
    __loge "ERROR: Failed to load year ${year} (exit code: ${year_exit_code})"
    exit "${year_exit_code}"
   fi
   __logi "Finished year ${year} load (PID: $$)."
  ) &
  pids+=($!)
  year=$((year + 1))

  # Limit concurrent processes to adjusted_threads
  if [[ ${#pids[@]} -ge ${adjusted_threads} ]]; then
   wait "${pids[0]}"
   pids=("${pids[@]:1}")
  fi
 done

 # Wait for all remaining processes
 __logi "Waiting for all year loads to complete..."
 local failed_years=0
 for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
   __loge "ERROR: Parallel load failed for PID ${pid}"
   ((failed_years++)) || true
  fi
 done
 if [[ ${failed_years} -gt 0 ]]; then
  __loge "ERROR: ${failed_years} year load(s) failed"
  __log_finish
  return 1
 fi
 local PHASE1_END_TIME
 PHASE1_END_TIME=$(date +%s)
 local phase1_duration=$((PHASE1_END_TIME - PHASE1_START_TIME))
 __logi "Phase 1: All parallel loads completed."
 __logi "⏱️  TIME: Phase 1 (Parallel load by year) took ${phase1_duration} seconds"

 # Phase 2: Update recent_opened_dimension_id_date for all facts
 local PHASE2_START_TIME
 PHASE2_START_TIME=$(date +%s)
 __logi "Phase 2: Updating recent_opened_dimension_id_date for all facts..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD_PHASE2}" 2>&1
 local phase2_exit_code=$?
 set -e
 if [[ ${phase2_exit_code} -ne 0 ]]; then
  __loge "ERROR: Phase 2 failed (exit code: ${phase2_exit_code})"
  __log_finish
  return 1
 fi
 local PHASE2_END_TIME
 PHASE2_END_TIME=$(date +%s)
 local phase2_duration=$((PHASE2_END_TIME - PHASE2_START_TIME))
 __logi "Phase 2: Update completed."
 __logi "⏱️  TIME: Phase 2 (Update recent_opened_dimension_id_date) took ${phase2_duration} seconds"

 # Phase 2b: Update closed_dimension_id_date for opened facts
 local PHASE2B_START_TIME
 PHASE2B_START_TIME=$(date +%s)
 __logi "Phase 2b: Updating closed_dimension_id_date for opened facts..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_35B_UPDATE_CLOSED_DIMENSION_ID_DATE}" 2>&1
 local phase2b_exit_code=$?
 set -e
 if [[ ${phase2b_exit_code} -ne 0 ]]; then
  __loge "ERROR: Phase 2b failed (exit code: ${phase2b_exit_code})"
  __loge "This is a warning - ML training may not work, but ETL can continue"
  # Don't fail ETL for this, just warn
 else
  local PHASE2B_END_TIME
  PHASE2B_END_TIME=$(date +%s)
  local phase2b_duration=$((PHASE2B_END_TIME - PHASE2B_START_TIME))
  __logi "Phase 2b: Update completed."
  __logi "⏱️  TIME: Phase 2b (Update closed_dimension_id_date) took ${phase2b_duration} seconds"
 fi

 # Add constraints, indexes and triggers.
 local CONSTRAINTS_START_TIME
 CONSTRAINTS_START_TIME=$(date +%s)
 __logi "Adding constraints, indexes and triggers."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_41_ADD_CONSTRAINTS_INDEXES_TRIGGERS}" 2>&1
 local constraints_exit_code=$?
 set -e
 if [[ ${constraints_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to add constraints, indexes and triggers (exit code: ${constraints_exit_code})"
  __log_finish
  return 1
 fi

 local CONSTRAINTS_END_TIME
 CONSTRAINTS_END_TIME=$(date +%s)
 local constraints_duration=$((CONSTRAINTS_END_TIME - CONSTRAINTS_START_TIME))
 __logi "⏱️  TIME: Adding constraints, indexes and triggers took ${constraints_duration} seconds"

 # Create automation detection system.
 local AUTOMATION_START_TIME
 AUTOMATION_START_TIME=$(date +%s)
 __logi "Creating automation detection system."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_50_CREATE_AUTOMATION_DETECTION}" 2>&1
 local automation_exit_code=$?
 set -e
 if [[ ${automation_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create automation detection system (exit code: ${automation_exit_code})"
  __log_finish
  return 1
 fi
 local AUTOMATION_END_TIME
 AUTOMATION_END_TIME=$(date +%s)
 local automation_duration=$((AUTOMATION_END_TIME - AUTOMATION_START_TIME))
 __logi "⏱️  TIME: Creating automation detection system took ${automation_duration} seconds"

 # Create experience levels system.
 local EXPERIENCE_START_TIME
 EXPERIENCE_START_TIME=$(date +%s)
 __logi "Creating experience levels system."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_51_CREATE_EXPERIENCE_LEVELS}" 2>&1
 local experience_exit_code=$?
 set -e
 if [[ ${experience_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create experience levels system (exit code: ${experience_exit_code})"
  __log_finish
  return 1
 fi
 local EXPERIENCE_END_TIME
 EXPERIENCE_END_TIME=$(date +%s)
 local experience_duration=$((EXPERIENCE_END_TIME - EXPERIENCE_START_TIME))
 __logi "⏱️  TIME: Creating experience levels system took ${experience_duration} seconds"

 # Create note activity metrics trigger.
 local METRICS_START_TIME
 METRICS_START_TIME=$(date +%s)
 __logi "Creating note activity metrics trigger."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_52_CREATE_NOTE_ACTIVITY_METRICS}" 2>&1
 local metrics_exit_code=$?
 set -e
 if [[ ${metrics_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create note activity metrics trigger (exit code: ${metrics_exit_code})"
  __log_finish
  return 1
 fi
 local METRICS_END_TIME
 METRICS_END_TIME=$(date +%s)
 local metrics_duration=$((METRICS_END_TIME - METRICS_START_TIME))
 __logi "⏱️  TIME: Creating note activity metrics trigger took ${metrics_duration} seconds"

 # Enable note activity metrics trigger after creation
 # (It was disabled before bulk load for performance)
 __logi "Enabling note activity metrics trigger for future incremental loads..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "SELECT dwh.enable_note_activity_metrics_trigger();" 2>&1
 local enable_trigger_exit_code=$?
 set -e
 if [[ ${enable_trigger_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to enable note activity metrics trigger (exit code: ${enable_trigger_exit_code})"
  __log_finish
  return 1
 fi

 # Step N: Drop copied base tables after DWH population (hybrid strategy)
 # This frees disk space and ensures incremental uses FDW
 # IMPORTANT: Only drop if Ingestion and Analytics are in DIFFERENT databases
 # If they are the same database (hybrid test mode), we must keep the tables
 # because datamarts and other processes need access to note_comments_text
 local DROP_TABLES_START_TIME
 DROP_TABLES_START_TIME=$(date +%s)
 __logi "Step N: Checking if base tables should be dropped..."
 __logi "Checking database configuration: DBNAME_INGESTION='${DBNAME_INGESTION}', DBNAME_DWH='${DBNAME_DWH}'"

 if [[ "${DBNAME_INGESTION}" != "${DBNAME_DWH}" ]]; then
  # Different databases: tables were copied, safe to drop them
  __logi "Databases are different - dropping copied base tables (were copied for initial load)"
  if [[ -f "${DROP_COPIED_BASE_TABLES_SCRIPT}" ]]; then
   if bash "${DROP_COPIED_BASE_TABLES_SCRIPT}"; then
    local DROP_TABLES_END_TIME
    DROP_TABLES_END_TIME=$(date +%s)
    local drop_tables_duration=$((DROP_TABLES_END_TIME - DROP_TABLES_START_TIME))
    __logi "Copied base tables dropped successfully"
    __logi "⏱️  TIME: Drop copied base tables took ${drop_tables_duration} seconds"
   else
    __logw "Warning: Failed to drop copied base tables (non-critical, continuing...)"
   fi
  else
   __logw "Warning: Drop copied base tables script not found: ${DROP_COPIED_BASE_TABLES_SCRIPT}"
  fi
 else
  # Same database: tables are NOT copies, they are the original tables
  # DO NOT drop them - datamarts and other processes need them
  __logi "Ingestion and Analytics use same database (${DBNAME_DWH})"
  __logi "Base tables are NOT copies - keeping them for datamart access"
  __logi "Skipping drop operation (datamarts need access to note_comments and note_comments_text)"
 fi

 # Create hashtag analysis views (consolidated timing)
 local HASHTAG_START_TIME
 HASHTAG_START_TIME=$(date +%s)
 __logi "Creating hashtag analysis views."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53_CREATE_HASHTAG_VIEWS}" 2>&1
 local hashtag_views_exit_code=$?
 set -e
 if [[ ${hashtag_views_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create hashtag analysis views (exit code: ${hashtag_views_exit_code})"
  __log_finish
  return 1
 fi

 # Enhance datamarts with hashtag metrics.
 __logi "Enhancing datamarts with hashtag metrics."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53A_ENHANCE_DATAMARTS_HASHTAGS}" 2>&1
 local enhance_hashtags_exit_code=$?
 set -e
 if [[ ${enhance_hashtags_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to enhance datamarts with hashtag metrics (exit code: ${enhance_hashtags_exit_code})"
  __log_finish
  return 1
 fi

 # Create specialized hashtag indexes.
 __logi "Creating specialized hashtag indexes."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53B_CREATE_HASHTAG_INDEXES}" 2>&1
 local hashtag_indexes_exit_code=$?
 set -e
 if [[ ${hashtag_indexes_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create specialized hashtag indexes (exit code: ${hashtag_indexes_exit_code})"
  __log_finish
  return 1
 fi
 local HASHTAG_END_TIME
 HASHTAG_END_TIME=$(date +%s)
 local hashtag_duration=$((HASHTAG_END_TIME - HASHTAG_START_TIME))
 __logi "⏱️  TIME: Creating hashtag views/indexes/enhancements took ${hashtag_duration} seconds"

 # Update initial load flag to 'completed' after successful parallel load
 __logi "Updating initial load flag to 'completed'..."
 set +e
 echo "INSERT INTO dwh.properties (key, value) VALUES ('initial load', 'completed') ON CONFLICT (key) DO UPDATE SET value = 'completed';" \
  | __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 2>&1
 local update_flag_exit_code=$?
 set -e
 if [[ ${update_flag_exit_code} -ne 0 ]]; then
  __logw "Warning: Failed to update initial load flag (non-critical, continuing...)"
 else
  __logi "Initial load flag updated to 'completed'"
 fi

 local INITIAL_FACTS_TOTAL_END_TIME
 INITIAL_FACTS_TOTAL_END_TIME=$(date +%s)
 local initial_facts_total_duration=$((INITIAL_FACTS_TOTAL_END_TIME - INITIAL_FACTS_TOTAL_START_TIME))
 __logi "════════════════════════════════════════════════════════════"
 # Initialize note current status table (ETL-003, ETL-004)
 __logi "Initializing note current status table..."
 local STATUS_START_TIME
 STATUS_START_TIME=$(date +%s)
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_55_CREATE_NOTE_CURRENT_STATUS}" 2>&1
 local status_create_exit_code=$?
 set -e
 if [[ ${status_create_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to create note current status objects (exit code: ${status_create_exit_code})"
  __log_finish
  return 1
 fi
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "CALL dwh.initialize_note_current_status();" 2>&1
 local status_init_exit_code=$?
 set -e # Restore error handling after capturing exit code
 if [[ ${status_init_exit_code} -ne 0 ]]; then
  __loge "ERROR: Failed to initialize note current status (exit code: ${status_init_exit_code})"
  __log_finish
  return 1
 fi
 local STATUS_END_TIME
 STATUS_END_TIME=$(date +%s)
 local status_duration=$((STATUS_END_TIME - STATUS_START_TIME))
 __logi "Note current status initialized successfully"
 __logi "⏱️  TIME: Note current status initialization took ${status_duration} seconds"

 __logi "⏱️  TIME: === __initialFactsParallel TOTAL TIME: ${initial_facts_total_duration} seconds ==="
 __logi "════════════════════════════════════════════════════════════"

 # shellcheck disable=SC2310  # Function invocation in || condition is intentional - we don't want log_finish to cause exit
 __log_finish || true
 return 0
}

# Creates initial facts for all years.
function __initialFacts {
 __log_start
 __logi "=== CREATING INITIAL FACTS ==="

 # Create initial facts base objects.
 __logi "Creating initial facts base objects."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_33_CREATE_FACTS_BASE_OBJECTS_SIMPLE}" 2>&1

 # Disable note activity metrics trigger for performance during bulk load
 # This improves ETL speed by 5-15% during initial load
 # Note: Function checks if trigger exists before attempting to disable
 __safe_disable_note_activity_metrics_trigger

 # Skip year-specific load creation for simple initial load
 # __logi "Creating initial facts load."
 # __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
 #  -f "${POSTGRES_34_CREATE_FACTS_YEAR_LOAD}" 2>&1

 # Execute initial facts load.
 __logi "Executing initial facts load."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_35_EXECUTE_FACTS_YEAR_LOAD_SIMPLE}" 2>&1

 # Skip the year-specific load creation and drop steps for simple initial load

 # Add constraints, indexes and triggers.
 __logi "Adding constraints, indexes and triggers."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_41_ADD_CONSTRAINTS_INDEXES_TRIGGERS}" 2>&1

 # Create automation detection system.
 __logi "Creating automation detection system."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_50_CREATE_AUTOMATION_DETECTION}" 2>&1

 # Create experience levels system.
 __logi "Creating experience levels system."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_51_CREATE_EXPERIENCE_LEVELS}" 2>&1

 # Create note activity metrics trigger.
 __logi "Creating note activity metrics trigger."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_52_CREATE_NOTE_ACTIVITY_METRICS}" 2>&1

 # Enable note activity metrics trigger after creation
 # (It was disabled before bulk load for performance)
 __logi "Enabling note activity metrics trigger for future incremental loads..."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -c "SELECT dwh.enable_note_activity_metrics_trigger();" 2>&1

 # Create hashtag analysis views.
 __logi "Creating hashtag analysis views."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53_CREATE_HASHTAG_VIEWS}" 2>&1

 # Enhance datamarts with hashtag metrics.
 __logi "Enhancing datamarts with hashtag metrics."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53A_ENHANCE_DATAMARTS_HASHTAGS}" 2>&1

 # Create specialized hashtag indexes.
 __logi "Creating specialized hashtag indexes."
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_53B_CREATE_HASHTAG_INDEXES}" 2>&1

 __log_finish
}

# Detects if this is the first execution by checking if DWH facts table is empty.
function __detectFirstExecution {
 # Temporarily disable logging to stdout for this function
 local temp_log_file
 temp_log_file=$(mktemp)

 {
  __log_start
  __logi "=== DETECTING EXECUTION MODE ==="

  # First, check if dwh schema exists
  local schema_exists
  # shellcheck disable=SC2310  # Function invocation in || condition is intentional; failures return default value
  schema_exists=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 'dwh';" 2> /dev/null || echo "0")
  __logi "dwh schema exists: '${schema_exists}'"

  # If schema doesn't exist, this is definitely first execution
  if [[ "${schema_exists}" == "0" ]]; then
   __logi "FIRST EXECUTION DETECTED - dwh schema does not exist"
   __logi "Will perform initial load with complete data warehouse creation"
   result="true"
  else
   # Schema exists, check if DWH facts table exists and has data
   local facts_count
   # shellcheck disable=SC2310  # Function invocation in || condition is intentional; failures return default value
   facts_count=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "SELECT COUNT(*) FROM dwh.facts;" 2> /dev/null || echo "0")
   __logi "Query result for facts count: '${facts_count}'"

   # Check if initial load flag exists
   local initial_load_flag
   # shellcheck disable=SC2310  # Function invocation in || condition is intentional; failures return default value
   initial_load_flag=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "SELECT value FROM dwh.properties WHERE key = 'initial load';" 2> /dev/null || echo "")
   __logi "Query result for initial load flag: '${initial_load_flag}'"

   if [[ "${facts_count}" -eq 0 ]]; then
    __logi "FIRST EXECUTION DETECTED - No facts found in DWH"
    __logi "Found ${facts_count} facts in DWH, initial load flag: '${initial_load_flag}'"
    __logi "Will perform initial load with complete data warehouse creation"
    result="true"
   else
    __logi "INCREMENTAL EXECUTION DETECTED - Found ${facts_count} facts in DWH"
    __logi "Will process only new data since last run"
    result="false"
   fi
  fi

  __log_finish
 } >> "${temp_log_file}" 2>&1

 # Output the log file to stdout
 cat "${temp_log_file}"
 rm -f "${temp_log_file}"

 # Return the result
 echo "${result}"
}

# Performs database maintenance operations.
function __perform_database_maintenance {
 __log_start
 __logi "=== PERFORMING DATABASE MAINTENANCE ==="

 if [[ "${ETL_VACUUM_AFTER_LOAD}" == "true" ]]; then
  __logi "Running VACUUM ANALYZE on fact table"
  set +e
  # VACUUM cannot run inside a transaction, so use psql directly without __psql_with_appname
  # which may add timeout settings that create a transaction block
  PGAPPNAME="${BASENAME}" psql -d "${DBNAME_DWH}" -c "VACUUM ANALYZE dwh.facts;" 2>&1
  local vacuum_exit_code=$?
  set -e
  if [[ ${vacuum_exit_code} -ne 0 ]]; then
   __logw "WARNING: VACUUM ANALYZE on fact table returned exit code ${vacuum_exit_code} (non-critical, continuing...)"
  else
   __logi "VACUUM ANALYZE on fact table completed successfully"
  fi
 else
  __logi "ETL_VACUUM_AFTER_LOAD is not set to 'true', skipping VACUUM ANALYZE"
 fi

 if [[ "${ETL_ANALYZE_AFTER_LOAD}" == "true" ]]; then
  __logi "Running ANALYZE on dimension tables"
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -c "ANALYZE dwh.dimension_users, dwh.dimension_countries, dwh.dimension_regions, dwh.dimension_continents, dwh.dimension_days, dwh.dimension_time_of_week, dwh.dimension_applications, dwh.dimension_application_versions, dwh.dimension_hashtags, dwh.dimension_timezones, dwh.dimension_seasons;" 2>&1
  local analyze_exit_code=$?
  set -e
  if [[ ${analyze_exit_code} -ne 0 ]]; then
   __logw "WARNING: ANALYZE on dimension tables returned exit code ${analyze_exit_code} (non-critical, continuing...)"
  else
   __logi "ANALYZE on dimension tables completed successfully"
  fi
 else
  __logi "ETL_ANALYZE_AFTER_LOAD is not set to 'true', skipping ANALYZE"
 fi

 __logi "=== DATABASE MAINTENANCE COMPLETED ==="
 __log_finish
}

# Sets up the lock file for single execution.
# Creates lock file descriptor and writes lock file content.
function __setupLockFile {
 __log_start
 __logw "Validating single execution."
 exec 7> "${LOCK}"
 export ONLY_EXECUTION="no"
 if ! flock -n 7; then
  __loge "Another instance of ${BASENAME} is already running."
  __loge "Lock file: ${LOCK}"
  if [[ -f "${LOCK}" ]]; then
   __loge "Lock file contents:"
   cat "${LOCK}" >&2 || true
  fi
  return 1
 fi
 export ONLY_EXECUTION="yes"

 cat > "${LOCK}" << EOF
PID: ${ORIGINAL_PID}
Process: ${BASENAME}
Started: ${PROCESS_START_TIME}
Temporary directory: ${TMP_DIR}
Process type: ${PROCESS_TYPE}
Main script: ${0}
EOF
 __logd "Lock file content written to: ${LOCK}"
 __log_finish
}

# Function that activates the error trap.
function __trapOn() {
 __log_start
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 # Note: Cannot use 'local' in trap handlers as they execute outside function context
 trap '{
  ERROR_LINE="${LINENO}"
  ERROR_COMMAND="${BASH_COMMAND}"
  ERROR_EXIT_CODE="$?"

  if [[ "${ERROR_EXIT_CODE}" -ne 0 ]]; then
   printf "%s ERROR: The script %s did not finish correctly. Temporary directory: ${TMP_DIR:-} - Line number: %d.\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}" "${ERROR_LINE}";
   printf "ERROR: Failed command: %s (exit code: %d)\n" "${ERROR_COMMAND}" "${ERROR_EXIT_CODE}";
   # Remove lock file on error
   rm -f "${LOCK:-}" 2> /dev/null || true
   exit "${ERROR_EXIT_CODE}";
  fi;
 }' ERR
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 trap '{
  printf "%s WARN: The script %s was terminated. Temporary directory: ${TMP_DIR:-}\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}";
  # Remove lock file on termination
  rm -f "${LOCK:-}" 2> /dev/null || true
  exit "${ERROR_GENERAL}";
 }' SIGINT SIGTERM
 __log_finish
}

######
# MAIN

function main() {
 # Temporarily disable exit on error at the start of main to allow graceful error handling
 # This ensures we can capture exit codes and return them explicitly
 # Also disable ERR trap temporarily to prevent it from interfering with error handling
 set +e
 trap - ERR # Disable ERR trap temporarily

 # Only log errors during initialization - normal startup is silent
 # shellcheck disable=SC2317
 # These commands are reachable when PROCESS_TYPE is -h or --help
 if [[ "${PROCESS_TYPE}" == "-h" ]] || [[ "${PROCESS_TYPE}" == "--help" ]]; then
  __show_help
  set -e   # Re-enable exit on error before returning
  __trapOn # Re-enable trap before returning
  return 0
 fi

 # Sets the trap in case of any signal.
 # But keep ERR trap disabled since we're handling errors manually with set +e
 # The trap will be set but won't interfere because set +e prevents immediate exit
 __trapOn
 trap - ERR # Immediately disable ERR trap again to prevent interference

 # Check for failed execution marker before proceeding
 if [[ -f "${FAILED_EXECUTION_FILE}" ]]; then
  __loge "CRITICAL: Previous ETL execution failed. Failed execution marker found: ${FAILED_EXECUTION_FILE}"
  __loge "Contents of failed execution marker:"
  cat "${FAILED_EXECUTION_FILE}" >&2 || true
  __loge ""
  __loge "ETL execution is blocked to prevent repeated failures."
  __loge "Please review the error above, fix the issue, and remove the failed marker file:"
  __loge "  rm -f ${FAILED_EXECUTION_FILE}"
  __loge ""
  __loge "ETL cannot proceed until the issue is resolved."
  return 1
 fi

 __setupLockFile
 local lock_exit_code=$?
 if [[ ${lock_exit_code} -ne 0 ]]; then
  __loge "Lock file check failed. ETL cannot proceed."
  return 1
 fi

 __checkPrereqs

 # Validate base ingestion tables and columns before processing
 __logi "Validating base ingestion tables and columns..."
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 set +e # Temporarily disable exit on error to check function return code
 __checkIngestionBaseTables
 local check_tables_exit_code=$?
 # Note: We keep set +e here because main() is designed to handle errors manually
 # The function started with set +e at line 1843, so we maintain that mode
 if [[ ${check_tables_exit_code} -ne 0 ]]; then
  __loge "Base ingestion tables validation failed. ETL cannot proceed."
  return 1
 fi

 __logi "PROCESS_TYPE value: '${PROCESS_TYPE}'"

 # Auto-detect execution mode
 __logi "Entering auto-detect mode"
 # Auto-detect if this is the first execution
 local detection_output
 detection_output=$(__detectFirstExecution)
 # Log the full detection output
 # Use set +e around the pipe to prevent pipefail from causing exit on grep failure
 # Also disable pipefail temporarily to prevent grep failure from propagating
 set +e
 set +o pipefail
 echo "${detection_output}" | grep -v "^$" | while IFS= read -r line; do
  __logi "${line}"
 done
 # Re-enable pipefail but keep set +e to prevent grep failure from causing exit
 set -o pipefail
 # Keep set +e here - we're ignoring grep exit code anyway
 # Ignore grep exit code - it's OK if grep finds no matches
 # Extract the result (last line)
 local is_first_execution
 is_first_execution=$(echo "${detection_output}" | tail -1)
 __logi "Detection result: '${is_first_execution}'"

 if [[ "${is_first_execution}" == "true" ]]; then
  __logi "AUTO-DETECTED FIRST EXECUTION - Performing initial load"
  # Adjust timeouts for initial load (longer operations expected)
  if [[ -z "${PSQL_STATEMENT_TIMEOUT:-}" ]] || [[ "${PSQL_STATEMENT_TIMEOUT}" == "30min" ]]; then
   __logi "Adjusting statement timeout for initial load: 4 hours (recommended for large datasets)"
   export PSQL_STATEMENT_TIMEOUT="${PSQL_STATEMENT_TIMEOUT:-4h}"
  fi
  set +E
  # shellcheck disable=SC2310
  if ! __checkBaseTables; then
   __logi "Tables missing, creating them"
   __createBaseTables
  else
   # Ensure schema exists even if tables exist (for datamart scripts)
   __logi "Ensuring dwh schema exists"
   __psql_with_appname -d "${DBNAME_DWH}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2>&1 || true
  fi
  set -E
  __logi "About to call __initialFactsParallel"
  __initialFactsParallel # Use parallel version
  local initial_facts_exit_code=$?
  if [[ ${initial_facts_exit_code} -ne 0 ]]; then
   __loge "ERROR: Initial facts parallel load failed (exit code: ${initial_facts_exit_code})"
   set -e # Re-enable exit on error before returning
   return 1
  fi
  __logi "Finished calling __initialFactsParallel"

  local MAINTENANCE_START_TIME
  MAINTENANCE_START_TIME=$(date +%s)
  __perform_database_maintenance
  local MAINTENANCE_END_TIME
  MAINTENANCE_END_TIME=$(date +%s)
  local maintenance_duration=$((MAINTENANCE_END_TIME - MAINTENANCE_START_TIME))
  __logi "⏱️  TIME: Database maintenance took ${maintenance_duration} seconds"

  # Create logs table (required by datamart procedures e.g. update_datamart_user_activity_year)
  # Always create so year-suffixed columns get populated even when ingestion and DWH use same DB
  __logi "Creating logs table for datamart procedures..."
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
   -f "${POSTGRES_CREATE_LOGS_TABLE}" 2>&1
  local logs_table_exit_code=$?
  set -e
  if [[ ${logs_table_exit_code} -ne 0 ]]; then
   __logw "Could not create logs table (exit code: ${logs_table_exit_code}); year columns may still be populated (procedure tolerates missing logs)"
  else
   __logi "Logs table created successfully"
  fi

  # Create datamart performance log table before executing datamarts
  # This table is required by datamartCountries and datamartUsers procedures
  __logi "Creating datamart performance log table..."
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
   -f "${POSTGRES_DATAMART_PERFORMANCE_CREATE_TABLE}" 2>&1
  local perf_table_exit_code=$?
  set -e
  if [[ ${perf_table_exit_code} -ne 0 ]]; then
   __loge "ERROR: Failed to create datamart performance log table (exit code: ${perf_table_exit_code})"
   # Don't fail the ETL, datamarts should still work (backward compatibility)
   __logw "Continuing anyway (datamarts may not log performance data)"
  else
   __logi "Datamart performance log table created successfully"
  fi

  # Setup FDW after initial load (needed for datamart scripts that access note_comments)
  # Foreign tables provide access to base tables after dropCopiedBaseTables
  local FDW_START_TIME
  FDW_START_TIME=$(date +%s)
  __logi "Setting up Foreign Data Wrappers for datamart processing..."
  if [[ "${DBNAME_INGESTION}" != "${DBNAME_DWH}" ]]; then
   __logi "Databases are different, setting up FDW for datamart access"
   if [[ -f "${POSTGRES_60_SETUP_FDW}" ]]; then
    # Export FDW configuration variables if not set (required for envsubst)
    # Temporarily disable exit on error to handle readonly variables gracefully
    set +e
    # Use 127.0.0.1 instead of localhost to avoid IPv6 issues with FDW
    # Force IPv4 even if FDW_INGESTION_HOST is already set to localhost
    if [[ "${FDW_INGESTION_HOST:-}" == "localhost" ]]; then
     export FDW_INGESTION_HOST="127.0.0.1" 2> /dev/null || true
    else
     export FDW_INGESTION_HOST="${FDW_INGESTION_HOST:-127.0.0.1}" 2> /dev/null || true
    fi
    export FDW_INGESTION_DBNAME="${DBNAME_INGESTION}" 2> /dev/null || true
    export FDW_INGESTION_PORT="${FDW_INGESTION_PORT:-5432}" 2> /dev/null || true
    export FDW_INGESTION_USER="${FDW_INGESTION_USER:-${DB_USER_INGESTION:-notes}}" 2> /dev/null || true
    # Try to get password from multiple sources:
    # 1. FDW_INGESTION_PASSWORD (explicit FDW password, may be readonly)
    # 2. PGPASSWORD (general PostgreSQL password)
    # 3. DB_PASSWORD (database password from properties)
    # 4. Empty string (will use .pgpass or peer authentication if available)
    # Use FDW_INGESTION_PASSWORD_VALUE to avoid readonly variable issues
    # Check if FDW_INGESTION_PASSWORD_VALUE is already set (e.g., by hybrid test script)
    local fdw_password_value
    if [[ -n "${FDW_INGESTION_PASSWORD_VALUE:-}" ]]; then
     # Already set by calling script (e.g., hybrid test)
     fdw_password_value="${FDW_INGESTION_PASSWORD_VALUE}"
    else
     # Try to get password from multiple sources:
     # 1. FDW_INGESTION_PASSWORD (explicit FDW password, may be readonly)
     # 2. PGPASSWORD (general PostgreSQL password)
     # 3. DB_PASSWORD (database password from properties)
     # 4. Empty string (will use .pgpass or peer authentication if available)
     fdw_password_value="${FDW_INGESTION_PASSWORD:-}"
     if [[ -z "${fdw_password_value}" ]]; then
      fdw_password_value="${PGPASSWORD:-${DB_PASSWORD:-}}"
     fi
    fi
    export FDW_INGESTION_PASSWORD_VALUE="${fdw_password_value}"
    # Export ANALYZE configuration for FDW tables
    export ETL_ANALYZE_FDW_TABLES_VALUE="${ETL_ANALYZE_FDW_TABLES}"
    set -e
    # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
    envsubst < "${POSTGRES_60_SETUP_FDW}" \
     | __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 2>&1 || {
     __loge "ERROR: Failed to setup Foreign Data Wrappers for datamart processing"
     return 1
    }
    __logi "Foreign Data Wrappers setup completed for datamart processing"
   else
    __loge "ERROR: FDW setup script not found: ${POSTGRES_60_SETUP_FDW}"
    return 1
   fi
  else
   __logi "Ingestion and Analytics use same database (${DBNAME_DWH}), tables are directly accessible"
  fi
  local FDW_END_TIME
  FDW_END_TIME=$(date +%s)
  local fdw_duration=$((FDW_END_TIME - FDW_START_TIME))
  __logi "⏱️  TIME: Setting up FDW took ${fdw_duration} seconds"

  # Backfill dimension_application_version from note_comments_text so version_adoption_rates is populated
  __logi "Backfilling application version from opening comment body (version_adoption_rates)..."
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 -f "${POSTGRES_27_BACKFILL_APPLICATION_VERSION}" 2>&1
  local backfill_version_exit_code=$?
  set -e
  if [[ ${backfill_version_exit_code} -ne 0 ]]; then
   __logw "Backfill application version failed (exit code: ${backfill_version_exit_code}); version_adoption_rates may be empty"
  else
   __logi "Backfill application version completed"
  fi

  local DATAMART_START_TIME
  DATAMART_START_TIME=$(date +%s)
  __logi "Executing datamart scripts..."
  set +e
  local datamart_failures=0
  local DATAMART_COUNTRIES_START_TIME
  DATAMART_COUNTRIES_START_TIME=$(date +%s)
  if "${DATAMART_COUNTRIES_SCRIPT}" ""; then
   local DATAMART_COUNTRIES_END_TIME
   DATAMART_COUNTRIES_END_TIME=$(date +%s)
   local datamart_countries_duration=$((DATAMART_COUNTRIES_END_TIME - DATAMART_COUNTRIES_START_TIME))
   __logi "SUCCESS: datamartCountries completed successfully"
   __logi "⏱️  TIME: datamartCountries took ${datamart_countries_duration} seconds"
  else
   local datamart_countries_exit_code=$?
   __loge "ERROR: datamartCountries failed with exit code ${datamart_countries_exit_code}"
   # Find log file directory
   local datamart_countries_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_countries_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartCountries_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_countries_log_dir}" ]]; then
    __loge "Check log file: ${datamart_countries_log_dir}/datamartCountries.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  local DATAMART_USERS_START_TIME
  DATAMART_USERS_START_TIME=$(date +%s)
  if "${DATAMART_USERS_SCRIPT}" ""; then
   local DATAMART_USERS_END_TIME
   DATAMART_USERS_END_TIME=$(date +%s)
   local datamart_users_duration=$((DATAMART_USERS_END_TIME - DATAMART_USERS_START_TIME))
   __logi "SUCCESS: datamartUsers completed successfully"
   __logi "⏱️  TIME: datamartUsers took ${datamart_users_duration} seconds"
  else
   local datamart_users_exit_code=$?
   __loge "ERROR: datamartUsers failed with exit code ${datamart_users_exit_code}"
   # Find log file directory
   local datamart_users_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_users_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartUsers_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_users_log_dir}" ]]; then
    __loge "Check log file: ${datamart_users_log_dir}/datamartUsers.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  local DATAMART_GLOBAL_START_TIME
  DATAMART_GLOBAL_START_TIME=$(date +%s)
  if "${DATAMART_GLOBAL_SCRIPT}" ""; then
   local DATAMART_GLOBAL_END_TIME
   DATAMART_GLOBAL_END_TIME=$(date +%s)
   local datamart_global_duration=$((DATAMART_GLOBAL_END_TIME - DATAMART_GLOBAL_START_TIME))
   __logi "SUCCESS: datamartGlobal completed successfully"
   __logi "⏱️  TIME: datamartGlobal took ${datamart_global_duration} seconds"
  else
   local datamart_global_exit_code=$?
   __loge "ERROR: datamartGlobal failed with exit code ${datamart_global_exit_code}"
   # Find log file directory
   local datamart_global_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_global_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartGlobal_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_global_log_dir}" ]]; then
    __loge "Check log file: ${datamart_global_log_dir}/datamartGlobal.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  set -e
  # Fail ETL if datamarts failed and ETL_DATAMART_FAIL_ON_ERROR is true (default)
  if [[ ${datamart_failures} -gt 0 ]]; then
   __loge "ERROR: ${datamart_failures} datamart script(s) failed"
   if [[ "${ETL_DATAMART_FAIL_ON_ERROR}" == "true" ]]; then
    __loge "ETL_DATAMART_FAIL_ON_ERROR=true: ETL will fail due to datamart errors"
    return 1
   else
    __logw "ETL_DATAMART_FAIL_ON_ERROR=false: Continuing despite datamart failures (backward compatibility mode)"
   fi
  fi
  local DATAMART_END_TIME
  DATAMART_END_TIME=$(date +%s)
  local datamart_duration=$((DATAMART_END_TIME - DATAMART_START_TIME))
  __logi "⏱️  TIME: All datamart scripts total time: ${datamart_duration} seconds"
 else
  __logi "AUTO-DETECTED INCREMENTAL EXECUTION - Processing only new data"
  # Check data volume to adjust timeout if needed for large incrementals
  local existing_facts_count
  set +e
  existing_facts_count=$(__psql_with_appname -d "${DBNAME_DWH}" -Atq -c "SELECT COUNT(*) FROM dwh.facts;" 2> /dev/null)
  local psql_exit_code=$?
  if [[ ${psql_exit_code} -ne 0 ]] || [[ -z "${existing_facts_count}" ]]; then
   existing_facts_count="0"
  fi
  set -e
  # If timeout is default (30min) and we have significant data, suggest longer timeout
  if [[ -z "${PSQL_STATEMENT_TIMEOUT:-}" ]] || [[ "${PSQL_STATEMENT_TIMEOUT}" == "30min" ]]; then
   if [[ "${existing_facts_count}" -gt 10000000 ]]; then
    __logw "Large dataset detected (${existing_facts_count} facts). Consider increasing PSQL_STATEMENT_TIMEOUT to 2h for large incremental updates."
    __logw "Current timeout: ${PSQL_STATEMENT_TIMEOUT:-30min}. Large updates may exceed this timeout."
   fi
  fi
  set +E
  # shellcheck disable=SC2310
  if ! __checkBaseTables; then
   __logi "Tables missing, creating them"
   __createBaseTables
  else
   # Ensure schema exists even if tables exist (for datamart scripts)
   __logi "Ensuring dwh schema exists"
   __psql_with_appname -d "${DBNAME_DWH}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2>&1 || true
  fi
  set -E
  __logi "About to call __processNotesETL"
  __processNotesETL
  local process_notes_exit_code=$?
  if [[ ${process_notes_exit_code} -ne 0 ]]; then
   __loge "ERROR: Process notes ETL failed (exit code: ${process_notes_exit_code})"
   __loge "This is a critical error. Creating failed execution marker to prevent repeated failures."
   __common_create_failed_marker "${BASENAME}" "${process_notes_exit_code}" \
    "Process notes ETL failed. Check logs for details." \
    "Review ETL logs and fix the issue causing process notes ETL to fail. Remove ${FAILED_EXECUTION_FILE} after fixing." \
    "${FAILED_EXECUTION_FILE}"
   set -e # Re-enable exit on error before returning
   return 1
  fi
  __logi "Finished calling __processNotesETL"
  __perform_database_maintenance

  # Create logs table if databases are different (needed for debugging in datamart procedures)
  if [[ "${DBNAME_INGESTION}" != "${DBNAME_DWH}" ]]; then
   __logi "Ensuring logs table exists for debugging (databases are different)..."
   set +e
   __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
    -f "${POSTGRES_CREATE_LOGS_TABLE}" 2>&1
   local logs_table_exit_code=$?
   set -e
   if [[ ${logs_table_exit_code} -ne 0 ]]; then
    __loge "ERROR: Failed to create logs table (exit code: ${logs_table_exit_code})"
    # Don't fail the ETL, but warn that datamarts may fail
    __logw "Continuing anyway (datamart procedures may fail if they try to log)"
   else
    __logi "Logs table ensured successfully"
   fi
  fi

  # Ensure datamart performance log table exists before executing datamarts
  # This table is required by datamartCountries and datamartUsers procedures
  __logi "Ensuring datamart performance log table exists..."
  set +e
  __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
   -f "${POSTGRES_DATAMART_PERFORMANCE_CREATE_TABLE}" 2>&1
  local perf_table_exit_code=$?
  set -e
  if [[ ${perf_table_exit_code} -ne 0 ]]; then
   __loge "ERROR: Failed to create datamart performance log table (exit code: ${perf_table_exit_code})"
   # Don't fail the ETL, datamarts should still work (backward compatibility)
   __logw "Continuing anyway (datamarts may not log performance data)"
  fi

  __logi "Executing datamart scripts..."
  set +e
  local datamart_failures=0
  if "${DATAMART_COUNTRIES_SCRIPT}" ""; then
   __logi "SUCCESS: datamartCountries completed successfully"
  else
   local datamart_countries_exit_code=$?
   __loge "ERROR: datamartCountries failed with exit code ${datamart_countries_exit_code}"
   # Find log file directory
   local datamart_countries_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_countries_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartCountries_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_countries_log_dir}" ]]; then
    __loge "Check log file: ${datamart_countries_log_dir}/datamartCountries.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  if "${DATAMART_USERS_SCRIPT}" ""; then
   __logi "SUCCESS: datamartUsers completed successfully"
  else
   local datamart_users_exit_code=$?
   __loge "ERROR: datamartUsers failed with exit code ${datamart_users_exit_code}"
   # Find log file directory
   local datamart_users_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_users_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartUsers_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_users_log_dir}" ]]; then
    __loge "Check log file: ${datamart_users_log_dir}/datamartUsers.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  if "${DATAMART_GLOBAL_SCRIPT}" ""; then
   __logi "SUCCESS: datamartGlobal completed successfully"
  else
   local datamart_global_exit_code=$?
   __loge "ERROR: datamartGlobal failed with exit code ${datamart_global_exit_code}"
   # Find log file directory
   local datamart_global_log_dir
   # shellcheck disable=SC2312  # Command substitution in error message is intentional
   datamart_global_log_dir=$(find /tmp -maxdepth 1 -type d -name 'datamartGlobal_*' -printf '%T@ %p\n' 2> /dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
   if [[ -n "${datamart_global_log_dir}" ]]; then
    __loge "Check log file: ${datamart_global_log_dir}/datamartGlobal.log"
   fi
   datamart_failures=$((datamart_failures + 1))
  fi
  set -e
  # Fail ETL if datamarts failed and ETL_DATAMART_FAIL_ON_ERROR is true (default)
  if [[ ${datamart_failures} -gt 0 ]]; then
   __loge "ERROR: ${datamart_failures} datamart script(s) failed"
   if [[ "${ETL_DATAMART_FAIL_ON_ERROR}" == "true" ]]; then
    __loge "ETL_DATAMART_FAIL_ON_ERROR=true: ETL will fail due to datamart errors"
    return 1
   else
    __logw "ETL_DATAMART_FAIL_ON_ERROR=false: Continuing despite datamart failures (backward compatibility mode)"
   fi
  fi
 fi

 # Generate ETL execution report (ETL-001)
 __logi "Generating ETL execution report..."
 local report_file
 report_file="${TMP_DIR}/etl_report.txt"
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_56_GENERATE_ETL_REPORT}" > "${report_file}" 2>&1
 local report_exit_code=$?
 # Keep set +e here - report generation failures are non-critical
 if [[ ${report_exit_code} -eq 0 ]]; then
  __logi "ETL Report generated successfully:"
  # Display report in log
  if [[ -f "${report_file}" ]]; then
   while IFS= read -r line; do
    __logi "  ${line}"
   done < "${report_file}"
  fi
 else
  __logw "Warning: Failed to generate ETL report (exit code: ${report_exit_code})"
  __logw "Report generation is non-critical, continuing..."
 fi

 # Validate ETL integrity (MON-001, MON-002)
 __logi "Running ETL integrity validations..."
 set +e
 __psql_with_appname -d "${DBNAME_DWH}" -v ON_ERROR_STOP=1 \
  -f "${POSTGRES_57_VALIDATE_ETL_INTEGRITY}" 2>&1
 local validation_exit_code=$?
 # Keep set +e here - validation failures are non-critical and we're continuing anyway
 if [[ ${validation_exit_code} -eq 0 ]]; then
  __logi "ETL integrity validations passed successfully"
 else
  __logw "Warning: ETL integrity validation failed (exit code: ${validation_exit_code})"
  __logw "Validation failures are logged above. Review and fix issues if needed."
  __logw "Validation is non-critical, continuing..."
 fi

 __logw "Ending process."

 # Remove lock file on successful completion
 # Use || true to prevent this from causing exit code 1 if file doesn't exist
 rm -f "${LOCK}" || true

 # Call __log_finish but don't let it cause exit if it fails
 # Use || true to prevent this from causing exit code 1 if it fails
 # shellcheck disable=SC2310  # Function invocation in || condition is intentional - we don't want log_finish to cause exit
 __log_finish || true

 # Explicitly return success to ensure exit code is 0
 # Don't re-enable trap ERR or set -e here, as they might interfere with the return
 # The caller will handle error checking
 return 0
}

# Allows to other user read the directory (skip if sourced for testing)
# Use || true to prevent this from causing exit code 1 if directory doesn't exist or permission denied
if [[ "${SKIP_MAIN:-}" != "true" ]] && [[ -n "${TMP_DIR:-}" ]] && [[ -d "${TMP_DIR:-}" ]]; then
 chmod go+x "${TMP_DIR}" 2> /dev/null || true
fi

# Logger already initialized, log file already set if running from cron
# When running from cron, exec already redirected stdout/stderr to log file
if [[ "${SKIP_MAIN:-}" != "true" ]]; then
 if [[ ! -t 1 ]]; then
  # Running from cron: output already redirected via exec, just call main
  set +e     # Temporarily disable exit on error to capture exit code
  trap - ERR # Disable ERR trap to prevent interference
  main
  EXIT_CODE=$?
  trap - ERR # Keep ERR trap disabled to prevent interference
  set +e     # Keep exit on error disabled during cleanup and exit
  if [[ -n "${CLEAN}" ]] && [[ "${CLEAN}" = true ]]; then
   mv "${LOG_FILENAME}" "/tmp/${BASENAME}_$(date +%Y-%m-%d_%H-%M-%S || true).log" || true
   rmdir "${TMP_DIR}" 2> /dev/null || rm -rf "${TMP_DIR}" 2> /dev/null || true
  fi
  exit "${EXIT_CODE}"
 else
  # Running interactively: output to terminal
  set +e     # Temporarily disable exit on error to capture exit code
  trap - ERR # Disable ERR trap to prevent interference
  main
  EXIT_CODE=$?
  trap - ERR # Keep ERR trap disabled to prevent interference
  set +e     # Keep exit on error disabled during exit
  exit "${EXIT_CODE}"
 fi
fi
