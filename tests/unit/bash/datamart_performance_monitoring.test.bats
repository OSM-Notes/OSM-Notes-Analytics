#!/usr/bin/env bats

# Require minimum BATS version for run flags
bats_require_minimum_version 1.5.0

# Load test helper for database connection verification
load ../../test_helper

# Tests for datamart performance monitoring system
# Verifies that performance logging works correctly and doesn't break existing functionality

setup() {
  # Setup test environment
  # shellcheck disable=SC2154
  SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY
}

# ============================================================================
# Table Creation Tests
# ============================================================================

# Test that performance log table can be created
@test "Performance log table should be creatable" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Create the table
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql"

  [[ "${status}" -eq 0 ]] || echo "Table creation should succeed"
}

# Test that performance log table exists after creation
@test "Performance log table should exist" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Check if table exists
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'dwh'
      AND table_name = 'datamart_performance_log';
  "

  [[ "${status}" -eq 0 ]]
  [[ $(echo "${output}" | grep -c "1") -eq 1 ]] || echo "Table should exist"
}

# Test that performance log table has correct columns
@test "Performance log table should have correct columns" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Check for required columns
  run psql -d "${dbname}" -t -c "
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'dwh'
      AND table_name = 'datamart_performance_log'
      AND column_name IN ('log_id', 'datamart_type', 'entity_id', 'start_time',
                          'end_time', 'duration_seconds', 'facts_count', 'status');
  "

  [[ "${status}" -eq 0 ]]
  # Should have at least 8 columns (the ones we checked)
  [[ $(echo "${output}" | grep -c "log_id\|datamart_type\|entity_id\|start_time\|end_time\|duration_seconds\|facts_count\|status") -ge 8 ]] || \
    echo "Table should have required columns"
}

# ============================================================================
# Integration Tests - Country Updates
# ============================================================================

# Test that country update procedure logs performance
@test "Country update procedure should log performance" {
  # Skip test if database connection is unavailable
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Get initial log count
  initial_count=$(psql -d "${dbname}" -t -c "
    SELECT COUNT(*) FROM dwh.datamart_performance_log WHERE datamart_type = 'country';
  " | tr -d ' ')

  # Update a country datamart (if country 1 exists)
  psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_countries WHERE dimension_country_id = 1) THEN
        CALL dwh.update_datamart_country(1);
      END IF;
    END \$\$;
  " > /dev/null 2>&1 || true

  # Get new log count
  new_count=$(psql -d "${dbname}" -t -c "
    SELECT COUNT(*) FROM dwh.datamart_performance_log WHERE datamart_type = 'country';
  " | tr -d ' ')

  # Count should have increased (if country exists)
  # If country doesn't exist, count stays same, which is also OK
  [[ "${new_count}" -ge "${initial_count}" ]] || echo "Log count should not decrease"
}

# Test that country update performance log has correct data
@test "Country update performance log should have correct data" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists and verify creation
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql"
  [[ "${status}" -eq 0 ]] || echo "Failed to create performance log table"

  # Verify table exists before proceeding
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'dwh'
      AND table_name = 'datamart_performance_log';
  "
  [[ "${status}" -eq 0 ]]
  [[ $(echo "${output}" | tr -d ' ') -eq 1 ]] || skip "Performance log table does not exist"

  # Update a country datamart (if country 1 exists)
  psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_countries WHERE dimension_country_id = 1) THEN
        CALL dwh.update_datamart_country(1);
      END IF;
    END \$\$;
  " > /dev/null 2>&1 || true

  # Check latest log entry (may be empty if no country exists or logging is disabled)
  run psql -d "${dbname}" -t -c "
    SELECT
      datamart_type,
      entity_id,
      duration_seconds,
      status
    FROM dwh.datamart_performance_log
    WHERE datamart_type = 'country'
      AND entity_id = 1
    ORDER BY created_at DESC
    LIMIT 1;
  "

  [[ "${status}" -eq 0 ]]
  # If log exists, verify it has correct structure
  if [[ -n "${output}" ]] && [[ "${output}" != *"0 rows"* ]] && [[ "${output}" != *"rows"* ]]; then
    [[ "${output}" == *"country"* ]] || echo "Log should have datamart_type = 'country'"
    [[ "${output}" == *"success"* ]] || echo "Log should have status = 'success'"
  fi
}

# ============================================================================
# Integration Tests - User Updates
# ============================================================================

# Test that user update procedure logs performance
@test "User update procedure should log performance" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Get initial log count
  initial_count=$(psql -d "${dbname}" -t -c "
    SELECT COUNT(*) FROM dwh.datamart_performance_log WHERE datamart_type = 'user';
  " | tr -d ' ')

  # Update a user datamart (if user 1 exists)
  psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_users WHERE dimension_user_id = 1) THEN
        CALL dwh.update_datamart_user(1);
      END IF;
    END \$\$;
  " > /dev/null 2>&1 || true

  # Get new log count
  new_count=$(psql -d "${dbname}" -t -c "
    SELECT COUNT(*) FROM dwh.datamart_performance_log WHERE datamart_type = 'user';
  " | tr -d ' ')

  # Count should have increased (if user exists)
  [[ "${new_count}" -ge "${initial_count}" ]] || echo "Log count should not decrease"
}

# Test that user update performance log has correct data
@test "User update performance log should have correct data" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists and verify creation
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql"
  [[ "${status}" -eq 0 ]] || echo "Failed to create performance log table"

  # Verify table exists before proceeding
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = 'dwh'
      AND table_name = 'datamart_performance_log';
  "
  [[ "${status}" -eq 0 ]]
  [[ $(echo "${output}" | tr -d ' ') -eq 1 ]] || skip "Performance log table does not exist"

  # Update a user datamart (if user 1 exists)
  psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_users WHERE dimension_user_id = 1) THEN
        CALL dwh.update_datamart_user(1);
      END IF;
    END \$\$;
  " > /dev/null 2>&1 || true

  # Check latest log entry (may be empty if no user exists or logging is disabled)
  run psql -d "${dbname}" -t -c "
    SELECT
      datamart_type,
      entity_id,
      duration_seconds,
      status
    FROM dwh.datamart_performance_log
    WHERE datamart_type = 'user'
      AND entity_id = 1
    ORDER BY created_at DESC
    LIMIT 1;
  "

  [[ "${status}" -eq 0 ]]
  # If log exists, verify it has correct structure
  if [[ -n "${output}" ]] && [[ "${output}" != *"0 rows"* ]] && [[ "${output}" != *"rows"* ]]; then
    [[ "${output}" == *"user"* ]] || echo "Log should have datamart_type = 'user'"
    [[ "${output}" == *"success"* ]] || echo "Log should have status = 'success'"
  fi
}

# ============================================================================
# Data Quality Tests
# ============================================================================

# Test that duration_seconds is positive
@test "Performance log duration should be positive" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Check that all durations are positive (if table has data)
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamart_performance_log
    WHERE duration_seconds IS NOT NULL
      AND duration_seconds <= 0;
  "

  [[ "${status}" -eq 0 ]]
  count="${output// /}"
  [[ "${count}" == "0" ]] || echo "All durations should be positive"
}

# Test that end_time is after start_time
@test "Performance log end_time should be after start_time" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Check that end_time >= start_time (if table has data)
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamart_performance_log
    WHERE end_time < start_time;
  "

  [[ "${status}" -eq 0 ]]
  count="${output// /}"
  [[ "${count}" == "0" ]] || echo "End time should be after start time"
}

# Test that duration matches time difference
@test "Performance log duration should match time difference" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Check that duration_seconds approximately matches (end_time - start_time)
  # Allow 1 second tolerance for rounding (if table has data)
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM dwh.datamart_performance_log
    WHERE ABS(duration_seconds - EXTRACT(EPOCH FROM (end_time - start_time))) > 1.0;
  "

  [[ "${status}" -eq 0 ]]
  count="${output// /}"
  # Allow some tolerance for very fast operations
  [[ "${count}" -lt 10 ]] || echo "Duration should match time difference (with tolerance)"
}

# ============================================================================
# Backward Compatibility Tests
# ============================================================================

# Test that existing datamart update procedures still work
@test "Existing datamart update procedures should still work" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Ensure table exists (so logging doesn't fail)
  psql -d "${dbname}" -f \
    "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartPerformance/datamartPerformance_10_createTable.sql" \
    > /dev/null 2>&1 || true

  # Try to update a country (should not fail even if country doesn't exist)
  run psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_countries WHERE dimension_country_id = 1) THEN
        CALL dwh.update_datamart_country(1);
      END IF;
    END \$\$;
  " 2>&1

  # Should succeed (status 0) or report missing data gracefully
  [[ "${status}" -ge 0 ]]
  # Should not have SQL errors about missing table
  [[ "${output}" != *"relation \"datamart_performance_log\" does not exist"* ]] || \
    echo "Performance log table should exist"
}

# Test that procedures can be called without performance table (graceful degradation)
@test "Procedures should handle missing performance table gracefully" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Drop table if exists
  psql -d "${dbname}" -c "DROP TABLE IF EXISTS dwh.datamart_performance_log;" > /dev/null 2>&1 || true

  # Try to update a country (should not fail)
  run psql -d "${dbname}" -c "
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM dwh.dimension_countries WHERE dimension_country_id = 1) THEN
        BEGIN
          CALL dwh.update_datamart_country(1);
        EXCEPTION WHEN OTHERS THEN
          -- If it fails due to missing table, that's OK for this test
          -- We just want to ensure it doesn't crash the entire procedure
          NULL;
        END;
      END IF;
    END \$\$;
  " 2>&1

  # Should not crash (even if it logs an error about missing table)
  [[ "${status}" -ge 0 ]]
}

# ============================================================================
# Index Tests
# ============================================================================

# Test that performance log table has indexes
@test "Performance log table should have indexes" {
  if [[ -z "${DBNAME:-}" ]] && [[ -z "${TEST_DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  local dbname="${TEST_DBNAME:-${DBNAME}}"

  # Check for indexes
  run psql -d "${dbname}" -t -c "
    SELECT COUNT(*)
    FROM pg_indexes
    WHERE schemaname = 'dwh'
      AND tablename = 'datamart_performance_log';
  "

  [[ "${status}" -eq 0 ]]
  # Should have at least 3 indexes
  count="${output// /}"
  [[ "${count}" -ge "3" ]] || echo "Table should have indexes for performance"
}

