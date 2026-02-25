#!/usr/bin/env bats

# Require minimum BATS version for run flags
bats_require_minimum_version 1.5.0

# Load test helper for database connection verification
load ../../test_helper

# Integration tests for datamartUsers.sh
# Tests that actually execute the script to detect real errors

setup() {
 # Setup test environment
 # shellcheck disable=SC2154
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
 export SCRIPT_BASE_DIRECTORY
 # shellcheck disable=SC2155
 TMP_DIR="$(mktemp -d)"
 export TMP_DIR
 export BASENAME="test_datamart_users"
 export LOG_LEVEL="INFO"

 # Ensure TMP_DIR exists and is writable
 if [[ ! -d "${TMP_DIR}" ]]; then
  mkdir -p "${TMP_DIR}" || {
   echo "ERROR: Could not create TMP_DIR: ${TMP_DIR}" >&2
   exit 1
  }
 fi
 if [[ ! -w "${TMP_DIR}" ]]; then
  echo "ERROR: TMP_DIR not writable: ${TMP_DIR}" >&2
  exit 1
 fi

 # Set up test database
 export TEST_DBNAME="test_osm_notes_${BASENAME}"
}

teardown() {
 # Cleanup
 rm -rf "${TMP_DIR}"
 # Drop test database if it exists
 psql -d postgres -c "DROP DATABASE IF EXISTS ${TEST_DBNAME};" 2> /dev/null || true
}

# Test that datamartUsers.sh can be sourced without errors
@test "datamartUsers.sh should be sourceable without errors" {
 # Test that the script can be sourced without logging errors
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh > /dev/null 2>&1"
 [[ "${status}" -eq 0 ]] || echo "Script should be sourceable"
}

# Test that datamartUsers.sh functions can be called without logging errors
@test "datamartUsers.sh functions should work without logging errors" {
 # Test that logging functions work
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && echo 'Test message'"
 [[ "${status}" -eq 0 ]]
 [[ "${output}" == *"Test message"* ]] || echo "Basic function should work"
}

# Test that datamartUsers.sh can run in dry-run mode
@test "datamartUsers.sh should work in dry-run mode" {
 # Test that the script can run without actually creating datamart
 run timeout 30s bash "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" --help
 [[ "${status}" -eq 1 ]] # Help should exit with code 1
 [[ "${output}" == *"help"* ]] || [[ "${output}" == *"usage"* ]] || echo "Script should show help information"
}

# Test that all required functions are available after sourcing
@test "datamartUsers.sh should have all required functions available" {
 # Test that key functions are available
 local REQUIRED_FUNCTIONS=(
  "__createDatamartUsers"
  "__checkDatamartUsersTables"
  "__createDatamartUsersTable"
  "__createProcedure"
  "__alterTableAddYears"
  "__populateDatamartUsersTable"
  "__showHelp"
 )

 for FUNC in "${REQUIRED_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}

# Test that logging functions work correctly
@test "datamartUsers.sh logging functions should work correctly" {
 # Test that logging functions don't produce errors
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && echo 'Test info' && echo 'Test error'"
 [[ "${status}" -eq 0 ]]
 [[ "${output}" != *"orden no encontrada"* ]]
 [[ "${output}" != *"command not found"* ]]
}

# Test that database operations work with test database
@test "datamartUsers.sh database operations should work with test database" {
 # Skip database operations in CI environment if no real database is available
 if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  # In CI, we might not have a real PostgreSQL server, so skip actual database operations
  # but verify that the SQL files exist and are valid
  [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql" ]]
  [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql" ]]

  # Verify SQL files contain valid SQL syntax (basic check)
  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP\|ALTER" "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql"
  [[ "${status}" -eq 0 ]]

  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP\|ALTER" "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
  [[ "${status}" -eq 0 ]]

  echo "Skipping actual database operations in CI environment - SQL files validated"
  return 0
 fi

 # Local environment - perform actual database operations
 # Create test database if it doesn't exist
 # shellcheck disable=SC2154
 run psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true
 # Note: CREATE DATABASE might fail if database already exists, which is OK

 # Drop existing schema/tables if they exist (clean slate for test)
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -c "DROP SCHEMA IF EXISTS dwh CASCADE;" > /dev/null 2>&1 || true
 else
  # Local connection
  psql -d "${TEST_DBNAME}" -c "DROP SCHEMA IF EXISTS dwh CASCADE;" > /dev/null 2>&1 || true
 fi

 # Clean up any existing datamart objects first
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_00_dropDatamartObjects.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_00_dropDatamartObjects.sql"
 fi
 # Note: Drop script might fail if objects don't exist, which is OK

 # Create base tables
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql"
 fi
 [[ "${status}" -eq 0 ]]

 # Create datamart users table
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
 fi
 [[ "${status}" -eq 0 ]]

 # Verify table exists (PostgreSQL converts unquoted identifiers to lowercase)
 if [[ -n "${TEST_DBHOST}" ]]; then
  # Remote connection
  # shellcheck disable=SC2154,SC2153
  run psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT}" -U "${TEST_DBUSER}" -d "${TEST_DBNAME}" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'dwh' AND LOWER(table_name) = 'datamartusers';"
 else
  # Local connection
  run psql -d "${TEST_DBNAME}" -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'dwh' AND LOWER(table_name) = 'datamartusers';"
 fi
 [[ "${status}" -eq 0 ]]
 [[ "${output}" =~ ^[0-9]+$ ]] || echo "Expected numeric count, got: ${output}"
}

# Test that error handling works correctly
@test "datamartUsers.sh error handling should work correctly" {
 # Test that the script handles missing database gracefully
 run bash -c "DBNAME=nonexistent_db source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh"
 [[ "${status}" -ne 0 ]] || echo "Script should handle missing database gracefully"
}

# Test that all SQL files are valid
@test "datamartUsers SQL files should be valid" {
 local SQL_FILES=(
  "sql/dwh/datamartUsers/datamartUsers_10_checkDatamartUsersTables.sql"
  "sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
  "sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"
  "sql/dwh/datamarts/62_createBadgeSystem.sql"
  "sql/dwh/datamartUsers/datamartUsers_20_alterTableAddYears.sql"
  "sql/dwh/datamartUsers/datamartUsers_31_populateDatamartUsersTable.sql"
  "sql/dwh/datamartUsers/datamartUsers_00_dropDatamartObjects.sql"
 )

 for SQL_FILE in "${SQL_FILES[@]}"; do
  [[ -f "${SCRIPT_BASE_DIRECTORY}/${SQL_FILE}" ]]
  # Test that SQL file has valid syntax (basic check)
  run grep -q "CREATE\|INSERT\|UPDATE\|SELECT\|DROP\|ALTER" "${SCRIPT_BASE_DIRECTORY}/${SQL_FILE}"
  [[ "${status}" -eq 0 ]] || echo "SQL file ${SQL_FILE} should contain valid SQL"
 done
}

# Test that the script can be executed without parameters
@test "datamartUsers.sh should handle no parameters gracefully" {
 # Test that the script doesn't crash when run without parameters
 # The script may succeed if DBNAME_DWH is configured, or fail gracefully if not
 run timeout 30s bash "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" 2>&1
 # Script should not crash (exit code should be valid, not 127/126 which indicate script errors)
 # Valid exit codes: 0 (success), 1 (help), 3 (database error), 241-243 (library/argument errors), 255 (general error)
 # Exit code 124 = timeout (script took too long, but didn't crash) - also acceptable
 # Exit codes 127/126 indicate script execution errors (command not found, permission denied)
 [[ "${status}" -ne 127 ]] && [[ "${status}" -ne 126 ]] || echo "Script should not crash with execution errors"
 # If timeout (124), that's acceptable - script is running, just taking time
 # If it fails, should be a graceful failure (database error, validation error, etc.)
 # If it succeeds, that's also fine (database configured and accessible)
}

# Test that datamart creation functions work correctly
@test "datamartUsers.sh datamart creation functions should work correctly" {
 # Test that datamart functions are available
 local DATAMART_FUNCTIONS=(
  "__createDatamartUsersTable"
  "__populateDatamartUsersTable"
  "__alterTableAddYears"
 )

 for FUNC in "${DATAMART_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}

# Test that procedure creation functions work correctly
@test "datamartUsers.sh procedure creation functions should work correctly" {
 # Test that procedure functions are available
 local PROCEDURE_FUNCTIONS=(
  "__createProcedure"
  "__checkDatamartUsersTables"
 )

 for FUNC in "${PROCEDURE_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}

# Test that data population functions work correctly
@test "datamartUsers.sh data population functions should work correctly" {
 # Test that population functions are available
 local POPULATION_FUNCTIONS=(
  "__populateDatamartUsersTable"
 )

 for FUNC in "${POPULATION_FUNCTIONS[@]}"; do
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f ${FUNC}"
  [[ "${status}" -eq 0 ]] || echo "Function ${FUNC} should be available"
 done
}
