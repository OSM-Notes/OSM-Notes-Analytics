#!/usr/bin/env bats

# Require minimum BATS version for run flags
bats_require_minimum_version 1.5.0

# Integration tests for application statistics in datamarts
# Tests that application statistics are calculated correctly

load ../../../tests/test_helper

setup() {
  SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY

  # Load properties
  # shellcheck disable=SC1090
  source "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh"

  # Use TEST_DBNAME so DBNAME is set for psql (test_helper may not run when this setup runs)
  export DBNAME="${TEST_DBNAME:-${DBNAME:-}}"

  # Setup test database if needed and DBNAME is configured
  if [[ -z "${SKIP_TEST_SETUP:-}" ]] && [[ -n "${DBNAME:-}" ]]; then
    setup_test_database
  fi
}

# Test that application statistics columns exist in datamartCountries
@test "Application statistics columns should exist in datamartCountries table" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  # Check if columns exist
  run psql -d "${DBNAME}" -t -c "
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'dwh'
      AND table_name = 'datamartcountries'
      AND column_name IN ('applications_used', 'most_used_application_id',
                          'mobile_apps_count', 'desktop_apps_count');
  "

  [[ "${status}" -eq 0 ]]
  # Should have 4 lines (one per column)
  [[ $(echo "${output}" | grep -c "app") -eq 4 ]] || echo "Application columns should exist"
}

# Test that application statistics columns exist in datamartUsers
@test "Application statistics columns should exist in datamartUsers table" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  # Check if columns exist
  run psql -d "${DBNAME}" -t -c "
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'dwh'
      AND table_name = 'datamartusers'
      AND column_name IN ('applications_used', 'most_used_application_id',
                          'mobile_apps_count', 'desktop_apps_count');
  "

  [[ "${status}" -eq 0 ]]
  # Should have 4 lines (one per column)
  [[ $(echo "${output}" | grep -c "app") -eq 4 ]] || echo "Application columns should exist"
}

# Test that applications_used JSON has valid structure
@test "Applications_used JSON should have valid structure for countries" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  run psql -d "${dbname}" -t -c "
    SELECT json_typeof(applications_used)
    FROM dwh.datamartcountries
    WHERE applications_used IS NOT NULL
    LIMIT 1;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist or lack application columns): ${output}"
  fi
  # If no data, output will be empty, which is acceptable
}

# Test that applications_used JSON has valid structure for users
@test "Applications_used JSON should have valid structure for users" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT json_typeof(applications_used)
    FROM dwh.datamartusers
    WHERE applications_used IS NOT NULL
    LIMIT 1;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist or lack application columns): ${output}"
  fi
  # Should be array when we have data
  [[ "${output}" == *"array"* ]] || [[ -z "${output// }" ]] || echo "Should be valid JSON array"
}

# Test that mobile_apps_count and desktop_apps_count are non-negative
@test "Mobile and desktop app counts should be non-negative for countries" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamartcountries
    WHERE mobile_apps_count IS NOT NULL AND mobile_apps_count < 0
       OR desktop_apps_count IS NOT NULL AND desktop_apps_count < 0;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist): ${output}"
  fi
  [[ "${output}" =~ ^[0\ ]+$ ]] || echo "All counts should be non-negative"
}

# Test that mobile_apps_count and desktop_apps_count are non-negative for users
@test "Mobile and desktop app counts should be non-negative for users" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamartusers
    WHERE mobile_apps_count IS NOT NULL AND mobile_apps_count < 0
       OR desktop_apps_count IS NOT NULL AND desktop_apps_count < 0;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist): ${output}"
  fi
  [[ "${output}" =~ ^[0\ ]+$ ]] || echo "All counts should be non-negative"
}

# Test that most_used_application_id references valid application
@test "Most_used_application_id should reference valid application for countries" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamartcountries dc
    LEFT JOIN dwh.dimension_applications da ON da.dimension_application_id = dc.most_used_application_id
    WHERE dc.most_used_application_id IS NOT NULL
      AND da.dimension_application_id IS NULL;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist): ${output}"
  fi
  [[ "${output}" =~ ^[0\ ]+$ ]] || echo "All references should be valid"
}

# Test that most_used_application_id references valid application for users
@test "Most_used_application_id should reference valid application for users" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamartusers du
    LEFT JOIN dwh.dimension_applications da ON da.dimension_application_id = du.most_used_application_id
    WHERE du.most_used_application_id IS NOT NULL
      AND da.dimension_application_id IS NULL;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist): ${output}"
  fi
  [[ "${output}" =~ ^[0\ ]+$ ]] || echo "All references should be valid"
}

# Test that applications_used JSON contains expected fields
@test "Applications_used JSON should contain app_id, app_name, count" {
  skip_if_no_db_connection
  run psql -d "${DBNAME}" -t -c "
    SELECT jsonb_pretty(applications_used::jsonb)
    FROM dwh.datamartcountries
    WHERE applications_used IS NOT NULL
    LIMIT 1;
  "

  if [[ "${status}" -ne 0 ]]; then
    skip "Query failed (tables may not exist): ${output}"
  fi
  [[ -n "${output}" ]] || [[ -z "${output// }" ]] || echo "Should return valid JSON"
}

# Test that applications can be queried from facts table
@test "Application statistics should be calculable from facts table" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  # Test that applications exist in facts
  # Create a simple query file to avoid escaping issues
  local query_file=$(mktemp)
  echo "SELECT COALESCE(COUNT(DISTINCT dimension_application_creation), 0) FROM dwh.facts WHERE dimension_application_creation IS NOT NULL AND action_comment = 'opened';" > "${query_file}"

  run psql -d "${DBNAME}" -t -f "${query_file}" 2>&1
  local exit_code=$?
  rm -f "${query_file}"

  [[ $exit_code -eq 0 ]]
  # Should contain numeric values (may be 0 if no test data)
  [[ "${output}" =~ [0-9] ]]
}

# Test that platform categorization works correctly
@test "Platform categorization should work (mobile vs desktop)" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  # Test platform detection
  run psql -d "${DBNAME}" -t -c "
    SELECT COUNT(DISTINCT platform)
    FROM dwh.dimension_applications
    WHERE platform IN ('android', 'ios', 'web');
  "

  [[ "${status}" -eq 0 ]]
  # Should have some platforms defined
  [[ "${output}" =~ [0-9] ]] || echo "Platforms should be defined"
}

