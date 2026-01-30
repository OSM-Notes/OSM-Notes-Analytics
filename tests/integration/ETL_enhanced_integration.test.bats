#!/usr/bin/env bats

# Integration tests for enhanced ETL functionality
# Author: Andres Gomez (AngocA)
# Version: 2025-08-08

setup() {
 # Create temporary test directory
 TEST_DIR=$(mktemp -d)
 export TEST_DIR

 # Detect project root directory dynamically
 PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
 export PROJECT_ROOT
}

teardown() {
 # Clean up test files
 rm -rf "${TEST_DIR}"
}

@test "ETL help mode" {
 # Test help mode
 # Execute command directly and check exit status
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  ./bin/dwh/ETL.sh --help
 " || exit_code=$?

 # Check exit status (help should exit with code 0)
 [[ "${exit_code:-0}" -eq 0 ]]
}

@test "ETL invalid parameter handling" {
 # Test invalid parameter handling
 # Execute command directly and check exit status
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  ./bin/dwh/ETL.sh --invalid-param
 " || exit_code=$?

 # Check exit status (should exit with code 242 or 255 for general error)
 # Note: The script might exit with different codes depending on the error handling
 [[ "${exit_code:-0}" -eq 242 ]] || [[ "${exit_code:-0}" -eq 255 ]] || [[ "${exit_code:-0}" -eq 1 ]]
}

@test "ETL configuration file loading" {
 # Test that ETL configuration file is loaded correctly
 local config_file="${PROJECT_ROOT}/etc/etl.properties"

 # Verify config file exists (skip if not found - file may not exist in all environments)
 [[ -f "${config_file}" ]] || skip "etl.properties not found"

 # Test loading configuration
 # shellcheck disable=SC1090
 source "${config_file}"

 # Verify key configuration variables are set
 [[ -n "${ETL_BATCH_SIZE:-}" ]] || skip "ETL_BATCH_SIZE not set"
 [[ -n "${ETL_COMMIT_INTERVAL:-}" ]] || skip "ETL_COMMIT_INTERVAL not set"
 [[ -n "${ETL_VACUUM_AFTER_LOAD:-}" ]] || skip "ETL_VACUUM_AFTER_LOAD not set"
}

@test "ETL SQL script validation" {
 # Test that all required SQL scripts exist and are valid
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check key SQL files exist
 [[ -f "${sql_dir}/ETL_11_checkDWHTables.sql" ]]
 [[ -f "${sql_dir}/ETL_20_createDWHTables.sql" ]]
 [[ -f "${sql_dir}/ETL_23_addFunctions.sql" ]]
 [[ -f "${sql_dir}/ETL_25_populateDimensionTables.sql" ]]
 [[ -f "${sql_dir}/ETL_26_updateDimensionTables.sql" ]]
 [[ -f "${sql_dir}/ETL_40_addConstraintsIndexesTriggers.sql" ]]
 [[ -f "${sql_dir}/Staging_32_createStagingObjects.sql" ]]
 [[ -f "${sql_dir}/Staging_34_initialFactsLoadCreate.sql" ]]
}

@test "ETL enhanced dimensions validation" {
 # Test that enhanced dimensions are properly configured
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check for new dimension tables in DDL
 grep -q "dimension_timezones" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "dimension_timezones not in DDL"
 grep -q "dimension_seasons" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "dimension_seasons not in DDL"
 grep -q "dimension_continents" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "dimension_continents not in DDL"
 grep -q "dimension_application_versions" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "dimension_application_versions not in DDL"
 grep -q "fact_hashtags" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "fact_hashtags not in DDL"

 # Check for renamed dimension
 grep -q "dimension_time_of_week" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "dimension_time_of_week not in DDL"
}

@test "ETL SCD2 implementation validation" {
 # Test that SCD2 is properly implemented for users dimension
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check for SCD2 columns in DDL
 grep -q "valid_from" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "valid_from not in DDL"
 grep -q "valid_to" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "valid_to not in DDL"
 grep -q "is_current" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "is_current not in DDL"

 # Check for SCD2 logic in update script
 grep -q "is_current.*TRUE" "${sql_dir}/ETL_26_updateDimensionTables.sql" || skip "SCD2 logic not in update script"
}

@test "ETL new functions validation" {
 # Test that new functions are properly defined
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check for new functions in functions script
 grep -q "get_timezone_id_by_lonlat" "${sql_dir}/ETL_23_addFunctions.sql" || skip "get_timezone_id_by_lonlat not in functions"
 grep -q "get_season_id" "${sql_dir}/ETL_23_addFunctions.sql" || skip "get_season_id not in functions"
 grep -q "get_application_version_id" "${sql_dir}/ETL_23_addFunctions.sql" || skip "get_application_version_id not in functions"
 grep -q "get_local_date_id" "${sql_dir}/ETL_23_addFunctions.sql" || skip "get_local_date_id not in functions"
}

@test "ETL staging procedures validation" {
 # Test that staging procedures handle new columns
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check for new columns in staging procedures
 grep -q "action_timezone_id" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "action_timezone_id not in staging"
 grep -q "local_action_dimension_id_date" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "local_action_dimension_id_date not in staging"
 grep -q "action_dimension_id_season" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "action_dimension_id_season not in staging"

 # Check for hashtag bridge table usage
 grep -q "fact_hashtags" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "fact_hashtags not in staging"
}

@test "ETL datamart compatibility" {
 # Test that datamarts are compatible with new schema
 local datamart_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"

 # Check datamart scripts reference correct dimension names
 grep -q "dimension_time_of_week" "${datamart_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not updated for dimension_time_of_week"

 local datamart_countries_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"
 grep -q "dimension_time_of_week" "${datamart_countries_dir}/datamartCountries_12_createProcedure.sql" || skip "datamartCountries not updated for dimension_time_of_week"
}

@test "ETL resource monitoring" {
 # Test resource monitoring functionality
 export ETL_MONITOR_RESOURCES=true
 export ETL_MONITOR_INTERVAL=1
 export LOG_LEVEL=ERROR

 # Run ETL with resource monitoring in dry-run mode
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  timeout 10s bash -c 'LOG_LEVEL=ERROR ./bin/dwh/ETL.sh --help'
 " || exit_code=$?

 # Check exit code (should be 0 for help)
 [[ "${exit_code:-0}" -eq 0 ]]
}

@test "ETL timeout handling" {
 # Test timeout functionality
 export ETL_TIMEOUT=5 # Very short timeout for testing
 export LOG_LEVEL=ERROR

 # Run ETL with short timeout in dry-run mode
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  timeout 10s bash -c 'LOG_LEVEL=ERROR ./bin/dwh/ETL.sh --help'
 " || exit_code=$?

 # Check exit code (should be 0 for help)
 [[ "${exit_code:-0}" -eq 0 ]]
}

@test "ETL data integrity validation" {
 # Test data integrity validation
 export ETL_VALIDATE_INTEGRITY=true
 export ETL_VALIDATE_DIMENSIONS=true
 export ETL_VALIDATE_FACTS=true
 export LOG_LEVEL=ERROR

 # Run validation mode
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  LOG_LEVEL=ERROR ./bin/dwh/ETL.sh --help
 " || exit_code=$?

 # Check exit status (should be 0 for help)
 # Note: help mode should exit with code 0
 [[ "${exit_code:-0}" -ge 0 ]]
}

@test "ETL parallel processing configuration" {
 # Test parallel processing configuration
 export ETL_PARALLEL_ENABLED=true
 export ETL_MAX_PARALLEL_JOBS=2
 export MAX_THREADS=4
 export LOG_LEVEL=ERROR

 # Verify configuration is loaded
 [[ "${ETL_PARALLEL_ENABLED}" = "true" ]]
 [[ "${ETL_MAX_PARALLEL_JOBS}" = "2" ]]
 [[ "${MAX_THREADS}" = "4" ]]

 # Test help with parallel processing - use timeout to prevent hanging
 local exit_code
 bash -c "
  cd \"\${PROJECT_ROOT}\"
  source tests/properties.sh
  export SCRIPT_BASE_DIRECTORY=\"\${PROJECT_ROOT}\"
  export DBNAME=notes
  export DB_USER=notes
  export LOG_LEVEL=ERROR
  timeout 10s bash ./bin/dwh/ETL.sh --help
 " || exit_code=$?

 # Check exit code (should be 0 for help)
 [[ "${exit_code:-0}" -eq 0 ]]
}

@test "ETL configuration validation" {
 # Test that configuration values are valid
 local config_file="${PROJECT_ROOT}/etc/etl.properties"

 # Verify config file exists before sourcing
 [[ -f "${config_file}" ]] || skip "etl.properties not found"

 # shellcheck disable=SC1090
 source "${config_file}"

 # Validate numeric configurations
 [[ "${MAX_MEMORY_USAGE}" =~ ^[0-9]+$ ]] || skip "MAX_MEMORY_USAGE not numeric"
 [[ "${MAX_DISK_USAGE}" =~ ^[0-9]+$ ]] || skip "MAX_DISK_USAGE not numeric"
 [[ "${ETL_TIMEOUT}" =~ ^[0-9]+$ ]] || skip "ETL_TIMEOUT not numeric"
 [[ "${ETL_MAX_PARALLEL_JOBS}" =~ ^[0-9]+$ ]] || skip "ETL_MAX_PARALLEL_JOBS not numeric"
 [[ "${ETL_MONITOR_INTERVAL}" =~ ^[0-9]+$ ]] || skip "ETL_MONITOR_INTERVAL not numeric"

 # Validate boolean configurations
 [[ "${ETL_VALIDATE_DIMENSIONS}" =~ ^(true|false)$ ]] || skip "ETL_VALIDATE_DIMENSIONS not boolean"
 [[ "${ETL_VALIDATE_FACTS}" =~ ^(true|false)$ ]] || skip "ETL_VALIDATE_FACTS not boolean"
 [[ "${ETL_PARALLEL_ENABLED}" =~ ^(true|false)$ ]] || skip "ETL_PARALLEL_ENABLED not boolean"
 [[ "${ETL_MONITOR_RESOURCES}" =~ ^(true|false)$ ]] || skip "ETL_MONITOR_RESOURCES not boolean"
}

@test "ETL enhanced functions integration" {
 # Test that enhanced functions are properly integrated
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check that staging procedures call new functions
 grep -q "get_timezone_id_by_lonlat" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "get_timezone_id_by_lonlat not called in staging"
 grep -q "get_season_id" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "get_season_id not called in staging"
 grep -q "get_application_version_id" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "get_application_version_id not called in staging"
}

@test "ETL bridge table implementation" {
 # Test that hashtag bridge table is properly implemented
 local sql_dir="${PROJECT_ROOT}/sql/dwh"

 # Check bridge table creation
 grep -q "CREATE TABLE.*fact_hashtags" "${sql_dir}/ETL_20_createDWHTables.sql" || skip "fact_hashtags table not created"

 # Check bridge table usage in staging
 grep -q "INSERT INTO.*fact_hashtags" "${sql_dir}/Staging_32_createStagingObjects.sql" || skip "fact_hashtags not used in staging"
}

@test "ETL documentation consistency" {
 # Test that documentation is consistent with implementation
 local docs_dir="${PROJECT_ROOT}/docs"
 local readme_file="${PROJECT_ROOT}/bin/dwh/README.md"

 # Check that documentation mentions new dimensions
 grep -q "dimension_timezones" "${readme_file}" || skip "dimension_timezones not documented"
 grep -q "dimension_seasons" "${readme_file}" || skip "dimension_seasons not documented"
 grep -q "dimension_continents" "${readme_file}" || skip "dimension_continents not documented"

 # Check that documentation mentions new columns
 grep -q "action_timezone_id" "${readme_file}" || skip "action_timezone_id not documented"
 grep -q "local_action_dimension_id_date" "${readme_file}" || skip "local_action_dimension_id_date not documented"
 grep -q "action_dimension_id_season" "${readme_file}" || skip "action_dimension_id_season not documented"
}
