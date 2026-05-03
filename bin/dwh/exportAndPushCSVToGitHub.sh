#!/bin/bash

# Exports CSV files and pushes to GitHub Pages data repository
# This script exports closed notes to CSV (one per country) and publishes them
# to the OSM-Notes-Data repository without preserving CSV file history
# (other files in the repository maintain their history)
#
# Usage: ./bin/dwh/exportAndPushCSVToGitHub.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2025-01-XX

set -euo pipefail

# Script basename for log file
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME

# Configure log file when running from cron (not a terminal)
# This prevents output from being sent by email and saves it to a log file instead
if [[ ! -t 1 ]] && [[ "${1:-}" != "--help" ]] && [[ "${1:-}" != "-h" ]]; then
 LOG_DIR="/tmp"
 mkdir -p "${LOG_DIR}"
 LOG_FILE="${LOG_DIR}/${BASENAME}.log"
 # Redirect all output to log file to prevent cron from sending emails
 exec >> "${LOG_FILE}" 2>&1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Loads the global properties
# shellcheck disable=SC1091
source "${ANALYTICS_DIR}/etc/properties.sh"
# Load local properties if they exist (overrides global settings)
if [[ -f "${ANALYTICS_DIR}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${ANALYTICS_DIR}/etc/properties.sh.local"
fi

# SQL script path
SQL_SCRIPT="${ANALYTICS_DIR}/sql/dwh/export/exportClosedNotesByCountry.sql"
readonly SQL_SCRIPT

# Temporary directory for CSV export
TEMP_CSV_DIR=$(mktemp -d "/tmp/csv_export_XXXXXX")
readonly TEMP_CSV_DIR

# Lock file for single execution
LOCK="${TEMP_CSV_DIR}/${BASENAME}.lock"
readonly LOCK

# Function to print colored messages
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

# Function to sanitize country name for filename
function __sanitize_filename() {
 local name="${1}"
 # Replace spaces with underscores, remove special characters
 echo "${name}" | sed 's/ /_/g' | sed 's/[^a-zA-Z0-9_-]//g' | tr '[:upper:]' '[:lower:]'
}

# Function to export notes for a specific country
function __export_country_notes() {
 local country_id="${1}"
 local country_name="${2}"
 local sanitized_name
 sanitized_name=$(__sanitize_filename "${country_name}")

 local output_file="${TEMP_CSV_DIR}/${country_id}_${sanitized_name}.csv"
 local start_time
 local end_time
 local duration

 print_info "Exporting notes for country: ${country_name} (ID: ${country_id})"
 start_time=$(date +%s)

 # Create CSV with header and data
 {
  # Header row (optimized order for AI context)
  echo "note_id,country_name,latitude,longitude,opened_at,closed_at,days_to_resolution,opened_by_username,opening_comment,total_comments,was_reopened,closed_by_username,closing_comment"

  # Data rows - replace :country_id and :max_notes_per_country variables in SQL and execute
  sed -e "s/:country_id/${country_id}/g" -e "s/:max_notes_per_country/${MAX_NOTES_PER_COUNTRY}/g" "${SQL_SCRIPT}" \
   | __psql_with_appname "${BASENAME}-country-${country_id}" -d "${DBNAME_DWH}" \
    --csv \
    -t \
    2> /dev/null
 } > "${output_file}"

 end_time=$(date +%s)
 duration=$((end_time - start_time))

 # Count lines (excluding header)
 local line_count
 line_count=$(wc -l < "${output_file}" | tr -d ' ')
 line_count=$((line_count - 1)) # Subtract header row

 if [[ ${line_count} -gt 0 ]]; then
  print_info "  Exported ${line_count} notes in ${duration}s"
  return 0
 else
  print_warn "  No notes found for country ${country_name} (ID: ${country_id}) in ${duration}s"
  # Remove empty file
  rm -f "${output_file}"
  return 1
 fi
}

# Function to check and filter large CSV files (GitHub limit: 100MB)
# Excludes files larger than 100MB and logs warnings
# Usage: __filter_large_csv_files [directory]
# Returns: 0 if all files OK, 1 if some files were excluded
function __filter_large_csv_files() {
 local csv_dir="${1:-${CSV_TARGET_DIR:-}}"

 # Return early if directory doesn't exist
 if [[ ! -d "${csv_dir}" ]]; then
  return 0
 fi

 local excluded_count=0
 local max_size_mb=100
 local max_size_bytes=$((max_size_mb * 1024 * 1024))

 # Check each CSV file
 while IFS= read -r -d '' csv_file; do
  [[ -z "${csv_file}" ]] && continue

  local file_size
  file_size=$(stat -f%z "${csv_file}" 2> /dev/null || stat -c%s "${csv_file}" 2> /dev/null || echo "0")

  if [[ ${file_size} -gt ${max_size_bytes} ]]; then
   local file_size_mb
   file_size_mb=$((file_size / 1024 / 1024))
   local filename
   filename=$(basename "${csv_file}")

   print_warn "Excluding large file from git: ${filename} (${file_size_mb} MB, exceeds GitHub's 100MB limit)"

   # Remove from git index if already staged
   git rm --cached "${csv_file}" 2> /dev/null || true

   # Remove from target directory (keep in temp for reference)
   rm -f "${csv_file}" 2> /dev/null || true

   excluded_count=$((excluded_count + 1))
  fi
 done < <(find "${csv_dir}" -maxdepth 1 -name "*.csv" -type f -print0 2> /dev/null || true)

 if [[ ${excluded_count} -gt 0 ]]; then
  print_warn "Excluded ${excluded_count} large CSV file(s) from git commit (exceed 100MB limit)"
  print_info "Large files are kept in ${TEMP_CSV_DIR} for reference but not pushed to GitHub"
  return 1
 fi

 return 0
}

# Cleanup function
function __cleanup() {
 rm -rf "${TEMP_CSV_DIR}" 2> /dev/null || true
 rm -f "${COUNTRY_LIST:-}" 2> /dev/null || true
 rm -f "${LOCK:-}" 2> /dev/null || true
}
trap __cleanup EXIT

# Check if data repository exists
if [[ ! -d "${DATA_REPO_DIR}" ]]; then
 print_error "Data repository not found at: ${DATA_REPO_DIR}"
 echo ""
 echo "Please create the repository first:"
 echo "1. Go to https://github.com/OSM-Notes/OSM-Notes-Data"
 echo "2. Clone it: git clone https://github.com/OSM-Notes/OSM-Notes-Data.git ${DATA_REPO_DIR}"
 echo ""
 echo "Or if it exists elsewhere, create a symlink or set DATA_REPO_DIR environment variable"
 echo ""
 exit 1
fi

# Safety check: Prevent execution if DBNAME_DWH looks like a test database
# This prevents accidentally overwriting production CSV files with test data
if [[ "${DBNAME_DWH:-}" =~ ^(test|mock|demo|dev|local).*$ ]] || [[ "${DBNAME_DWH:-}" =~ .*_(test|mock|demo|dev)$ ]]; then
 print_error "Safety check failed: DBNAME_DWH appears to be a test database: ${DBNAME_DWH}"
 echo ""
 echo "This script should only run against production databases to avoid corrupting"
 echo "production data in GitHub. If you need to test, use a separate test repository."
 echo ""
 echo "To override this check, set FORCE_EXPORT=true environment variable"
 if [[ "${FORCE_EXPORT:-}" != "true" ]]; then
  exit 1
 else
  print_warn "FORCE_EXPORT=true is set - proceeding despite test database warning"
 fi
fi

# Validate single execution using flock
print_info "Validating single execution..."
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

# Write lock file information
# Get current timestamp to avoid command substitution in heredoc
start_timestamp=$(date '+%Y-%m-%d %H:%M:%S') || start_timestamp="unknown"
cat > "${LOCK}" << EOF
PID: $$
Process: ${BASENAME}
Started: ${start_timestamp}
Temporary directory: ${TEMP_CSV_DIR}
Main script: ${0}
EOF

# Step 1: Export CSV files
print_info "Step 1: Exporting CSV files from Analytics..."
STEP1_START=$(date +%s)

# Check if dwh schema exists
# shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
if ! __psql_with_appname -d "${DBNAME_DWH}" -Atq -c "SELECT 1 FROM information_schema.schemata WHERE schema_name = 'dwh'" | grep -q 1; then
 print_error "Schema 'dwh' does not exist. Please run the ETL process first."
 exit 1
fi

# Check if SQL script exists
if [[ ! -f "${SQL_SCRIPT}" ]]; then
 print_error "SQL script not found: ${SQL_SCRIPT}"
 exit 1
fi

# Create temporary directory for CSV export
mkdir -p "${TEMP_CSV_DIR}"

# First, sync with GitHub to get latest CSV files for comparison
print_info "Syncing with GitHub to check existing CSV files..."
cd "${DATA_REPO_DIR}" || exit 1
git checkout main 2> /dev/null || true

# Abort any ongoing merge to start clean
if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
 print_warn "Aborting ongoing merge to start clean..."
 git merge --abort 2> /dev/null || true
fi

# Fetch and pull latest changes from GitHub
git fetch origin main 2> /dev/null || true
if ! git pull --no-edit origin main 2> /dev/null; then
 # Pull failed, resolve conflicts by taking our version
 git checkout --ours csv/notes-by-country/*.csv 2> /dev/null || true
 git add csv/notes-by-country/*.csv 2> /dev/null || true
 git commit --no-edit 2> /dev/null || git merge --abort 2> /dev/null || true
fi

# Get list of countries that have closed notes, with last update date
print_info "Getting list of countries with closed notes and last update dates..."
COUNTRY_LIST_START=$(date +%s)

# Export notes for each country
COUNTRY_LIST=$(mktemp)
__psql_with_appname -d "${DBNAME_DWH}" -Atq << 'EOF' > "${COUNTRY_LIST}"
SELECT
  dc.country_id,
  COALESCE(dc.country_name, dc.country_name_en, 'Unknown') AS country_name,
  COALESCE(dc.country_name_en, dc.country_name, 'Unknown') AS country_name_en,
  MAX(f.action_at)::TEXT AS last_close_date
FROM dwh.facts f
  JOIN dwh.dimension_countries dc
    ON f.dimension_id_country = dc.dimension_country_id
WHERE f.action_comment = 'closed'
GROUP BY dc.country_id, dc.country_name, dc.country_name_en
ORDER BY COALESCE(dc.country_name_en, dc.country_name, 'Unknown');
EOF

COUNTRY_LIST_END=$(date +%s)
COUNTRY_LIST_DURATION=$((COUNTRY_LIST_END - COUNTRY_LIST_START))
print_info "Country list retrieved in ${COUNTRY_LIST_DURATION}s"

# Configuration for incremental commits and pushes
# Commit and push every N countries to reduce risk of losing work and avoid large pushes
COUNTRIES_PER_COMMIT="${COUNTRIES_PER_COMMIT:-10}"
readonly COUNTRIES_PER_COMMIT

# Push every N countries exported (should match COUNTRIES_PER_COMMIT for commit+push together)
COUNTRIES_PER_PUSH="${COUNTRIES_PER_PUSH:-10}"
readonly COUNTRIES_PER_PUSH

# Maximum notes per country to export (for AI context)
# This limits the export to the most recent notes to keep files under GitHub's 100MB limit
# Based on Germany: 609K notes = 143 MB, so ~400K notes should be ~94 MB (under 100MB limit)
# For AI context, recent notes are more valuable than very old historical data
MAX_NOTES_PER_COUNTRY="${MAX_NOTES_PER_COUNTRY:-400000}"
readonly MAX_NOTES_PER_COUNTRY

# CSV target directory (needed for incremental commits)
CSV_TARGET_DIR="${DATA_REPO_DIR}/csv/notes-by-country"
mkdir -p "${CSV_TARGET_DIR}"

TOTAL_COUNTRIES=0
EXPORTED_COUNTRIES=0
TOTAL_NOTES=0
EXPORT_START=$(date +%s)
COMMITTED_COUNTRIES=0

# Function to generate README.md with country list and links to CSV files
function __generate_readme() {
 print_info "Generating README.md with country list..."

 local readme_file="${CSV_TARGET_DIR}/README.md"
 local temp_readme
 temp_readme=$(mktemp)
 # Get current timestamp to avoid command substitution in heredoc
 local current_timestamp
 current_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ) || current_timestamp="unknown"

 # Header
 cat > "${temp_readme}" << 'EOF'
# OSM Notes by Country - CSV Exports

This directory contains CSV files with closed notes data for each country from OSM Notes Analytics.

## Available Countries

The following countries are available (sorted alphabetically by English name):

EOF

 # Get all CSV files and extract country IDs
 local csv_files
 csv_files=$(find "${CSV_TARGET_DIR}" -name "*.csv" -type f -printf '%f\n' 2> /dev/null | sort)

 if [[ -z "${csv_files}" ]]; then
  print_warn "No CSV files found to generate README"
  rm -f "${temp_readme}"
  return 1
 fi

 # Create temporary file to store country info
 local country_info_file
 country_info_file=$(mktemp)

 # Get country information from database for all countries that have CSV files
 local country_ids
 country_ids=$(echo "${csv_files}" | sed -n 's/^\([0-9]\+\).*\.csv$/\1/p' | sort -u | tr '\n' ',' | sed 's/,$//')

 if [[ -n "${country_ids}" ]]; then
  # Query database for country names in English and save to temp file
  local db_results_file
  db_results_file=$(mktemp)
  __psql_with_appname -d "${DBNAME_DWH}" -Atq << EOF > "${db_results_file}"
SELECT
  dc.country_id,
  COALESCE(dc.country_name_en, dc.country_name, 'Unknown') AS country_name_en,
  COALESCE(dc.country_name, dc.country_name_en, 'Unknown') AS country_name_local
FROM dwh.dimension_countries dc
WHERE dc.country_id IN (${country_ids})
ORDER BY COALESCE(dc.country_name_en, dc.country_name, 'Unknown');
EOF

  # Process database results
  while IFS='|' read -r country_id country_name_en country_name_local; do
   if [[ -n "${country_id}" ]]; then
    # Find the CSV file for this country (may have different name formats)
    local csv_file
    csv_file=$(echo "${csv_files}" | grep "^${country_id}_" | head -1)

    if [[ -n "${csv_file}" ]]; then
     # Store country info: country_name_en|country_id|csv_file|country_name_local
     echo "${country_name_en}|${country_id}|${csv_file}|${country_name_local}" >> "${country_info_file}"
    fi
   fi
  done < "${db_results_file}"
  rm -f "${db_results_file}"
 fi

 # Sort by English name and generate README entries
 if [[ -f "${country_info_file}" ]]; then
  sort -t'|' -k1,1 "${country_info_file}" | while IFS='|' read -r country_name_en country_id csv_file country_name_local; do
   if [[ -n "${country_name_en}" && -n "${csv_file}" ]]; then
    # Format: - [English Name (Local Name)](./filename.csv) (ID: country_id)
    if [[ "${country_name_en}" != "${country_name_local}" && "${country_name_local}" != "Unknown" ]]; then
     echo "- [${country_name_en} (${country_name_local})](./${csv_file}) (ID: ${country_id})" >> "${temp_readme}"
    else
     echo "- [${country_name_en}](./${csv_file}) (ID: ${country_id})" >> "${temp_readme}"
    fi
   fi
  done
  rm -f "${country_info_file}"
 else
  # Fallback: if database query failed, list files by filename
  echo "${csv_files}" | while read -r csv_file; do
   local country_id
   country_id=$(echo "${csv_file}" | sed -n 's/^\([0-9]\+\).*\.csv$/\1/p')
   if [[ -n "${country_id}" ]]; then
    echo "- [Country ID: ${country_id}](./${csv_file})" >> "${temp_readme}"
   fi
  done
 fi

 # Footer
 cat >> "${temp_readme}" << EOF

## CSV File Format

Each CSV file contains the following columns:

- **note_id**: OSM note ID
- **country_name**: Country name
- **latitude**: Note latitude
- **longitude**: Note longitude
- **opened_at**: Date and time when note was opened
- **closed_at**: Date and time when note was closed
- **days_to_resolution**: Days from open to close
- **opened_by_username**: Username who opened the note
- **opening_comment**: Initial comment (cleaned, max 2000 chars)
- **total_comments**: Total number of comments on the note
- **was_reopened**: Whether note was reopened before final close (0/1)
- **closed_by_username**: Username who closed the note
- **closing_comment**: Comment when note was closed (cleaned, max 2000 chars)

## Notes

- Files are limited to the most recent notes (up to 400,000 per country) to keep file sizes manageable
- Files larger than 100MB are excluded from the repository (GitHub's file size limit)
- Data is updated automatically from the OSM Notes Analytics database

## Last Updated

Generated: ${current_timestamp}
EOF

 # Copy to target directory
 cp "${temp_readme}" "${readme_file}"
 rm -f "${temp_readme}"

 local file_count
 file_count=$(echo "${csv_files}" | wc -l)
 print_success "README.md generated with ${file_count} countries"
 return 0
}

# Rolling CSV mode uses "git commit --amend" to keep a single commit locally. That rewrites
# the commit hash, so origin/main still points at the pre-amend tip and a normal push is
# rejected (non-fast-forward). git pull/merge does not fix that reliably. Sync with
# --force-with-lease, which is safe if no one else pushed in the meantime.
function __is_rolling_csv_head_commit() {
 local msg
 msg=$(git log -1 --pretty=%B 2> /dev/null || true)
 echo "${msg}" | grep -q "Auto-update.*CSV files"
}

# Function to commit and push current batch of CSV files
function __commit_and_push_batch() {
 local batch_start="${1}"
 local batch_end="${2}"
 local batch_count="${3}"

 print_info "Committing batch: countries ${batch_start}-${batch_end} (${batch_count} countries)"

 cd "${DATA_REPO_DIR}"

 # Configure git safe.directory if needed (for dubious ownership error)
 git config --global --add safe.directory "${DATA_REPO_DIR}" 2> /dev/null || true

 # Check and fix permissions if needed
 # The .git directory should be writable by the current user
 CURRENT_USER=$(whoami)
 GIT_OWNER=$(stat -c '%U' "${DATA_REPO_DIR}/.git" 2> /dev/null || echo "unknown")
 GIT_GROUP=$(stat -c '%G' "${DATA_REPO_DIR}/.git" 2> /dev/null || echo "unknown")

 if [[ ! -w "${DATA_REPO_DIR}/.git" ]]; then
  print_warn "Git directory not writable. Checking ownership..."

  if [[ "${CURRENT_USER}" != "${GIT_OWNER}" ]]; then
   # Check if user is in the git owner's group
   if groups "${CURRENT_USER}" 2> /dev/null | grep -q "\b${GIT_GROUP}\b"; then
    # User is in the group, try to fix group permissions
    print_info "User ${CURRENT_USER} is in group ${GIT_GROUP}, checking group permissions..."
    if [[ -r "${DATA_REPO_DIR}/.git" ]]; then
     # Try to make group writable
     chmod -R g+w "${DATA_REPO_DIR}/.git" 2> /dev/null || true
     if [[ -w "${DATA_REPO_DIR}/.git" ]]; then
      print_success "Fixed group permissions"
     else
      print_error "Could not fix group permissions. Owner: ${GIT_OWNER}, Group: ${GIT_GROUP}"
      print_error "Please run: sudo chmod -R g+w ${DATA_REPO_DIR}/.git"
      print_error "Or: sudo chown -R ${CURRENT_USER}:${CURRENT_USER} ${DATA_REPO_DIR}/.git"
      return 1
     fi
    else
     print_error "Cannot read git directory. Please fix permissions."
     return 1
    fi
   else
    print_error "Git directory owned by ${GIT_OWNER}:${GIT_GROUP}, but script running as ${CURRENT_USER}"
    print_error "Please fix ownership: sudo chown -R ${CURRENT_USER}:${CURRENT_USER} ${DATA_REPO_DIR}/.git"
    print_error "Or add ${CURRENT_USER} to ${GIT_GROUP} group: sudo usermod -a -G ${GIT_GROUP} ${CURRENT_USER}"
    return 1
   fi
  else
   # Same owner, try to fix permissions
   if ! chmod -R u+w "${DATA_REPO_DIR}/.git" 2> /dev/null; then
    print_error "Could not fix git directory permissions"
    return 1
   fi
  fi
 fi

 # Remove stale lock file if it exists
 if [[ -f "${DATA_REPO_DIR}/.git/index.lock" ]]; then
  print_warn "Removing stale git lock file..."
  if ! rm -f "${DATA_REPO_DIR}/.git/index.lock" 2> /dev/null; then
   # Try with different user if we have sudo access
   if command -v sudo > /dev/null 2>&1 && [[ "${CURRENT_USER}" != "${GIT_OWNER}" ]]; then
    sudo -u "${GIT_OWNER}" rm -f "${DATA_REPO_DIR}/.git/index.lock" 2> /dev/null || true
   fi
   if [[ -f "${DATA_REPO_DIR}/.git/index.lock" ]]; then
    print_error "Could not remove lock file. Please remove manually:"
    print_error "  sudo rm -f ${DATA_REPO_DIR}/.git/index.lock"
    return 1
   fi
  fi
 fi

 # Ensure we're on main branch
 git checkout main 2> /dev/null || true

 # Abort any ongoing merge to start clean
 if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
  print_warn "Aborting ongoing merge to start clean..."
  git merge --abort 2> /dev/null || true
 fi

 # Fetch latest changes
 git fetch origin main 2> /dev/null || true

 # Check if remote has changes
 local remote_commit
 local local_commit
 remote_commit=$(git rev-parse origin/main 2> /dev/null || echo "")
 local_commit=$(git rev-parse HEAD 2> /dev/null || echo "")

 if [[ -n "${remote_commit}" && -n "${local_commit}" && "${remote_commit}" != "${local_commit}" ]]; then
  # Remote has changes, pull with strategy to prefer our CSV files
  print_info "Remote has changes, pulling and resolving conflicts..."

  # Try to pull with ours strategy for CSV files
  if ! git pull --no-edit origin main 2> /dev/null; then
   # Pull failed due to conflicts, resolve by taking our version for CSV files
   print_info "Resolving merge conflicts (taking local version for CSV files)..."

   # For CSV files, always take our version
   git checkout --ours csv/notes-by-country/*.csv 2> /dev/null || true
   git add csv/notes-by-country/*.csv 2> /dev/null || true

   # Complete the merge
   git commit --no-edit 2> /dev/null || git merge --abort 2> /dev/null || true
  fi
 else
  # No remote changes or already up to date
  git pull origin main 2> /dev/null || true
 fi

 # Copy ALL CSV files from temp dir (accumulated so far)
 # This ensures we have all files from previous batches plus current batch
 rsync -av --exclude='*.lock' --exclude='*.log' "${TEMP_CSV_DIR}/" "${CSV_TARGET_DIR}/" > /dev/null 2>&1

 # Remove any non-CSV files that might have been copied (lock files, etc.)
 find "${CSV_TARGET_DIR}" -type f ! -name "*.csv" -delete 2> /dev/null || true

 # Filter out files that exceed GitHub's 100MB limit BEFORE adding to git
 # This is critical to prevent pushing large files
 __filter_large_csv_files "${CSV_TARGET_DIR}"

 # Generate/update README.md with all countries (after copying all CSV files)
 # Don't fail if README generation fails (non-critical)
 # shellcheck disable=SC2310  # Function invocation in || condition is intentional for error handling
 __generate_readme || print_warn "README generation failed, continuing anyway..."

 # Remove CSV directory from git index if this is the first batch
 if [[ ${COMMITTED_COUNTRIES} -eq 0 ]] && git ls-files --error-unmatch csv/notes-by-country/ > /dev/null 2>&1; then
  print_info "Removing existing CSV files from git history..."
  git rm -r --cached csv/notes-by-country/ 2> /dev/null || true
 fi

 # Add all CSV files in target directory (excluding large ones already filtered)
 git add csv/notes-by-country/*.csv 2> /dev/null || true

 # Add README.md if it exists
 if [[ -f "${CSV_TARGET_DIR}/README.md" ]]; then
  git add csv/notes-by-country/README.md 2> /dev/null || true
 fi

 # Check if there are changes to commit
 # Try different methods for compatibility with different git versions
 local has_changes=false
 if git diff --staged --quiet 2> /dev/null; then
  has_changes=false
 elif git diff --cached --quiet 2> /dev/null; then
  has_changes=false
 elif git status --porcelain csv/notes-by-country/ 2> /dev/null | grep -qE "^A|^M"; then
  has_changes=true
 else
  # Last resort: check if files were actually added
  if git status --short csv/notes-by-country/ 2> /dev/null | grep -q .; then
   has_changes=true
  fi
 fi

 if [[ "${has_changes}" == "false" ]]; then
  print_warn "No changes to commit in this batch"
  return 0
 fi

 # Get file count for commit message
 FILE_COUNT=$(find csv/notes-by-country/ -name "*.csv" 2> /dev/null | wc -l || echo "0")
 TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

 # Check if we're in the middle of a merge
 local in_merge=false
 if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
  in_merge=true
  print_warn "In the middle of a merge, will complete merge instead of amending"
 fi

 # Check if the last commit was a CSV update (to use --amend and avoid history)
 # This keeps only the latest CSV version in git history
 # But don't amend if we're in a merge
 local use_amend=false
 if [[ "${in_merge}" == "false" ]]; then
  local last_commit_msg
  last_commit_msg=$(git log -1 --pretty=%B 2> /dev/null || echo "")
  if echo "${last_commit_msg}" | grep -q "Auto-update.*CSV files"; then
   use_amend=true
   print_info "Previous CSV commit found, will amend to replace it (no history preserved)"
  fi
 fi

 # Commit changes locally (amend if previous commit was CSV to avoid history)
 # But if in merge, complete the merge instead
 local commit_output
 if [[ "${in_merge}" == "true" ]]; then
  # Complete the merge by taking our version of CSV files
  git checkout --ours csv/notes-by-country/*.csv 2> /dev/null || true
  git add csv/notes-by-country/*.csv 2> /dev/null || true
  commit_output=$(git commit --no-edit -m "Auto-update: ${FILE_COUNT} CSV files (closed notes by country) - ${TIMESTAMP}

This commit replaces all previous CSV files. CSV history is not preserved.
Total countries exported: ${EXPORTED_COUNTRIES}
Total notes: ${TOTAL_NOTES}" 2>&1)
 elif [[ "${use_amend}" == "true" ]]; then
  commit_output=$(git commit --amend -m "Auto-update: ${FILE_COUNT} CSV files (closed notes by country) - ${TIMESTAMP}

This commit replaces all previous CSV files. CSV history is not preserved.
Total countries exported: ${EXPORTED_COUNTRIES}
Total notes: ${TOTAL_NOTES}" 2>&1)
 else
  commit_output=$(git commit -m "Auto-update: ${FILE_COUNT} CSV files (closed notes by country) - ${TIMESTAMP}

This commit replaces all previous CSV files. CSV history is not preserved.
Total countries exported: ${EXPORTED_COUNTRIES}
Total notes: ${TOTAL_NOTES}" 2>&1)
 fi
 local commit_exit_code=$?

 if [[ ${commit_exit_code} -eq 0 ]]; then
  print_success "Batch ${batch_start}-${batch_end} committed locally (${FILE_COUNT} CSV files)"
  COMMITTED_COUNTRIES=$((COMMITTED_COUNTRIES + batch_count))

  # Push immediately after commit (since commit and push happen together every N countries)
  print_info "Pushing to GitHub (${EXPORTED_COUNTRIES} countries exported)..."
  local push_output
  push_output=$(git push origin main 2>&1) || true
  local push_exit_code=$?
  if [[ ${push_exit_code} -ne 0 ]] && echo "${push_output}" | grep -qE "non-fast-forward|diverged" && __is_rolling_csv_head_commit; then
   print_info "Amended rolling CSV commit: replacing remote tip with push --force-with-lease"
   push_output=$(git push --force-with-lease origin main 2>&1) || true
   push_exit_code=$?
  fi

  if [[ ${push_exit_code} -eq 0 ]]; then
   print_success "Pushed successfully (${EXPORTED_COUNTRIES} countries exported)"
  else
   # Check if push failed due to non-fast-forward (diverged branches)
   if echo "${push_output}" | grep -q "non-fast-forward\|diverged"; then
    print_warn "Branches have diverged, attempting to resolve..."

    # Fetch latest changes
    git fetch origin main 2> /dev/null || true

    # Abort any ongoing merge
    if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
     git merge --abort 2> /dev/null || true
    fi

    # Resolve conflicts by taking our CSV version
    if git pull --no-edit origin main 2> /dev/null; then
     # Pull succeeded, try push again
     push_output=$(git push origin main 2>&1)
     push_exit_code=$?
     if [[ ${push_exit_code} -eq 0 ]]; then
      print_success "Pushed successfully after resolving conflicts (${EXPORTED_COUNTRIES} countries exported)"
     else
      print_error "Failed to push after resolving conflicts"
      print_error "Git push error: ${push_output}"
      print_warn "Continuing export, but push failed. Will retry at end."
      return 2
     fi
    else
     # Pull failed, resolve conflicts manually
     print_info "Resolving merge conflicts (taking local version for CSV files)..."
     git checkout --ours csv/notes-by-country/*.csv 2> /dev/null || true
     git add csv/notes-by-country/*.csv 2> /dev/null || true
     git commit --no-edit 2> /dev/null || true

     # Try push again
     push_output=$(git push origin main 2>&1)
     push_exit_code=$?
     if [[ ${push_exit_code} -eq 0 ]]; then
      print_success "Pushed successfully after manual conflict resolution (${EXPORTED_COUNTRIES} countries exported)"
     else
      print_error "Failed to push after manual conflict resolution"
      print_error "Git push error: ${push_output}"
      print_warn "Continuing export, but push failed. Will retry at end."
      return 2
     fi
    fi
   else
    print_error "Failed to push to GitHub"
    print_error "Git push error: ${push_output}"
    print_warn "Continuing export, but push failed. Will retry at end."
    return 2
   fi
  fi

  return 0
 else
  print_error "Failed to commit batch ${batch_start}-${batch_end}"
  print_error "Git commit error: ${commit_output}"
  return 1
 fi
}

BATCH_START=1
BATCH_COUNT=0

# Function to check if CSV needs update
# Returns 0 if CSV needs update, 1 if CSV is up to date
function __csv_needs_update() {
 local country_id="${1}"
 local country_name="${2}"
 local last_close_date="${3}"
 local sanitized_name
 sanitized_name=$(__sanitize_filename "${country_name}")

 # Check for CSV file in git (more reliable than filesystem)
 # Search for any CSV file that starts with country_id_ (handles both formats)
 local csv_file_in_git=""
 local csv_file_pattern="${country_id}_*.csv"

 # Find CSV file in git for this country ID
 # Use git ls-files to find files matching the pattern
 csv_file_in_git=$(cd "${DATA_REPO_DIR}" && git ls-files "csv/notes-by-country/${csv_file_pattern}" 2> /dev/null | head -1)

 # If no file found in git, needs update
 if [[ -z "${csv_file_in_git}" ]]; then
  return 0
 fi

 # Get git commit date for this file (most reliable)
 local git_commit_date=0
 if [[ -n "${csv_file_in_git}" ]]; then
  git_commit_date=$(cd "${DATA_REPO_DIR}" && git log -1 --format=%ct -- "${csv_file_in_git}" 2> /dev/null | head -1)
  # If git_commit_date is empty or invalid, try to get it from the file
  if [[ -z "${git_commit_date}" ]] || ! [[ "${git_commit_date}" =~ ^[0-9]+$ ]]; then
   git_commit_date=0
  fi
 fi

 # Also check filesystem modification time as fallback
 local csv_file_fs
 csv_file_fs="${CSV_TARGET_DIR}/$(basename "${csv_file_in_git}")"
 local csv_mtime=0
 if [[ -f "${csv_file_fs}" ]]; then
  csv_mtime=$(stat -c%Y "${csv_file_fs}" 2> /dev/null || stat -f%m "${csv_file_fs}" 2> /dev/null || echo "0")
 fi

 # Use the most recent date (git commit or file modification)
 local csv_timestamp=${git_commit_date}
 if [[ ${csv_mtime} -gt ${git_commit_date} ]]; then
  csv_timestamp=${csv_mtime}
 fi

 # Convert last_close_date to timestamp
 # PostgreSQL returns timestamps in format: YYYY-MM-DD HH:MI:SS or YYYY-MM-DD HH:MI:SS.MS
 local db_timestamp=0
 if [[ -n "${last_close_date}" ]]; then
  # Remove milliseconds and timezone if present
  local clean_date
  clean_date=$(echo "${last_close_date}" | sed 's/\.[0-9]*//' | sed 's/+.*//' | sed 's/-.*//')
  # Try different date parsing methods
  db_timestamp=$(date -d "${clean_date}" +%s 2> /dev/null \
   || date -d "${last_close_date}" +%s 2> /dev/null \
   || echo "0")
 fi

 # If we can't parse dates or CSV timestamp is invalid, export to be safe
 if [[ ${csv_timestamp} -eq 0 ]] || [[ ${db_timestamp} -eq 0 ]]; then
  return 0
 fi

 # Get current timestamp
 local current_timestamp
 current_timestamp=$(date +%s)

 # If CSV was committed recently (within last 24 hours), consider it up to date
 # This prevents re-exporting if CSV was just updated
 local csv_age_hours=$(((current_timestamp - csv_timestamp) / 3600))
 if [[ ${csv_age_hours} -lt 24 ]]; then
  # CSV is recent (less than 24 hours old), consider it up to date
  return 1
 fi

 # CSV is older than 24 hours, check if database has significantly newer data
 # Only export if database has data more than 1 hour newer than CSV
 local time_diff=$((db_timestamp - csv_timestamp))
 if [[ ${time_diff} -gt 3600 ]]; then
  # Database has data more than 1 hour newer than CSV, needs update
  return 0
 fi

 # CSV is up to date (either recent or no significant new data)
 return 1
}

while IFS='|' read -r country_id country_name country_name_en last_close_date; do
 if [[ -n "${country_id}" && -n "${country_name}" ]]; then
  TOTAL_COUNTRIES=$((TOTAL_COUNTRIES + 1))

  # Check if CSV needs update
  # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
  if __csv_needs_update "${country_id}" "${country_name}" "${last_close_date}"; then
   # shellcheck disable=SC2310  # Function invocation in condition is intentional for error handling
   if __export_country_notes "${country_id}" "${country_name}"; then
    EXPORTED_COUNTRIES=$((EXPORTED_COUNTRIES + 1))
    BATCH_COUNT=$((BATCH_COUNT + 1))

    # Count notes in the file
    sanitized_name=$(__sanitize_filename "${country_name}")
    file_notes=$(wc -l < "${TEMP_CSV_DIR}/${country_id}_${sanitized_name}.csv" | tr -d ' ')
    file_notes=$((file_notes - 1)) # Subtract header
    TOTAL_NOTES=$((TOTAL_NOTES + file_notes))

    # Commit and push every COUNTRIES_PER_COMMIT countries
    if [[ ${BATCH_COUNT} -ge ${COUNTRIES_PER_COMMIT} ]]; then
     BATCH_END=${EXPORTED_COUNTRIES}
     if __commit_and_push_batch "${BATCH_START}" "${BATCH_END}" "${BATCH_COUNT}"; then
      BATCH_START=$((BATCH_END + 1))
      BATCH_COUNT=0
     else
      print_warn "Continuing despite commit failure. Will retry at end."
     fi
    fi
   fi
  else
   # CSV is up to date, skip export
   print_info "Skipping ${country_name} (ID: ${country_id}) - CSV is up to date"
  fi
 fi
done < "${COUNTRY_LIST}"

# Commit and push remaining countries if any
if [[ ${BATCH_COUNT} -gt 0 ]]; then
 BATCH_END=${EXPORTED_COUNTRIES}
 __commit_and_push_batch "${BATCH_START}" "${BATCH_END}" "${BATCH_COUNT}"
fi

# Step 2: Final push check (push any remaining commits)
print_info "Step 2: Final push check..."
STEP2_START=$(date +%s)
cd "${DATA_REPO_DIR}"

# Check if there are any unpushed commits
unpushed_commits=$(git log --oneline origin/main..HEAD --grep="Auto-update.*CSV files" 2> /dev/null | wc -l || echo "0")

if [[ ${unpushed_commits} -gt 0 ]]; then
 print_info "Pushing ${unpushed_commits} remaining commit(s)..."
 set +e
 final_push_out=$(git push origin main 2>&1)
 final_push_ec=$?
 if [[ ${final_push_ec} -ne 0 ]] && echo "${final_push_out}" | grep -qE "non-fast-forward|diverged" && __is_rolling_csv_head_commit; then
  print_info "Amended rolling CSV commit: replacing remote tip with push --force-with-lease"
  final_push_out=$(git push --force-with-lease origin main 2>&1)
  final_push_ec=$?
 fi
 set -e
 if [[ ${final_push_ec} -eq 0 ]]; then
  STEP2_END=$(date +%s)
  STEP2_DURATION=$((STEP2_END - STEP2_START))
  print_success "All commits pushed successfully in ${STEP2_DURATION}s"
 else
  print_error "Failed to push remaining commits"
  print_error "Git: ${final_push_out}"
  print_warn "Some commits may not have been pushed. Check git status."
 fi
else
 print_info "All commits already pushed"
fi

STEP2_END=$(date +%s)
STEP2_DURATION=$((STEP2_END - STEP2_START))
print_success "Step 2 completed in ${STEP2_DURATION}s"

rm -f "${COUNTRY_LIST}"

EXPORT_END=$(date +%s)
EXPORT_DURATION=$((EXPORT_END - EXPORT_START))

if [[ ${EXPORTED_COUNTRIES} -eq 0 ]]; then
 print_warn "No CSV files were exported"
 exit 0
fi

STEP1_END=$(date +%s)
STEP1_DURATION=$((STEP1_END - STEP1_START))

# Calculate average time per country (using integer division)
AVG_TIME_PER_COUNTRY=0
if [[ ${EXPORTED_COUNTRIES} -gt 0 ]]; then
 AVG_TIME_PER_COUNTRY=$((EXPORT_DURATION / EXPORTED_COUNTRIES))
fi

print_success "Export completed: ${EXPORTED_COUNTRIES} countries, ${TOTAL_NOTES} total notes"
print_info "Export timing: ${EXPORT_DURATION}s (countries: ${EXPORTED_COUNTRIES}, avg: ${AVG_TIME_PER_COUNTRY}s per country)"
print_info "Step 1 total time: ${STEP1_DURATION}s"

# Final summary
TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - STEP1_START))

print_success "All CSV files exported"
# Calculate total batches committed locally
TOTAL_BATCHES_LOCAL=$((COMMITTED_COUNTRIES / COUNTRIES_PER_COMMIT))
if [[ $((COMMITTED_COUNTRIES % COUNTRIES_PER_COMMIT)) -gt 0 ]]; then
 TOTAL_BATCHES_LOCAL=$((TOTAL_BATCHES_LOCAL + 1))
fi
print_info "Total batches committed locally: ${TOTAL_BATCHES_LOCAL}"
echo ""
echo "CSV files are now available at:"
echo "https://github.com/OSM-Notes/OSM-Notes-Data/tree/main/csv/notes-by-country"
echo ""
echo "Raw file access:"
echo "https://raw.githubusercontent.com/OSM-Notes/OSM-Notes-Data/main/csv/notes-by-country/"
echo ""
print_info "Total execution time: ${TOTAL_DURATION}s"
print_info "Note: CSV file history is not preserved. Only the latest version is kept in git."

echo ""
print_success "Done! CSV files updated in GitHub repository"
print_info "Note: CSV file history is not preserved. Each export replaces previous CSV files."
