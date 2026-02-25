#!/usr/bin/env bats

# Application and version detection tests (staging.get_application, dwh.get_application_version_id).
# Uses real-world note comment samples. Run SQL test when DB has dwh + staging objects (e.g. after ETL).
# Author: Andres Gomez (AngocA)

bats_require_minimum_version 1.5.0

load ../../test_helper

SCRIPT_BASE_DIRECTORY=""
SQL_TEST_FILE=""

setup() {
  SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY
  SQL_TEST_FILE="${SCRIPT_BASE_DIRECTORY}/tests/unit/sql/application_version_detection.test.sql"
  export SQL_TEST_FILE
  export TEST_DBNAME="${TEST_DBNAME:-notes_dwh}"
}

# Test file exists
@test "application_version_detection.test.sql should exist" {
  [[ -f "${SQL_TEST_FILE}" ]]
}

# Test file contains real-world samples and expected functions
@test "application_version_detection.test.sql should reference get_application and version detection" {
  grep -q "staging.get_application" "${SQL_TEST_FILE}"
  grep -q "get_application_version_id" "${SQL_TEST_FILE}"
  grep -q "Opened with iD" "${SQL_TEST_FILE}"
  grep -q "dimension_applications" "${SQL_TEST_FILE}"
}

# When DB is available and has dwh + staging: run SQL test (real-world samples)
@test "application and version detection SQL test should pass when DB has dwh and staging" {
  if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    skip "Skip DB-dependent test in CI if no database"
  fi

  psql_cmd=$(build_psql_cmd "${TEST_DBNAME}")
  # Probe DB and required objects
  run $psql_cmd -tAc "SELECT 1 FROM dwh.dimension_applications LIMIT 1;" 2>&1
  if [[ "${status}" -ne 0 ]]; then
    skip "DB or dwh.dimension_applications not available"
  fi

  run $psql_cmd -tAc "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'staging' AND proname = 'get_application';" 2>&1
  if [[ "${status}" -ne 0 ]] || [[ -z "${output// }" ]]; then
    skip "staging.get_application not found"
  fi

  run $psql_cmd -v ON_ERROR_STOP=1 -f "${SQL_TEST_FILE}" 2>&1
  if [[ "${status}" -ne 0 ]]; then
    echo "Output: ${output}"
    return 1
  fi
  [[ "${output}" == *"passed"* ]]
}
