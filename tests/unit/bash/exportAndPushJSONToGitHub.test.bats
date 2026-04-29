#!/usr/bin/env bats
# Test suite for exportAndPushJSONToGitHub.sh script
# Author: Andres Gomez (AngocA)
# Version: 2026-04-28

# Require minimum BATS version
bats_require_minimum_version 1.5.0

# Load test helper
load ../../test_helper

# Get script directory (go up from tests/unit/bash to project root)
SCRIPT_BASE_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." &> /dev/null && pwd)"
readonly SCRIPT_BASE_DIR

# Test that script exists and is executable
@test "exportAndPushJSONToGitHub.sh script exists and is executable" {
  [ -f "${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh" ]
  [ -x "${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh" ]
}

# Test that script has required functions
@test "exportAndPushJSONToGitHub.sh contains required functions" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "run_datamart_json_export" "${script_file}"
  grep -q "mark_stale_countries_for_reexport" "${script_file}"
  grep -q "commit_and_push_json_changes" "${script_file}"
  grep -q "remove_obsolete_countries" "${script_file}"
  grep -q "generate_countries_readme" "${script_file}"
  grep -q "git_pull_data_repo_merge_csv_resolve" "${script_file}"
}

# Test that script has correct default configuration
@test "exportAndPushJSONToGitHub.sh has correct default configuration" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q 'MAX_AGE_DAYS="${MAX_AGE_DAYS:-30}"' "${script_file}"
  grep -q 'JSON_EXPORT_BATCH_SIZE="${JSON_EXPORT_BATCH_SIZE:-10000}"' "${script_file}"
}

# Test that script delegates to exportDatamartsToJSON for full tree
@test "exportAndPushJSONToGitHub.sh invokes exportDatamartsToJSON.sh" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "exportDatamartsToJSON.sh" "${script_file}"
  grep -q "EXPORT_DATAMARTS_SCRIPT" "${script_file}"
}

# Test that script includes cleanup of obsolete countries
@test "exportAndPushJSONToGitHub.sh includes obsolete country cleanup" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "remove_obsolete_countries" "${script_file}"
  grep -q "^remove_obsolete_countries()" "${script_file}"
}

# Test that script generates README.md
@test "exportAndPushJSONToGitHub.sh generates countries README.md" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "generate_countries_readme" "${script_file}"
  grep -q "^generate_countries_readme()" "${script_file}"
}

# Test that script can mark countries for re-export
@test "exportAndPushJSONToGitHub.sh marks stale countries for re-export" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "json_exported = FALSE" "${script_file}"
  grep -q "UPDATE dwh.datamartcountries" "${script_file}"
}

# Test that script checks for obsolete countries logic
@test "exportAndPushJSONToGitHub.sh checks for obsolete countries logic" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "comm -23" "${script_file}"
  grep -q "git rm" "${script_file}"
}

# Test that script generates README with alphabetical order
@test "exportAndPushJSONToGitHub.sh generates README in alphabetical order" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "ORDER BY.*country_name" "${script_file}" || \
  grep -q "ORDER BY.*COALESCE" "${script_file}"
}

# Test that script fatals if export fails
@test "exportAndPushJSONToGitHub.sh exits on exportDatamartsToJSON failure" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "exportDatamartsToJSON.sh failed" "${script_file}"
}

# Test that script has lock file mechanism
@test "exportAndPushJSONToGitHub.sh has lock file mechanism" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "setup_lock" "${script_file}"
  grep -q "flock" "${script_file}"
  grep -q "LOCK=" "${script_file}"
}

# Test that script has cleanup on exit
@test "exportAndPushJSONToGitHub.sh has cleanup on exit" {
  local script_file="${SCRIPT_BASE_DIR}/bin/dwh/exportAndPushJSONToGitHub.sh"

  grep -q "cleanup()" "${script_file}"
  grep -q "trap cleanup" "${script_file}"
}
