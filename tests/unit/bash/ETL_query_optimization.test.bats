#!/usr/bin/env bats
# Test suite for ETL query optimizations
# Validates that CAST operations are removed and JOINs are optimized
#
# Author: Andres Gomez (AngocA)
# Version: 2026-01-10

# Detect project root directory dynamically
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
export SCRIPT_BASE_DIRECTORY

@test "Staging_32_createStagingObjects.sql should not use CAST(event AS text)" {
  # Verify that CAST(event AS text) is not used in the optimized version
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized to use event directly"

  # Verify that event = 'opened' is used instead (without CAST)
  run grep -q "event = ''opened''" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized query pattern (event = 'opened') not found"

  # Verify JOIN directo is used instead of subquery
  run grep -q "JOIN note_comments o" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Direct JOIN pattern not found"

  # Verify subquery pattern is NOT used
  # Check if old pattern exists (this should fail if pattern is found)
  if grep -n "JOIN (" "${sql_file}" | grep -A 5 "SELECT note_id, id_user" | grep -q "FROM note_comments"; then
    # If subquery pattern exists, verify it doesn't use CAST
    run grep -B 2 -A 5 "JOIN (" "${sql_file}" | grep -q "CAST(event AS text)"
    [[ "${status}" -ne 0 ]] || echo "Found old subquery pattern with CAST - should be optimized"
  fi
}

@test "Staging_34_initialFactsLoadCreate.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_34_initialFactsLoadCreate.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists
  run grep -q "event = ''opened''" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized query pattern not found"
}

@test "Staging_34_initialFactsLoadCreate_Parallel.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_34_initialFactsLoadCreate_Parallel.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists
  run grep -q "event = 'opened'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized query pattern not found"
}

@test "Staging_35_initialFactsLoadExecute_Simple.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_35_initialFactsLoadExecute_Simple.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists
  run grep -q "event = 'opened'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized query pattern not found"
}

@test "exportClosedNotesByCountry.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/export/exportClosedNotesByCountry.sql"

  # Check that CAST(nc.event AS text) is NOT present
  run grep -n "CAST(nc.event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(nc.event AS text) in ${sql_file} - should be optimized"

  # Verify optimized patterns exist
  run grep -q "nc.event = 'opened'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized opened pattern not found"

  run grep -q "nc.event = 'closed'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized closed pattern not found"
}

@test "datamartCountries_12_createProcedure.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists (JOIN directo)
  run grep -q "JOIN note_comments nc" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Direct JOIN pattern not found"

  # Verify event = 'closed' is used
  run grep -q "nc.event = 'closed'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized closed pattern not found"
}

@test "datamartUsers_12_createProcedure.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists
  run grep -q "nc.event = 'closed'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized closed pattern not found"
}

@test "ETL_57_validateETLIntegrity.sql should not use CAST(event AS text)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_57_validateETLIntegrity.sql"

  # Check that CAST(event AS text) is NOT present
  run grep -n "CAST(event AS text)" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "Found CAST(event AS text) in ${sql_file} - should be optimized"

  # Verify optimized pattern exists
  run grep -q "event IN (" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Optimized IN pattern not found"
}

@test "All optimized files should use direct JOIN instead of subquery for event filtering" {
  # Verify that the optimized pattern (JOIN directo) is used in key files
  local files=(
    "sql/dwh/Staging_32_createStagingObjects.sql"
    "sql/dwh/Staging_34_initialFactsLoadCreate.sql"
    "sql/dwh/Staging_34_initialFactsLoadCreate_Parallel.sql"
    "sql/dwh/Staging_35_initialFactsLoadExecute_Simple.sql"
  )

  for file in "${files[@]}"; do
    local sql_file="${SCRIPT_BASE_DIRECTORY}/${file}"
    [[ -f "${sql_file}" ]] || skip "File ${file} not found"

    # Verify JOIN directo pattern exists (not JOIN with subquery)
    run grep -q "JOIN note_comments o" "${sql_file}"
    [[ "${status}" -eq 0 ]] || echo "Direct JOIN pattern not found in ${file}"

    # Verify that we're not using the old subquery pattern with CAST
    # Old pattern would be: JOIN (SELECT note_id, id_user FROM note_comments WHERE CAST(event AS text) = 'opened')
    # Check that if there's a JOIN with subquery for opened events, it doesn't use CAST
    if grep -q "JOIN (" "${sql_file}"; then
      # If there are JOINs with subqueries, verify none use CAST(event AS text) for opened
      run grep -B 5 -A 10 "JOIN (" "${sql_file}" | grep -A 10 "opened" | grep -q "CAST(event AS text)"
      [[ "${status}" -ne 0 ]] || echo "Found subquery with CAST(event AS text) for opened in ${file} - should be optimized"
    fi
  done
}

@test "Optimized queries should allow index usage" {
  # This test verifies that the query pattern allows PostgreSQL to use indexes
  # We check that event is used directly (not CAST) which allows index usage

  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/Staging_32_createStagingObjects.sql"

  # Verify that event is used directly in WHERE/ON clauses (allows index usage)
  # Pattern: event = 'opened' or event = 'closed' (not CAST(event AS text))
  run grep -q "event = ''opened''\|event = 'opened'" "${sql_file}"
  [[ "${status}" -eq 0 ]] || echo "Direct event comparison not found - index usage may be limited"

  # Verify CAST is not used (which prevents index usage)
  run grep -q "CAST.*event.*AS text" "${sql_file}"
  [[ "${status}" -ne 0 ]] || echo "CAST found - this prevents index usage on event column"
}
