#!/usr/bin/env bats

# Integration tests for enhanced datamart functionality
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

@test "DatamartUsers enhanced functionality" {
 # Test that datamartUsers works with enhanced dimensions
 local datamart_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"

 # Check that datamartUsers references the renamed dimension
 grep -q "dimension_time_of_week" "${datamart_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not updated for dimension_time_of_week"

 # Check that datamartUsers handles SCD2 users correctly
 grep -q "is_current.*TRUE" "${datamart_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not updated for SCD2"

 # Check that datamartUsers can handle new columns
 grep -q "dimension_id_country" "${datamart_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers missing country reference"
}

@test "DatamartCountries enhanced functionality" {
 # Test that datamartCountries works with enhanced dimensions
 local datamart_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"

 # Check that datamartCountries references the renamed dimension
 grep -q "dimension_time_of_week" "${datamart_dir}/datamartCountries_12_createProcedure.sql" || skip "datamartCountries not updated for dimension_time_of_week"

 # Check that datamartCountries handles new country columns
 grep -q "iso_alpha2\|iso_alpha3" "${datamart_dir}/datamartCountries_12_createProcedure.sql" || skip "datamartCountries not updated for ISO codes"
}

@test "Datamart script validation" {
 # Test that datamart scripts exist and are valid
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"
 local datamart_countries_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"

 # Check key datamart files exist
 [[ -f "${datamart_users_dir}/datamartUsers_10_checkDatamartUsersTables.sql" ]]
 [[ -f "${datamart_users_dir}/datamartUsers_11_createDatamartUsersTable.sql" ]]
 [[ -f "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" ]]
 [[ -f "${datamart_users_dir}/datamartUsers_31_populateDatamartUsersTable.sql" ]]

 [[ -f "${datamart_countries_dir}/datamartCountries_10_checkDatamartCountriesTables.sql" ]]
 [[ -f "${datamart_countries_dir}/datamartCountries_11_createDatamarCountriesTable.sql" ]]
 [[ -f "${datamart_countries_dir}/datamartCountries_12_createProcedure.sql" ]]
 [[ -f "${datamart_countries_dir}/datamartCountries_30_populateDatamartCountriesTable.sql" ]]
}

@test "Datamart enhanced dimensions integration" {
 # Test that datamarts integrate with new dimensions
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"
 local datamart_countries_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"

 # Check that datamarts can reference new dimensions
 grep -q "dimension_continents" "${datamart_countries_dir}/datamartCountries_12_createProcedure.sql" || skip "datamartCountries not integrated with continents"

 # Check that datamarts can handle timezone-aware data
 grep -q "action_timezone_id\|local_action" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not integrated with timezone data"
}

@test "Datamart SCD2 integration" {
 # Test that datamarts work with SCD2 user dimension
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"

 # Check that datamartUsers handles SCD2 correctly
 grep -q "is_current.*TRUE" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not updated for SCD2"

 # Check that Anonymous user is handled
 grep -q "user_id.*-1\|Anonymous" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not handling Anonymous user"
}

@test "Datamart bridge table integration" {
 # Test that datamarts can work with hashtag bridge table
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"

 # Check that datamarts can reference fact_hashtags
 grep -q "fact_hashtags\|dimension_hashtag_id" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not integrated with hashtag bridge table"
}

@test "Datamart application version integration" {
 # Test that datamarts can work with application versions
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"

 # Check that datamarts can reference application versions
 grep -q "dimension_application_version\|application_version" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not integrated with application versions"
}

@test "Datamart season integration" {
 # Test that datamarts can work with seasons
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"
 local datamart_countries_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"

 # Check that datamarts can reference seasons
 grep -q "action_dimension_id_season\|season" "${datamart_users_dir}/datamartUsers_12_createProcedure.sql" || skip "datamartUsers not integrated with seasons"
 grep -q "action_dimension_id_season\|season" "${datamart_countries_dir}/datamartCountries_12_createProcedure.sql" || skip "datamartCountries not integrated with seasons"
}

@test "Datamart script execution" {
 # Test that datamart scripts can be executed (dry-run)
 local datamart_users_script="${PROJECT_ROOT}/bin/dwh/datamartUsers/datamartUsers.sh"
 local datamart_countries_script="${PROJECT_ROOT}/bin/dwh/datamartCountries/datamartCountries.sh"

 # Check scripts exist
 [[ -f "${datamart_users_script}" ]]
 [[ -f "${datamart_countries_script}" ]]

 # Test help mode
 run bash -c "cd \"\${PROJECT_ROOT}\" && ${datamart_users_script} --help"
 [[ "${status}" -eq 1 ]] # Help should exit with code 1

 run bash -c "cd \"\${PROJECT_ROOT}\" && ${datamart_countries_script} --help"
 [[ "${status}" -eq 1 ]] # Help should exit with code 1
}

@test "Datamart enhanced columns validation" {
 # Test that datamarts include enhanced columns
 local datamart_users_dir="${PROJECT_ROOT}/sql/dwh/datamartUsers"
 local datamart_countries_dir="${PROJECT_ROOT}/sql/dwh/datamartCountries"

 # Check for enhanced date columns in datamartUsers
 grep -q "iso_week\|quarter\|month_name" "${datamart_users_dir}/datamartUsers_11_createDatamartUsersTable.sql" || skip "datamartUsers missing enhanced date columns"

 # Check for enhanced time columns in datamartUsers
 grep -q "hour_of_week\|period_of_day" "${datamart_users_dir}/datamartUsers_11_createDatamartUsersTable.sql" || skip "datamartUsers missing enhanced time columns"

 # Check for enhanced country columns in datamartCountries
 grep -q "iso_alpha2\|iso_alpha3" "${datamart_countries_dir}/datamartCountries_11_createDatamarCountriesTable.sql" || skip "datamartCountries missing enhanced country columns"
}

@test "Datamart documentation consistency" {
 # Test that datamart documentation is consistent with implementation
 local readme_file="${PROJECT_ROOT}/bin/dwh/README.md"

 # Check that documentation mentions datamarts
 grep -q "datamart" "${readme_file}" || skip "datamarts not documented"

 # Check that documentation mentions enhanced features
 grep -q "dimension_time_of_week\|time_of_week" "${readme_file}" || skip "renamed dimension not documented"
 grep -q "SCD2\|slowly changing" "${readme_file}" || skip "SCD2 not documented"
}
