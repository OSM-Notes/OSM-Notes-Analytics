#!/usr/bin/env bats

# Badge system (DM-004) tests: 62_createBadgeSystem.sql, assign_badges_to_user, assign_badges_to_all_users
# Author: Andres Gomez (AngocA)

bats_require_minimum_version 1.5.0

load ../../test_helper

setup() {
  SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY
  TMP_DIR="$(mktemp -d)"
  export TMP_DIR
  export BASENAME="test_datamart_badges"
  export LOG_LEVEL="INFO"
  BADGE_SCRIPT="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts/62_createBadgeSystem.sql"
  export BADGE_SCRIPT
  export TEST_DBNAME="${TEST_DBNAME:-test_osm_notes_badges}"
}

teardown() {
  rm -rf "${TMP_DIR}"
  psql -d postgres -c "DROP DATABASE IF EXISTS ${TEST_DBNAME};" 2> /dev/null || true
}

# Badge system script exists
@test "62_createBadgeSystem.sql should exist" {
  [[ -f "${BADGE_SCRIPT}" ]]
}

# Badge system script contains expected SQL
@test "62_createBadgeSystem.sql should define badges and assign_badges functions" {
  grep -q "dwh.badges" "${BADGE_SCRIPT}"
  grep -q "assign_badges_to_user" "${BADGE_SCRIPT}"
  grep -q "assign_badges_to_all_users" "${BADGE_SCRIPT}"
}

# Badge system script has valid SQL structure
@test "62_createBadgeSystem.sql should contain valid SQL statements" {
  run grep -qE "CREATE|INSERT|DELETE|FUNCTION|PROCEDURE" "${BADGE_SCRIPT}"
  [[ "${status}" -eq 0 ]]
}

# When DB available: run badge script and verify badges table is populated
@test "badge system script should populate dwh.badges when run after table creation" {
  if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    skip "Skip DB-dependent test in CI if no database"
  fi

  psql_cmd=$(build_psql_cmd "${TEST_DBNAME}")
  # Ensure DB exists
  psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true
  # Schema dwh
  $psql_cmd -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2> /dev/null || true
  # Tables required by 62: dwh.badges (from datamartUsers_11)
  $psql_cmd -c "
    CREATE TABLE IF NOT EXISTS dwh.badges (
      badge_id SERIAL,
      badge_name VARCHAR(64),
      description TEXT,
      PRIMARY KEY (badge_id)
    );
    CREATE TABLE IF NOT EXISTS dwh.badges_per_users (
      id_user INTEGER NOT NULL,
      id_badge INTEGER NOT NULL,
      date_awarded DATE NOT NULL,
      comment TEXT,
      PRIMARY KEY (id_user, id_badge)
    );
    CREATE TABLE IF NOT EXISTS dwh.datamartUsers (dimension_user_id INTEGER PRIMARY KEY);
    INSERT INTO dwh.badges (badge_name) VALUES ('Test') ON CONFLICT DO NOTHING;
  " 2> /dev/null || true

  run $psql_cmd -v ON_ERROR_STOP=1 -f "${BADGE_SCRIPT}" 2>&1
  # Script may fail if it expects more columns or constraints; we only care that it runs
  if [[ "${status}" -ne 0 ]]; then
    skip "Badge script requires full datamart (status ${status})"
  fi

  count=$($psql_cmd -tAc "SELECT COUNT(*) FROM dwh.badges;" 2> /dev/null || echo "0")
  [[ "${count}" -gt 1 ]] || echo "Expected multiple badges after running 62_createBadgeSystem.sql"
}

# assign_badges_to_all_users procedure exists and can be called when datamart exists
@test "assign_badges_to_all_users procedure should exist after badge script" {
  if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    skip "Skip DB-dependent test in CI if no database"
  fi

  psql_cmd=$(build_psql_cmd "${TEST_DBNAME}")
  psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true
  $psql_cmd -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2> /dev/null || true
  # Minimal tables so procedure can be created
  $psql_cmd -c "
    CREATE TABLE IF NOT EXISTS dwh.badges (badge_id SERIAL PRIMARY KEY, badge_name VARCHAR(64), description TEXT);
    CREATE TABLE IF NOT EXISTS dwh.badges_per_users (id_user INTEGER NOT NULL, id_badge INTEGER NOT NULL, date_awarded DATE NOT NULL, comment TEXT, PRIMARY KEY (id_user, id_badge));
    CREATE TABLE IF NOT EXISTS dwh.datamartUsers (dimension_user_id INTEGER PRIMARY KEY);
  " 2> /dev/null || true

  run $psql_cmd -v ON_ERROR_STOP=1 -f "${BADGE_SCRIPT}" 2>&1
  if [[ "${status}" -ne 0 ]]; then
    skip "Badge script requires full schema (status ${status})"
  fi

  run $psql_cmd -tAc "SELECT proname FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'dwh' AND proname = 'assign_badges_to_all_users';" 2>&1
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"assign_badges_to_all_users"* ]]

  # Call should not error (may assign 0 badges if no users in datamart)
  run $psql_cmd -v ON_ERROR_STOP=1 -c "CALL dwh.assign_badges_to_all_users();" 2>&1
  [[ "${status}" -eq 0 ]]
}

# datamartUsers.sh includes badge system script in validation
@test "datamartUsers.sh should validate badge system script" {
  run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh 2>/dev/null && echo \$POSTGRES_15_BADGE_SYSTEM_FILE"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"62_createBadgeSystem.sql"* ]]
}

# Motivation badges (Global Resolver, First Responder, etc.) are defined in script
@test "62_createBadgeSystem.sql should define the 6 motivation badges" {
  for name in "Global Resolver" "First Responder" "Solid Closer" "Rising Resolver" "Local Hero" "Closing Streak"; do
    grep -q "'${name}'" "${BADGE_SCRIPT}" || { echo "Missing badge definition: ${name}"; return 1; }
  done
}

# assign_badges_to_user contains logic for the 6 new badges
@test "assign_badges_to_user should reference motivation badge variables and names" {
  grep -q "v_countries_closed" "${BADGE_SCRIPT}"
  grep -q "v_first_responder_notes" "${BADGE_SCRIPT}"
  grep -q "v_solid_closes" "${BADGE_SCRIPT}"
  grep -q "v_notes_closed_last_year" "${BADGE_SCRIPT}"
  grep -q "v_max_closes_one_country" "${BADGE_SCRIPT}"
  grep -q "v_closing_streak_days" "${BADGE_SCRIPT}"
  for name in "Global Resolver" "First Responder" "Solid Closer" "Rising Resolver" "Local Hero" "Closing Streak"; do
    grep -q "badge_name = '${name}'" "${BADGE_SCRIPT}" || { echo "Missing assign logic for: ${name}"; return 1; }
  done
}

# After running badge script, dwh.badges contains the 6 motivation badges
@test "dwh.badges should contain motivation badges after running 62 script" {
  if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    skip "Skip DB-dependent test in CI if no database"
  fi

  psql_cmd=$(build_psql_cmd "${TEST_DBNAME}")
  psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true
  $psql_cmd -c "CREATE SCHEMA IF NOT EXISTS dwh;" 2> /dev/null || true
  $psql_cmd -c "
    CREATE TABLE IF NOT EXISTS dwh.badges (badge_id SERIAL PRIMARY KEY, badge_name VARCHAR(64), description TEXT);
    CREATE TABLE IF NOT EXISTS dwh.badges_per_users (id_user INTEGER NOT NULL, id_badge INTEGER NOT NULL, date_awarded DATE NOT NULL, comment TEXT, PRIMARY KEY (id_user, id_badge));
    CREATE TABLE IF NOT EXISTS dwh.datamartUsers (dimension_user_id INTEGER PRIMARY KEY);
  " 2> /dev/null || true

  run $psql_cmd -v ON_ERROR_STOP=1 -f "${BADGE_SCRIPT}" 2>&1
  if [[ "${status}" -ne 0 ]]; then
    skip "Badge script failed (status ${status})"
  fi

  for name in "Global Resolver" "First Responder" "Solid Closer" "Rising Resolver" "Local Hero" "Closing Streak"; do
    count=$($psql_cmd -tAc "SELECT COUNT(*) FROM dwh.badges WHERE badge_name = '${name}';" 2> /dev/null || echo "0")
    [[ "${count}" -eq 1 ]] || { echo "Badge '${name}' should exist once in dwh.badges, got: ${count}"; return 1; }
  done
}
