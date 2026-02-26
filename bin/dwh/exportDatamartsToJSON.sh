#!/bin/bash

# Exports datamarts to JSON files for web viewer consumption.
# This allows the web viewer to read precalculated data without direct database access.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-01-15
# Note: This script now uses SELECT * to dynamically export all columns,
# including any new year-based columns added to the datamart tables.
# For users, it also includes contributor_type_name and contributor_type_name_en via JOIN with contributor_types table.
#
# Directory Structure:
#   - Users are organized in subdirectories using hexadecimal hash (3 levels)
#     Format: users/{hex1}/{hex2}/{hex3}/{user_id}.json
#     Calculation: modulo 4096 of user_id, converted to 3-digit hex
#     Example: user_id 12345 -> users/0/3/9/12345.json
#     Note: This script assumes files are already in hexadecimal structure.
#           For initial migration, use migrateGitHubToHexStructure.sh
#   - Countries remain in flat structure (countries/{country_id}.json)
#     as there are few countries and no scalability issues

# Fails when a variable is not initialized.
set -u
# Fails with an non-zero return code.
set -e
# Fails if one of the commands of the pipe fails.
set -o pipefail

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-ERROR}"

# Batch size for incremental export (limits number of files exported per execution)
# Set JSON_EXPORT_BATCH_SIZE=0 to export all pending files (default behavior)
declare JSON_EXPORT_BATCH_SIZE="${JSON_EXPORT_BATCH_SIZE:-10000}"
readonly JSON_EXPORT_BATCH_SIZE

# Base directory for the project.
declare SCRIPT_BASE_DIRECTORY
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
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

# Load common functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

# Load validation functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"

# Schema validation function using ajv
function __validate_json_with_schema() {
 local json_file="${1}"
 local schema_file="${2}"
 local name="${3:-$(basename "${json_file}")}"

 if [[ ! -f "${json_file}" ]]; then
  echo "ERROR: JSON file not found: ${json_file}"
  return 1
 fi

 if [[ ! -f "${schema_file}" ]]; then
  echo "WARNING: Schema file not found: ${schema_file}"
  return 0
 fi

 if command -v ajv > /dev/null 2>&1; then
  if ajv validate -s "${schema_file}" -d "${json_file}" > /dev/null 2>&1; then
   echo "  ✓ Valid: ${name}"
   return 0
  else
   echo "  ✗ Invalid: ${name}"
   ajv validate -s "${schema_file}" -d "${json_file}" 2>&1 || true
   return 1
  fi
 else
  echo "WARNING: ajv not available, skipping schema validation"
  return 0
 fi
}

# Calculate datamart schema hash for change detection
function __calculate_schema_hash() {
 if ! command -v psql > /dev/null 2>&1; then
  echo ""
  return 1
 fi

 # Get column definitions from datamart tables
 local schema_hash
 schema_hash=$(
  psql -d "${DBNAME_DWH}" -Atq << 'EOF' | sha256sum | cut -d' ' -f1
SELECT
  COALESCE(string_agg(column_name || ':' || data_type || ':' || ordinal_position, '|' ORDER BY table_name, ordinal_position), '')
FROM (
  SELECT
    'datamartusers' as table_name,
    column_name,
    data_type,
    ordinal_position
  FROM information_schema.columns
  WHERE table_schema = 'dwh' AND table_name = 'datamartusers'
  UNION ALL
  SELECT
    'datamartcountries' as table_name,
    column_name,
    data_type,
    ordinal_position
  FROM information_schema.columns
  WHERE table_schema = 'dwh' AND table_name = 'datamartcountries'
) t
EOF
 )
 echo "${schema_hash}"
}

# Get current version from version tracking file
function __get_current_version() {
 local version_file="${SCRIPT_BASE_DIRECTORY}/.json_export_version"

 if [[ -f "${version_file}" ]]; then
  cat "${version_file}"
 else
  echo "1.0.0"
 fi
}

# Increment version (MAJOR.MINOR.PATCH)
function __increment_version() {
 local current_version="${1:-1.0.0}"
 local version_type="${2:-patch}" # major, minor, or patch
 local major minor patch

 IFS='.' read -r major minor patch <<< "${current_version}"

 case "${version_type}" in
 major)
  major=$((major + 1))
  minor=0
  patch=0
  ;;
 minor)
  minor=$((minor + 1))
  patch=0
  ;;
 patch | *)
  patch=$((patch + 1))
  ;;
 esac

 echo "${major}.${minor}.${patch}"
}

# Save version to file
function __save_version() {
 local version="${1}"
 local version_file="${SCRIPT_BASE_DIRECTORY}/.json_export_version"
 echo "${version}" > "${version_file}"
}

# Cleanup function for temporary directory
function __cleanup_temp() {
 if [[ -d "${ATOMIC_TEMP_DIR}" ]]; then
  echo "Cleaning up temporary directory..."
  rm -rf "${ATOMIC_TEMP_DIR}"
 fi
}

# Reset json_exported flag for modified entities
function __reset_exported_flags() {
 # shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
 echo "$(date +%Y-%m-%d\ %H:%M:%S) - Resetting export flags for modified entities..."

 # Reset users marked as modified
 psql -d "${DBNAME_DWH}" -Atq -c "
  UPDATE dwh.datamartusers
  SET json_exported = FALSE
  FROM dwh.dimension_users
  WHERE dwh.datamartusers.dimension_user_id = dwh.dimension_users.dimension_user_id
    AND dwh.dimension_users.modified = TRUE
 " > /dev/null 2>&1 || true

 # Reset countries marked as modified
 psql -d "${DBNAME_DWH}" -Atq -c "
  UPDATE dwh.datamartcountries
  SET json_exported = FALSE
  FROM dwh.dimension_countries
  WHERE dwh.datamartcountries.dimension_country_id = dwh.dimension_countries.dimension_country_id
    AND dwh.dimension_countries.modified = TRUE
 " > /dev/null 2>&1 || true

 echo "  Export flags reset for modified entities"
}

# Schema files location (from OSM-Notes-Common submodule)
declare SCHEMA_DIR="${SCHEMA_DIR:-${SCRIPT_BASE_DIRECTORY}/lib/osm-common/schemas}"
readonly SCHEMA_DIR

# Output directory for JSON files (final destination)
declare OUTPUT_DIR="${JSON_OUTPUT_DIR:-./output/json}"
readonly OUTPUT_DIR

# Temporary directory for atomic writes (inside TMP_DIR)
declare ATOMIC_TEMP_DIR="${TMP_DIR}/atomic_export"
readonly ATOMIC_TEMP_DIR

# Validation error counter
VALIDATION_ERROR_COUNT=0

# Register cleanup trap
trap __cleanup_temp EXIT

# Create temporary directories for atomic writes
mkdir -p "${ATOMIC_TEMP_DIR}/users"
mkdir -p "${ATOMIC_TEMP_DIR}/countries"
mkdir -p "${ATOMIC_TEMP_DIR}/indexes"

# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Starting datamart JSON export to temporary directory"

# Check if dwh schema exists
if ! psql -d "${DBNAME_DWH}" -Atq -c "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'dwh'" | grep -q 1; then
 __loge "Schema 'dwh' does not exist. Please run the ETL process first to create the data warehouse."
 exit 1
fi

# Check if datamart tables exist
if ! psql -d "${DBNAME_DWH}" -Atq -c "SELECT 1 FROM information_schema.tables WHERE table_schema = 'dwh' AND table_name = 'datamartusers'" | grep -q 1; then
 __loge "Datamart tables do not exist. Please run the datamart population scripts first:
	- bin/dwh/datamartUsers/datamartUsers.sh
	- bin/dwh/datamartCountries/datamartCountries.sh
	- bin/dwh/datamartGlobal/datamartGlobal.sh"
 exit 1
fi

# Reset export flags for entities marked as modified in dimension tables
__reset_exported_flags

# Function to calculate hexadecimal subdirectory for user_id (3-level hash)
# Uses modulo 4096 for uniform distribution across 4096 directories
get_user_subdir() {
 local user_id=$1
 local mod
 local hex_mod
 local d1
 local d2
 local d3
 mod=$((user_id % 4096))
 hex_mod=$(printf "%03x" "${mod}")
 d1=$(echo "${hex_mod}" | cut -c1)
 d2=$(echo "${hex_mod}" | cut -c2)
 d3=$(echo "${hex_mod}" | cut -c3)
 echo "${d1}/${d2}/${d3}"
}

# Export users - incremental mode
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Exporting users datamart (incremental)..."

# Copy existing user files to temp directory to preserve unchanged ones (hexadecimal subdirectory structure)
if [[ -d "${OUTPUT_DIR}/users" ]]; then
 echo "  Copying existing user files..."
 # Copy files from hexadecimal subdirectory structure recursively
 cp -rp "${OUTPUT_DIR}/users"/* "${ATOMIC_TEMP_DIR}/users/" 2> /dev/null || true
fi

# Export only modified users (with optional batch limit)
MODIFIED_USER_COUNT=0
if [[ ${JSON_EXPORT_BATCH_SIZE} -gt 0 ]]; then
 echo "  Processing batch of up to ${JSON_EXPORT_BATCH_SIZE} users..."
fi

psql -d "${DBNAME_DWH}" -Atq << SQL_USERS | while IFS='|' read -r user_id username; do
SELECT
  user_id,
  username
FROM dwh.datamartusers
WHERE user_id IS NOT NULL
  AND json_exported = FALSE
ORDER BY user_id
LIMIT ${JSON_EXPORT_BATCH_SIZE};
SQL_USERS

 if [[ -n "${user_id}" ]]; then
  # Validate user_id is a positive integer to prevent SQL injection
  # This validation ensures user_id contains only digits, making it safe for direct interpolation
  if ! [[ "${user_id}" =~ ^[0-9]+$ ]]; then
   echo "  ERROR: Invalid user_id format: ${user_id} (skipping)" >&2
   continue
  fi

  # Calculate subdirectory for this user_id (hexadecimal hash of 3 levels)
  USER_SUBDIR=$(get_user_subdir "${user_id}")
  mkdir -p "${ATOMIC_TEMP_DIR}/users/${USER_SUBDIR}"

  # Export each modified user to a separate JSON file in subdirectory
  # Use export view if available (excludes internal _partial_* columns), otherwise use table directly
  # The view excludes internal columns prefixed with _partial_ or _last_processed_
  # SECURITY: user_id is validated above to contain only digits, so direct interpolation is safe
  if psql -d "${DBNAME_DWH}" -Atq -c "SELECT 1 FROM information_schema.views WHERE table_schema = 'dwh' AND table_name = 'datamartusers_export'" | grep -q 1; then
   # Use export view (excludes internal columns)
   psql -d "${DBNAME_DWH}" -Atq -c "
      SELECT row_to_json(t)
      FROM (
        SELECT
          du.*,
          ct.contributor_type_name,
          ct.contributor_type_name_en
        FROM dwh.datamartusers_export du
        LEFT JOIN dwh.contributor_types ct
          ON du.id_contributor_type = ct.contributor_type_id
        WHERE du.user_id = $(printf '%d' "${user_id}")
      ) t
	" > "${ATOMIC_TEMP_DIR}/users/${USER_SUBDIR}/${user_id}.json"
  else
   # Fallback: Use table directly (for backward compatibility)
   # Exclude internal columns manually if they exist
   psql -d "${DBNAME_DWH}" -Atq -c "
      SELECT row_to_json(t)
      FROM (
        SELECT
          du.*,
          ct.contributor_type_name,
          ct.contributor_type_name_en
        FROM dwh.datamartusers du
        LEFT JOIN dwh.contributor_types ct
          ON du.id_contributor_type = ct.contributor_type_id
        WHERE du.user_id = $(printf '%d' "${user_id}")
      ) t
	" > "${ATOMIC_TEMP_DIR}/users/${USER_SUBDIR}/${user_id}.json"
  fi

  echo "  Exported modified user: ${user_id} (${username})"
  MODIFIED_USER_COUNT=$((MODIFIED_USER_COUNT + 1))

  # Mark as exported in database
  # SECURITY: user_id is validated above to contain only digits, so direct interpolation is safe
  psql -d "${DBNAME_DWH}" -Atq -c "
      UPDATE dwh.datamartusers
      SET json_exported = TRUE
      WHERE user_id = $(printf '%d' "${user_id}")
	" > /dev/null 2>&1 || true

  # Validate only modified user files
  # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
  if ! __validate_json_with_schema \
   "${ATOMIC_TEMP_DIR}/users/${USER_SUBDIR}/${user_id}.json" \
   "${SCHEMA_DIR}/user-profile.schema.json" \
   "user ${user_id}"; then
   VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
  fi
 fi
done

if [[ ${MODIFIED_USER_COUNT} -gt 0 ]]; then
 echo "  Total modified users exported: ${MODIFIED_USER_COUNT}"
else
 echo "  No modified users to export"
fi

# Create user index file
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Creating user index..."
if ! psql -d "${DBNAME_DWH}" -Atq -c "
  SELECT COALESCE(json_agg(t), '[]'::json)
  FROM (
    SELECT
      du.user_id,
      du.username,
      du.id_contributor_type,
      ct.contributor_type_name,
      ct.contributor_type_name_en,
      dimu.experience_level_id,
      el.experience_level,
      du.date_starting_creating_notes,
      du.history_whole_open,
      du.history_whole_closed,
      du.history_whole_commented,
      du.history_year_open,
      du.history_year_closed,
      du.history_year_commented,
      du.avg_days_to_resolution,
      du.resolution_rate,
      du.notes_resolved_count,
      du.notes_still_open_count,
      du.user_response_time,
      du.days_since_last_action,
      du.notes_created_last_30_days,
      du.notes_resolved_last_30_days
    FROM dwh.datamartusers du
    LEFT JOIN dwh.contributor_types ct
      ON du.id_contributor_type = ct.contributor_type_id
    LEFT JOIN dwh.dimension_users dimu ON du.dimension_user_id = dimu.dimension_user_id
    LEFT JOIN dwh.dimension_experience_levels el ON dimu.experience_level_id = el.dimension_experience_id
    WHERE du.user_id IS NOT NULL
    ORDER BY du.history_whole_open DESC NULLS LAST, du.history_whole_closed DESC NULLS LAST
  ) t
" > "${ATOMIC_TEMP_DIR}/indexes/users.json"; then
 echo '[]' > "${ATOMIC_TEMP_DIR}/indexes/users.json"
fi

# Validate user index
# shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
if ! __validate_json_with_schema \
 "${ATOMIC_TEMP_DIR}/indexes/users.json" \
 "${SCHEMA_DIR}/user-index.schema.json" \
 "user index"; then
 VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
fi

# Export countries - incremental mode
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Exporting countries datamart (incremental)..."

# Copy existing country files to temp directory to preserve unchanged ones
if [[ -d "${OUTPUT_DIR}/countries" ]]; then
 echo "  Copying existing country files..."
 cp -p "${OUTPUT_DIR}/countries"/*.json "${ATOMIC_TEMP_DIR}/countries/" 2> /dev/null || true
fi

# Export only modified countries (with optional batch limit)
MODIFIED_COUNTRY_COUNT=0
if [[ ${JSON_EXPORT_BATCH_SIZE} -gt 0 ]]; then
 echo "  Processing batch of up to ${JSON_EXPORT_BATCH_SIZE} countries..."
fi

psql -d "${DBNAME_DWH}" -Atq << SQL_COUNTRIES | while IFS='|' read -r country_id country_name; do
SELECT country_id, country_name_en
FROM dwh.datamartcountries
WHERE country_id IS NOT NULL
  AND json_exported = FALSE
ORDER BY country_id
LIMIT ${JSON_EXPORT_BATCH_SIZE};
SQL_COUNTRIES

 if [[ -n "${country_id}" ]]; then
  # Export each modified country to a separate JSON file
  # Use SELECT * to dynamically include all columns
  psql -d "${DBNAME_DWH}" -Atq -c "
      SELECT row_to_json(t)
      FROM dwh.datamartcountries t
      WHERE t.country_id = ${country_id}
	" > "${ATOMIC_TEMP_DIR}/countries/${country_id}.json"

  echo "  Exported modified country: ${country_id} (${country_name})"
  MODIFIED_COUNTRY_COUNT=$((MODIFIED_COUNTRY_COUNT + 1))

  # Mark as exported in database
  psql -d "${DBNAME_DWH}" -Atq -c "
      UPDATE dwh.datamartcountries
      SET json_exported = TRUE
      WHERE country_id = ${country_id}
	" > /dev/null 2>&1 || true

  # Validate only modified country files
  # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
  if ! __validate_json_with_schema \
   "${ATOMIC_TEMP_DIR}/countries/${country_id}.json" \
   "${SCHEMA_DIR}/country-profile.schema.json" \
   "country ${country_id}"; then
   VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
  fi
 fi
done

if [[ ${MODIFIED_COUNTRY_COUNT} -gt 0 ]]; then
 echo "  Total modified countries exported: ${MODIFIED_COUNTRY_COUNT}"
else
 echo "  No modified countries to export"
fi

# Create country index file
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Creating country index..."
if ! psql -d "${DBNAME_DWH}" -Atq -c "
  SELECT COALESCE(json_agg(t), '[]'::json)
  FROM (
    SELECT
      country_id,
      country_name,
      country_name_es,
      country_name_en,
      date_starting_creating_notes,
      history_whole_open,
      history_whole_closed,
      history_whole_commented,
      history_year_open,
      history_year_closed,
      history_year_commented,
      avg_days_to_resolution,
      resolution_rate,
      notes_resolved_count,
      notes_still_open_count,
      notes_health_score,
      new_vs_resolved_ratio,
      notes_created_last_30_days,
      notes_resolved_last_30_days
    FROM dwh.datamartcountries
    WHERE country_id IS NOT NULL
    ORDER BY history_whole_open DESC NULLS LAST, history_whole_closed DESC NULLS LAST
  ) t
" > "${ATOMIC_TEMP_DIR}/indexes/countries.json"; then
 echo '[]' > "${ATOMIC_TEMP_DIR}/indexes/countries.json"
fi

# Validate country index
# shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
if ! __validate_json_with_schema \
 "${ATOMIC_TEMP_DIR}/indexes/countries.json" \
 "${SCHEMA_DIR}/country-index.schema.json" \
 "country index"; then
 VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
fi

# Create metadata file with versioning
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Creating metadata with versioning..."

# Get current version and calculate schema hash
CURRENT_VERSION=$(__get_current_version)
SCHEMA_VERSION="1.0.0"
DATA_SCHEMA_HASH=$(__calculate_schema_hash)
EXPORT_TIMESTAMP=$(date +%s)

# shellcheck disable=SC2312  # Command substitution in heredoc is intentional; date/find/wc commands are safe
cat > "${ATOMIC_TEMP_DIR}/metadata.json" << EOF
{
  "export_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "export_timestamp": ${EXPORT_TIMESTAMP},
  "total_users": $(find "${ATOMIC_TEMP_DIR}/users" -type f -name "*.json" | wc -l),
  "total_countries": $(find "${ATOMIC_TEMP_DIR}/countries" -maxdepth 1 -type f | wc -l),
  "version": "${CURRENT_VERSION}",
  "schema_version": "${SCHEMA_VERSION}",
  "api_compat_min": "1.0.0",
  "data_schema_hash": "${DATA_SCHEMA_HASH}"
}
EOF

echo "  Export version: ${CURRENT_VERSION}"
echo "  Schema hash: ${DATA_SCHEMA_HASH}"

# Validate metadata
# shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
if ! __validate_json_with_schema \
 "${ATOMIC_TEMP_DIR}/metadata.json" \
 "${SCHEMA_DIR}/metadata.schema.json" \
 "metadata"; then
 VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
fi

# Export global statistics
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - Exporting global datamart..."
psql -d "${DBNAME_DWH}" -Atq -c "
  SELECT row_to_json(t)
  FROM dwh.datamartglobal t
  WHERE dimension_global_id = 1
" > "${ATOMIC_TEMP_DIR}/global_stats.json"

# Also create a simplified version for quick loading
psql -d "${DBNAME_DWH}" -Atq -c "
  SELECT row_to_json(t)
  FROM (
    SELECT
      currently_open_count,
      currently_closed_count,
      history_whole_open,
      history_whole_closed,
      history_whole_reopened,
      history_year_open,
      history_year_closed,
      history_year_reopened,
      avg_days_to_resolution,
      median_days_to_resolution,
      avg_days_to_resolution_current_year,
      median_days_to_resolution_current_year,
      resolution_rate,
      notes_created_last_30_days,
      notes_resolved_last_30_days,
      notes_backlog_size,
      active_users_count
    FROM dwh.datamartglobal
    WHERE dimension_global_id = 1
  ) t
" > "${ATOMIC_TEMP_DIR}/global_stats_summary.json"

# Validate global stats
if [[ -f "${SCHEMA_DIR}/global-stats.schema.json" ]]; then
 # shellcheck disable=SC2310  # Function invocation in ! condition is intentional for error handling
 if ! __validate_json_with_schema \
  "${ATOMIC_TEMP_DIR}/global_stats.json" \
  "${SCHEMA_DIR}/global-stats.schema.json" \
  "global stats"; then
  VALIDATION_ERROR_COUNT=$((VALIDATION_ERROR_COUNT + 1))
 fi
fi

echo "  ✓ Global statistics exported"

# Check validation results
if [[ ${VALIDATION_ERROR_COUNT} -gt 0 ]]; then
 echo ""
 echo "ERROR: Validation failed with ${VALIDATION_ERROR_COUNT} error(s)"
 echo "Keeping existing files in ${OUTPUT_DIR}"
 echo "Invalid files are in ${ATOMIC_TEMP_DIR} for inspection"
 exit 1
fi

# All validations passed - atomic move to final destination
echo ""
# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - All validations passed, moving to final destination..."

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/users"
mkdir -p "${OUTPUT_DIR}/countries"
mkdir -p "${OUTPUT_DIR}/indexes"

# Move files atomically (move is atomic operation)
mv "${ATOMIC_TEMP_DIR}"/* "${OUTPUT_DIR}/"

# shellcheck disable=SC2312  # Command substitution in echo is intentional; date command is safe
echo "$(date +%Y-%m-%d\ %H:%M:%S) - JSON export completed successfully"
# shellcheck disable=SC2312  # Command substitution in echo is intentional; find/wc commands are safe
echo "  Users: $(find "${OUTPUT_DIR}/users" -type f -name "*.json" | wc -l) files"
# shellcheck disable=SC2312  # Command substitution in echo is intentional; find/wc commands are safe
echo "  Countries: $(find "${OUTPUT_DIR}/countries" -maxdepth 1 -type f | wc -l) files"
echo "  Global statistics: global_stats.json, global_stats_summary.json"
echo "  Output directory: ${OUTPUT_DIR}"
