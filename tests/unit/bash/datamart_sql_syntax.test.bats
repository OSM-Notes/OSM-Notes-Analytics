#!/usr/bin/env bats

# Test that datamart SQL procedures can be created without syntax errors
# This test executes the SQL files directly to catch syntax errors that
# wouldn't be detected by static analysis or grep-based tests.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-01-11

load ../../../tests/test_helper

setup() {
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
 export SCRIPT_BASE_DIRECTORY

 # Load properties
 # shellcheck disable=SC1090
 source "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh"

 # Only setup if DBNAME/TEST_DBNAME is configured
 if [[ -z "${SKIP_TEST_SETUP:-}" ]] && [[ -n "${TEST_DBNAME:-}" ]]; then
  setup_test_database
 fi
}

# Test that datamartCountries procedure can be created without syntax errors
@test "datamartCountries_12_createProcedure.sql should create procedure without syntax errors" {
 skip_if_no_db_connection
 local dbname="${TEST_DBNAME:-${DBNAME}}"
 local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"

 # Skip if file doesn't exist
 [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

 # First, ensure required tables exist
 run psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2>&1
 [[ "${status}" -eq 0 ]]

 # Create minimal required tables for the procedure
 run psql -d "${dbname}" << 'EOF'
    CREATE TABLE IF NOT EXISTS dwh.dimension_countries (
      dimension_country_id SERIAL PRIMARY KEY,
      country_id INTEGER,
      country_name VARCHAR(100),
      country_name_es VARCHAR(100),
      country_name_en VARCHAR(100),
      iso_alpha2 VARCHAR(2),
      iso_alpha3 VARCHAR(3),
      region_id INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_regions (
      dimension_region_id SERIAL PRIMARY KEY,
      region_name_es VARCHAR(60),
      region_name_en VARCHAR(60),
      continent_id INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_continents (
      dimension_continent_id SERIAL PRIMARY KEY,
      continent_name_es VARCHAR(32),
      continent_name_en VARCHAR(32)
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_days (
      dimension_day_id SERIAL PRIMARY KEY,
      date_id DATE
    );
    CREATE TABLE IF NOT EXISTS dwh.facts (
      fact_id SERIAL PRIMARY KEY,
      id_note INTEGER,
      sequence_action INTEGER,
      dimension_id_country INTEGER,
      opened_dimension_id_date INTEGER,
      closed_dimension_id_date INTEGER,
      action_dimension_id_date INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.datamartCountries (
      dimension_country_id INTEGER PRIMARY KEY
    );
EOF
 [[ "${status}" -eq 0 ]]

 # Try to create the procedure - this will catch syntax errors
 run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1

 # Check for specific error patterns that indicate syntax issues
 if [[ "${status}" -ne 0 ]]; then
  echo "SQL execution failed with exit code ${status}"
  echo "Output: ${output}"
  # Check for common syntax errors
  if echo "${output}" | grep -q "record.*is not assigned"; then
   fail "SQL syntax error: record variable conflict detected"
  fi
  if echo "${output}" | grep -q "syntax error"; then
   fail "SQL syntax error detected"
  fi
  if echo "${output}" | grep -q "ERROR:"; then
   fail "SQL execution error detected"
  fi
 fi

 [[ "${status}" -eq 0 ]]
}

# Test that datamartUsers procedure can be created without syntax errors
@test "datamartUsers_12_createProcedure.sql should create procedure without syntax errors" {
 skip_if_no_db_connection
 local dbname="${TEST_DBNAME:-${DBNAME}}"
 local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"

 # Skip if file doesn't exist
 [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

 # First, ensure required tables exist
 run psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2>&1
 [[ "${status}" -eq 0 ]]

 # Create minimal required tables for the procedure
 run psql -d "${dbname}" << 'EOF'
    CREATE TABLE IF NOT EXISTS dwh.dimension_users (
      dimension_user_id SERIAL PRIMARY KEY,
      user_id INTEGER,
      username VARCHAR(256),
      modified BOOLEAN,
      is_current BOOLEAN
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_days (
      dimension_day_id SERIAL PRIMARY KEY,
      date_id DATE
    );
    CREATE TABLE IF NOT EXISTS dwh.facts (
      fact_id SERIAL PRIMARY KEY,
      id_note INTEGER,
      sequence_action INTEGER,
      action_dimension_id_user INTEGER,
      opened_dimension_id_user INTEGER,
      closed_dimension_id_user INTEGER,
      action_dimension_id_date INTEGER,
      opened_dimension_id_date INTEGER,
      closed_dimension_id_date INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.datamartUsers (
      dimension_user_id INTEGER PRIMARY KEY
    );
EOF
 [[ "${status}" -eq 0 ]]

 # Try to create the procedure - this will catch syntax errors
 run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1

 # Check for specific error patterns
 if [[ "${status}" -ne 0 ]]; then
  echo "SQL execution failed with exit code ${status}"
  echo "Output: ${output}"
  # Check for common syntax errors
  if echo "${output}" | grep -q "readonly"; then
   fail "Variable readonly error detected (should be handled in shell script, not SQL)"
  fi
  if echo "${output}" | grep -q "syntax error"; then
   fail "SQL syntax error detected"
  fi
  if echo "${output}" | grep -q "ERROR:"; then
   fail "SQL execution error detected"
  fi
 fi

 [[ "${status}" -eq 0 ]]
}

# Test that insert_datamart_country procedure can be called without errors
@test "insert_datamart_country procedure should execute without record variable errors" {
 skip_if_no_db_connection
 local dbname="${TEST_DBNAME:-${DBNAME}}"

 # Ensure schema and tables exist
 run psql -d "${dbname}" << 'EOF'
    CREATE SCHEMA IF NOT EXISTS dwh;
    CREATE TABLE IF NOT EXISTS dwh.dimension_countries (
      dimension_country_id SERIAL PRIMARY KEY,
      country_id INTEGER,
      country_name VARCHAR(100),
      country_name_es VARCHAR(100),
      country_name_en VARCHAR(100),
      iso_alpha2 VARCHAR(2),
      iso_alpha3 VARCHAR(3),
      region_id INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_regions (
      dimension_region_id SERIAL PRIMARY KEY,
      region_name_es VARCHAR(60),
      region_name_en VARCHAR(60),
      continent_id INTEGER
    );
    CREATE TABLE IF NOT EXISTS dwh.dimension_continents (
      dimension_continent_id SERIAL PRIMARY KEY,
      continent_name_es VARCHAR(32),
      continent_name_en VARCHAR(32)
    );
    INSERT INTO dwh.dimension_continents (continent_name_es, continent_name_en) VALUES ('América', 'Americas') ON CONFLICT DO NOTHING;
    INSERT INTO dwh.dimension_regions (region_name_es, region_name_en, continent_id) VALUES ('Test', 'Test', 1) ON CONFLICT DO NOTHING;
    INSERT INTO dwh.dimension_countries (country_id, country_name, country_name_es, country_name_en, iso_alpha2, iso_alpha3, region_id) VALUES (1, 'Test', 'Test', 'Test', 'TT', 'TST', 1) ON CONFLICT DO NOTHING;
EOF
 [[ "${status}" -eq 0 ]]

 # Load the procedure
 local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"
 [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

 run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
 [[ "${status}" -eq 0 ]]

 # Try to call the procedure - this will catch runtime errors like "record is not assigned"
 run psql -d "${dbname}" -v ON_ERROR_STOP=1 -c "CALL dwh.insert_datamart_country(1);" 2>&1

 # Check for the specific error we're trying to catch
 if echo "${output}" | grep -q "record.*is not assigned"; then
  fail "Procedure has record variable conflict error"
 fi

 # Procedure might fail for other reasons (missing tables, etc.) but should not fail with record error
 # We don't require success, just that it doesn't fail with the specific error we're testing for
 if [[ "${status}" -ne 0 ]] && echo "${output}" | grep -q "record.*is not assigned"; then
  fail "Procedure failed with record variable error"
 fi
}
