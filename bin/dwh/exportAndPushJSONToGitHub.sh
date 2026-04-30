#!/bin/bash

# Exports all datamart JSON (users, countries, indexes, metadata, global stats) and pushes
# to the OSM-Notes-Data repository for GitHub Pages.
#
# Usage: ./bin/dwh/exportAndPushJSONToGitHub.sh
#
# Environment variables:
#   MAX_AGE_DAYS: Country JSON older than this (or missing) forces re-export (default: 30)
#   JSON_EXPORT_BATCH_SIZE: Max users/countries per run in exportDatamartsToJSON (default: 10000).
#                          Set to 0 for no limit (full pending export in one run).
#   SKIP_DATAMART_JSON_EXPORT: If "true", skip running exportDatamartsToJSON (not recommended).
#   DBNAME_DWH: DWH database name (default: from etc/properties.sh)
#   OSM_NOTES_DATA_SQUASH_AFTER_EXPORT: If "true", after a successful pipeline run squash
#     OSM-Notes-Data to a single orphan commit on origin/<branch> (force-with-lease). Use sparingly:
#     see bin/dwh/squashOSMNotesDataGitHistory.sh. GitHub branch protection must allow force-push or
#     the squash step fails with a warning and leaves the normal export commits intact.
#
# Behavior:
#   - Syncs OSM-Notes-Data clone, copies JSON schemas
#   - Removes obsolete country files, marks stale country JSON for re-export when needed
#   - Runs exportDatamartsToJSON.sh with output directly under data/ in the Data repo
#   - Commits and pushes data/, schemas/, and countries README when there are changes
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-30

set -eu pipefail

# Script basename for lock file
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME

# Lock file for single execution
LOCK="/tmp/${BASENAME}.lock"
readonly LOCK

# Process start time
PROCESS_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
readonly PROCESS_START_TIME
ORIGINAL_PID=$$
readonly ORIGINAL_PID

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
MAX_AGE_DAYS="${MAX_AGE_DAYS:-30}"
readonly MAX_AGE_DAYS
JSON_EXPORT_BATCH_SIZE="${JSON_EXPORT_BATCH_SIZE:-10000}"
readonly JSON_EXPORT_BATCH_SIZE
SKIP_DATAMART_JSON_EXPORT="${SKIP_DATAMART_JSON_EXPORT:-false}"
readonly SKIP_DATAMART_JSON_EXPORT

# Project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
readonly SCRIPT_DIR
ANALYTICS_DIR="${SCRIPT_DIR}"
readonly ANALYTICS_DIR
# Support both locations: ${HOME}/OSM-Notes-Data (preferred) and ${HOME}/github/OSM-Notes-Data (fallback)
if [[ -d "${HOME}/OSM-Notes-Data" ]]; then
 DATA_REPO_DIR="${HOME}/OSM-Notes-Data"
elif [[ -d "${HOME}/github/OSM-Notes-Data" ]]; then
 DATA_REPO_DIR="${HOME}/github/OSM-Notes-Data"
else
 DATA_REPO_DIR="${HOME}/OSM-Notes-Data"
fi
readonly DATA_REPO_DIR

readonly EXPORT_DATAMARTS_SCRIPT="${ANALYTICS_DIR}/bin/dwh/exportDatamartsToJSON.sh"

print_info() {
 echo -e "${GREEN}ℹ${NC} $1"
}

print_warn() {
 echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
 echo -e "${RED}✗${NC} $1"
}

print_success() {
 echo -e "${GREEN}✓${NC} $1"
}

# Load database configuration and common functions
if [[ -f "${ANALYTICS_DIR}/etc/properties.sh" ]]; then
 # shellcheck disable=SC1091
 source "${ANALYTICS_DIR}/etc/properties.sh"
fi

# Get database name
DBNAME="${DBNAME_DWH:-notes_dwh}"
readonly DBNAME

# Load common functions if available
if [[ -f "${ANALYTICS_DIR}/lib/osm-common/commonFunctions.sh" ]]; then
 # shellcheck disable=SC1091
 source "${ANALYTICS_DIR}/lib/osm-common/commonFunctions.sh"
fi

# Load validation functions if available
if [[ -f "${ANALYTICS_DIR}/lib/osm-common/validationFunctions.sh" ]]; then
 # shellcheck disable=SC1091
 source "${ANALYTICS_DIR}/lib/osm-common/validationFunctions.sh"
fi

# Pull origin/main; on merge failure prefer remote CSV notes-by-country artifacts.
git_pull_data_repo_merge_csv_resolve() {
 cd "${DATA_REPO_DIR}" || return 1
 git fetch origin main 2> /dev/null || true
 if ! git pull --no-edit origin main 2> /dev/null; then
  print_warn "Merge conflict detected, resolving (taking remote version for CSV files)..."
  git checkout --theirs csv/notes-by-country/*.csv 2> /dev/null || true
  git checkout --theirs csv/notes-by-country/README.md 2> /dev/null || true
  git add csv/notes-by-country/*.csv csv/notes-by-country/README.md 2> /dev/null || true
  git commit --no-edit 2> /dev/null || git merge --abort 2> /dev/null || true
 fi
}

# Mark countries whose JSON is missing or older than MAX_AGE_DAYS so exportDatamartsToJSON picks them up.
mark_stale_countries_for_reexport() {
 print_info "Checking country files for mandatory re-export (missing or older than ${MAX_AGE_DAYS} days)..."
 local cutoff_time
 cutoff_time=$(($(date +%s) - MAX_AGE_DAYS * 24 * 60 * 60))
 local temp_db_output
 temp_db_output=$(mktemp "/tmp/stale_countries_db_XXXXXX.txt")
 psql -d "${DBNAME}" -Atq -c "
SELECT country_id
FROM dwh.datamartcountries
WHERE country_id IS NOT NULL
ORDER BY country_id;
" > "${temp_db_output}"

 local -a stale_ids=()
 while IFS='|' read -r country_id; do
  if [[ -z "${country_id}" ]]; then
   continue
  fi
  local repo_file="${DATA_REPO_DIR}/data/countries/${country_id}.json"
  local stale=false
  if [[ ! -f "${repo_file}" ]]; then
   stale=true
  else
   local file_time
   file_time=$(stat -c %Y "${repo_file}" 2> /dev/null || echo "0")
   if [[ "${file_time}" -lt "${cutoff_time}" ]]; then
    stale=true
   fi
  fi
  if [[ "${stale}" == "true" ]]; then
   stale_ids+=("${country_id}")
  fi
 done < "${temp_db_output}"
 rm -f "${temp_db_output}"

 if [[ ${#stale_ids[@]} -eq 0 ]]; then
  print_info "No stale country files found"
  return 0
 fi

 local id_list
 id_list=$(
  IFS=,
  echo "${stale_ids[*]}"
 )
 print_info "Marking ${#stale_ids[@]} countries for re-export (json_exported := FALSE)"
 psql -d "${DBNAME}" -Atq -c "
  UPDATE dwh.datamartcountries
  SET json_exported = FALSE
  WHERE country_id IN (${id_list});
" > /dev/null 2>&1 || print_warn "Failed to mark stale countries for re-export"
}

run_datamart_json_export() {
 if [[ ! -x "${EXPORT_DATAMARTS_SCRIPT}" ]]; then
  print_error "exportDatamartsToJSON.sh not found or not executable: ${EXPORT_DATAMARTS_SCRIPT}"
  return 1
 fi
 print_info "Running exportDatamartsToJSON.sh (output: ${DATA_REPO_DIR}/data, batch size: ${JSON_EXPORT_BATCH_SIZE})..."
 # Pass overrides via env only: properties.sh sets DBNAME_DWH / JSON_OUTPUT_DIR as readonly; subshell inherits that.
 (
  cd "${ANALYTICS_DIR}" || exit 1
  exec env DBNAME_DWH="${DBNAME}" JSON_OUTPUT_DIR="${DATA_REPO_DIR}/data" JSON_EXPORT_BATCH_SIZE="${JSON_EXPORT_BATCH_SIZE}" "${EXPORT_DATAMARTS_SCRIPT}"
 )
}

# Commit and push JSON tree + schemas when the working tree differs from HEAD.
commit_and_push_json_changes() {
 local timestamp
 timestamp=$(date '+%Y-%m-%d %H:%M:%S')

 cd "${DATA_REPO_DIR}"
 git checkout main 2> /dev/null || true

 if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
  print_warn "Aborting ongoing merge to start clean..."
  git merge --abort 2> /dev/null || true
 fi

 git_pull_data_repo_merge_csv_resolve

 git add -A data schemas 2> /dev/null || true

 if git diff --cached --quiet 2> /dev/null; then
  print_info "No staged JSON/schema changes (skip commit)"
  return 0
 fi

 if ! git commit -m "Auto-update: datamart JSON export - ${timestamp}" > /dev/null 2>&1; then
  print_warn "git commit reported no changes or failed"
  return 0
 fi

 if ! git push origin main > /dev/null 2>&1; then
  print_error "Failed to push JSON export to GitHub"
  return 1
 fi
 print_success "JSON export pushed to GitHub"
 return 0
}

# Remove countries from GitHub that don't exist in local database
remove_obsolete_countries() {
 print_info "Checking for obsolete countries in GitHub..."

 cd "${DATA_REPO_DIR}"
 git checkout main 2> /dev/null || true

 if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
  print_warn "Aborting ongoing merge to start clean..."
  git merge --abort 2> /dev/null || true
 fi

 git_pull_data_repo_merge_csv_resolve

 local db_countries_file
 db_countries_file=$(mktemp "/tmp/db_countries_XXXXXX.txt")
 psql -d "${DBNAME}" -Atq -c "
SELECT country_id
FROM dwh.datamartcountries
WHERE country_id IS NOT NULL
ORDER BY country_id;
" > "${db_countries_file}"

 local github_countries_file
 github_countries_file=$(mktemp "/tmp/github_countries_XXXXXX.txt")
 if [[ -d "${DATA_REPO_DIR}/data/countries" ]]; then
  find "${DATA_REPO_DIR}/data/countries" -name "*.json" -type f \
   | sed 's|.*/||' | sed 's|\.json$||' | sort -n > "${github_countries_file}"
 else
  touch "${github_countries_file}"
 fi

 sort -n -o "${db_countries_file}" "${db_countries_file}" 2> /dev/null || true

 local obsolete_countries
 obsolete_countries=$(comm -23 "${github_countries_file}" "${db_countries_file}" 2> /dev/null || echo "")

 rm -f "${db_countries_file}" "${github_countries_file}"

 if [[ -z "${obsolete_countries}" ]]; then
  print_info "No obsolete countries found"
  return 0
 fi

 local obsolete_count
 obsolete_count=$(echo "${obsolete_countries}" | grep -c . || echo "0")
 print_warn "Found ${obsolete_count} obsolete countries to remove"

 echo "${obsolete_countries}" | while read -r country_id; do
  if [[ -z "${country_id}" ]]; then
   continue
  fi

  local country_file="data/countries/${country_id}.json"
  if [[ -f "${DATA_REPO_DIR}/${country_file}" ]]; then
   print_warn "Removing obsolete country: ${country_id}"
   git rm "${country_file}" > /dev/null 2>&1 || true
  fi
 done

 if ! git diff --cached --quiet; then
  local ots
  ots=$(date '+%Y-%m-%d %H:%M:%S')
  git commit -m "Remove obsolete countries - ${ots}

Removed countries that no longer exist in local database." > /dev/null 2>&1
  git push origin main > /dev/null 2>&1 || print_warn "Failed to push removal of obsolete countries"
  print_success "Removed ${obsolete_count} obsolete countries"
 else
  print_info "No obsolete countries to remove"
 fi
}

# Generate README.md with alphabetical list of countries
generate_countries_readme() {
 print_info "Generating countries README.md..."

 readme_file="${DATA_REPO_DIR}/data/countries/README.md"
 temp_readme=$(mktemp "/tmp/countries_readme_XXXXXX.md")

 cat > "${temp_readme}" << 'EOF'
# Countries Data

This directory contains JSON files with country profiles from OSM Notes Analytics.

## Available Countries

The following countries are available (sorted alphabetically):

EOF

 psql -d "${DBNAME}" -Atq -c "
SELECT
  country_id,
  COALESCE(country_name_en, country_name, 'Unknown') as name
FROM dwh.datamartcountries
WHERE country_id IS NOT NULL
ORDER BY COALESCE(country_name_en, country_name, 'Unknown');
" | while IFS='|' read -r country_id country_name; do
  if [[ -z "${country_id}" ]]; then
   continue
  fi

  local country_file="${country_id}.json"
  if [[ -f "${DATA_REPO_DIR}/data/countries/${country_file}" ]]; then
   echo "- [${country_name}](./${country_file}) (ID: ${country_id})" >> "${temp_readme}"
  fi
 done

 local current_timestamp
 current_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ) || current_timestamp="unknown"
 cat >> "${temp_readme}" << EOF

## Usage

Each JSON file contains complete country profile data including:
- Historical statistics (open, closed, commented notes)
- Resolution metrics
- User activity patterns
- Geographic patterns
- Hashtag usage
- Temporal patterns

## Last Updated

Generated: ${current_timestamp}
EOF

 cp "${temp_readme}" "${readme_file}"
 rm -f "${temp_readme}"

 print_success "Countries README.md generated"
}

setup_lock() {
 print_warn "Validating single execution."
 exec 7> "${LOCK}"
 if ! flock -n 7; then
  print_error "Another instance of ${BASENAME} is already running."
  print_error "Lock file: ${LOCK}"
  if [[ -f "${LOCK}" ]]; then
   print_error "Lock file contents:"
   cat "${LOCK}" || true
  fi
  exit 1
 fi

 cat > "${LOCK}" << EOF
PID: ${ORIGINAL_PID}
Process: ${BASENAME}
Started: ${PROCESS_START_TIME}
Main script: ${0}
EOF
}

cleanup() {
 rm -f "${LOCK}" 2> /dev/null || true
}

trap cleanup EXIT INT TERM

setup_lock

if [[ ! -d "${DATA_REPO_DIR}" ]]; then
 print_error "Data repository not found at: ${DATA_REPO_DIR}"
 echo ""
 echo "Please create the repository first:"
 echo "1. Go to https://github.com/OSM-Notes/OSM-Notes-Data"
 echo "2. Clone it: git clone https://github.com/OSM-Notes/OSM-Notes-Data.git"
 echo ""
 exit 1
fi

print_info "Full datamart JSON export → ${DATA_REPO_DIR}"
print_info "JSON export batch size: ${JSON_EXPORT_BATCH_SIZE} (0 = unlimited per exportDatamartsToJSON)"

cd "${DATA_REPO_DIR}"
git checkout main 2> /dev/null || true

if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
 print_warn "Aborting ongoing merge to start clean..."
 git merge --abort 2> /dev/null || true
fi

git fetch origin main 2> /dev/null || true
local_ahead=$(git rev-list --count origin/main..HEAD 2> /dev/null || echo "0")
if [[ "${local_ahead}" -gt 0 ]]; then
 print_info "Pushing ${local_ahead} pending commit(s) to origin..."
 git push origin main 2> /dev/null || print_warn "Failed to push pending commits, continuing anyway..."
fi

git_pull_data_repo_merge_csv_resolve

mkdir -p "${DATA_REPO_DIR}/data/countries"
mkdir -p "${DATA_REPO_DIR}/data/indexes"
mkdir -p "${DATA_REPO_DIR}/data/users"

print_info "Copying JSON schemas to data repository..."
SCHEMA_SOURCE_DIR="${ANALYTICS_DIR}/lib/osm-common/schemas"
SCHEMA_TARGET_DIR="${DATA_REPO_DIR}/schemas"

if [[ -d "${SCHEMA_SOURCE_DIR}" ]]; then
 mkdir -p "${SCHEMA_TARGET_DIR}"
 rsync -av --include="*.json" --include="README.md" --exclude="*" "${SCHEMA_SOURCE_DIR}/" "${SCHEMA_TARGET_DIR}/" > /dev/null 2>&1 || true
fi

remove_obsolete_countries
mark_stale_countries_for_reexport

if [[ "${SKIP_DATAMART_JSON_EXPORT}" == "true" ]]; then
 print_warn "SKIP_DATAMART_JSON_EXPORT=true — skipping exportDatamartsToJSON.sh"
else
 if ! run_datamart_json_export; then
  print_error "exportDatamartsToJSON.sh failed"
  exit 1
 fi
fi

if ! commit_and_push_json_changes; then
 exit 1
fi

generate_countries_readme

cd "${DATA_REPO_DIR}"
git checkout main 2> /dev/null || true
git_pull_data_repo_merge_csv_resolve
git add "data/countries/README.md" 2> /dev/null || true
if ! git diff --cached --quiet; then
 ts_readme=$(date '+%Y-%m-%d %H:%M:%S')
 git commit -m "Update countries README - ${ts_readme}" > /dev/null 2>&1
 git push origin main > /dev/null 2>&1 || print_warn "Failed to push countries README"
fi

print_success "Export pipeline completed."
print_info "Allow 1–2 minutes for GitHub Pages to update"
print_info "Schemas: https://osm-notes.github.io/OSM-Notes-Data/schemas/"

if [[ "${OSM_NOTES_DATA_SQUASH_AFTER_EXPORT:-false}" == "true" ]]; then
 print_warn "OSM_NOTES_DATA_SQUASH_AFTER_EXPORT=true — collapsing OSM-Notes-Data to one Git commit..."
 squash_script="${ANALYTICS_DIR}/bin/dwh/squashOSMNotesDataGitHistory.sh"
 if [[ ! -x "${squash_script}" ]]; then
  print_warn "Squash helper not executable or missing: ${squash_script} (skip squash)."
 else
  "${squash_script}" --yes || print_warn "History squash skipped or failed — normal export commits remain on origin."
 fi
fi
