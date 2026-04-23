#!/usr/bin/env bats

# Unit tests for DWH schema contract helpers (etc/schema_compatibility.sh).
# Author: Andres Gomez (AngocA)
# Version: 2026-04-22

load ../../test_helper

@test "etc/schema_compatibility.sh should export DWH contract defaults for api" {
 run bash -c "
  source \"${SCRIPT_BASE_DIRECTORY}/etc/schema_compatibility.sh\"
  __set_dwh_schema_contract_range api
  printf '%s %s %s' \"\${SCHEMA_DWH_COMPONENT}\" \"\${EXPECTED_DWH_SCHEMA_MIN}\" \"\${EXPECTED_DWH_SCHEMA_MAX}\"
 "
 [[ "${status}" -eq 0 ]]
 [[ "${output}" == "dwh 1.0.0 1.0.x" ]]
}

@test "__compare_semver should order patch versions" {
 run bash -c "
  source \"${SCRIPT_BASE_DIRECTORY}/etc/schema_compatibility.sh\"
  __compare_semver 1.0.1 1.0.0
 "
 [[ "${status}" -eq 0 ]]
 [[ "${output}" == "1" ]]
}

@test "ensure_dwh_schema_version.sql should exist and reference dwh component" {
 [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ensure_dwh_schema_version.sql" ]]
 run grep -q "VALUES ('dwh'" "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ensure_dwh_schema_version.sql"
 [[ "${status}" -eq 0 ]]
}
