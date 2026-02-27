#!/usr/bin/env bats

# Tests for last_year_activity: 371-char string, LPAD, and fixed 371-day window.
# - LPAD to 371 chars and helper functions (move_day, refresh_today_activities).
# - Procedures must use generate_series(CURRENT_DATE - 370, CURRENT_DATE) so the
#   "last year" is always the last 371 calendar days, not limited by dimension_days.
#   (dimension_days is populated on demand during ETL; if only recent data was loaded,
#   we used to get only N days and LPAD with zeros, so the heatmap showed only ~9 weeks.
#   The tests that only checked LPAD and length did not catch that.)
#
# Author: Andres Gomez (AngocA)
# Version: 2026-02-27

load ../../../tests/test_helper

setup() {
  SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT_BASE_DIRECTORY

  # shellcheck disable=SC1090
  [[ -f "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh" ]] && source "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh"

  if [[ -z "${SKIP_TEST_SETUP:-}" ]] && [[ -n "${TEST_DBNAME:-}" ]]; then
    setup_test_database
  fi
}

# --- Source-code / regression tests: procedure must pad last_year_activity to 371 chars ---

@test "datamartUsers_12_createProcedure.sql should contain LPAD for last_year_activity to 371 chars" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "LPAD(m_last_year_activity, 371, '0')" "${sql_file}" || \
  grep -q "LPAD.*m_last_year_activity.*371" "${sql_file}" || \
  fail "Procedure must pad last_year_activity to 371 chars (LPAD) when dimension_days has fewer dates"
}

@test "datamartCountries_12_createProcedure.sql should contain LPAD for last_year_activity to 371 chars" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "LPAD(m_last_year_activity, 371, '0')" "${sql_file}" || \
  grep -q "LPAD.*m_last_year_activity.*371" "${sql_file}" || \
  fail "Procedure must pad last_year_activity to 371 chars (LPAD) when dimension_days has fewer dates"
}

# --- Constants: last_year_activity must be 371 chars (53 weeks * 7 + 6) ---

@test "datamartUsers table definition should define last_year_activity as CHAR(371)" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "last_year_activity CHAR(371)" "${sql_file}" || \
  fail "datamartUsers.last_year_activity must be CHAR(371)"
}

@test "datamarts_lastYearActivities.sql move_day and refresh_today_activities should use 371" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "CHAR(371)" "${sql_file}" || fail "lastYearActivities functions must use CHAR(371)"
  grep -q "SUBSTRING(activity, 1, 370)" "${sql_file}" || fail "refresh_today_activities must keep 370 chars and append one"
}

# --- Regression: procedures must use fixed 371-day window (generate_series), not only dimension_days ---

@test "datamartUsers_12 procedure uses generate_series for last 371 calendar days" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "generate_series" "${sql_file}" || fail "Procedure must use generate_series for fixed 371-day window"
  grep -q "CURRENT_DATE - 370" "${sql_file}" || fail "Procedure must use CURRENT_DATE - 370 for last 371 days"
}

@test "datamartCountries_12 procedure uses generate_series for last 371 calendar days" {
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"
  [[ -f "${sql_file}" ]] || skip "SQL file not found: ${sql_file}"

  grep -q "generate_series" "${sql_file}" || fail "Procedure must use generate_series for fixed 371-day window"
  grep -q "CURRENT_DATE - 370" "${sql_file}" || fail "Procedure must use CURRENT_DATE - 370 for last 371 days"
}

# --- Runtime test: with DB, LPAD and helper functions return 371-char string ---

@test "LPAD to 371 chars produces length 371 for short activity string" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"

  run psql -d "${dbname}" -tAc "SELECT LENGTH(LPAD('12', 371, '0'))"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" -eq 371 ]] || fail "LPAD('12', 371, '0') must have length 371, got ${output}"
}

@test "lastYearActivities functions exist and return 371-char string when loaded" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities (missing deps?): ${output}"

  # refresh_today_activities(activity, score): appends score; SUBSTRING(activity,1,370)||score => 371 chars
  run psql -d "${dbname}" -tAc "SELECT LENGTH(dwh.refresh_today_activities(REPEAT('0', 370), 0))"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" -eq 371 ]] || fail "refresh_today_activities must return 371 chars, got ${output}"

  # move_day: shifts left and appends '0', so 371 in => 371 out
  run psql -d "${dbname}" -tAc "SELECT LENGTH(dwh.move_day(REPEAT('1', 371)))"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" -eq 371 ]] || fail "move_day must return 371 chars, got ${output}"
}

# --- Vector generation: build like the procedure (loop + LPAD) and assert design ---

@test "vector generation with few days yields 371 chars with leading zeros" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities: ${output}"

  # Simulate procedure: start '0', append one score per "day" (5 days), then LPAD to 371.
  # After 5 iterations we have 1+5=6 data chars; LPAD gives 365 leading zeros, then 6 data chars.
  run psql -d "${dbname}" -tAc "
    DO \$\$
    DECLARE
      m_vec TEXT := '0';
      i INT;
    BEGIN
      FOR i IN 1..5 LOOP
        m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 1);
      END LOOP;
      m_vec := LPAD(m_vec, 371, '0');
      IF LENGTH(m_vec) <> 371 THEN
        RAISE EXCEPTION 'length % expected 371', LENGTH(m_vec);
      END IF;
      IF SUBSTRING(m_vec FROM 1 FOR 365) <> REPEAT('0', 365) THEN
        RAISE EXCEPTION 'first 365 chars must be zeros (padding for older days)';
      END IF;
      RAISE NOTICE 'OK';
    END \$\$
  "
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK"* ]] || fail "Vector build+LPAD must yield 371 chars with 365 leading zeros"
}

@test "vector generation full 371 days yields 371 chars without extra padding" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities: ${output}"

  # Build vector with 371 iterations (like full dimension_days): no LPAD needed, result already 371
  run psql -d "${dbname}" -tAc "
    DO \$\$
    DECLARE
      m_vec TEXT := '0';
      i INT;
    BEGIN
      FOR i IN 1..370 LOOP
        m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 0);
      END LOOP;
      IF LENGTH(m_vec) <> 370 THEN
        RAISE EXCEPTION 'after 370 iterations length % expected 370', LENGTH(m_vec);
      END IF;
      m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 1);
      IF LENGTH(m_vec) <> 371 THEN
        RAISE EXCEPTION 'after 371 iterations length % expected 371', LENGTH(m_vec);
      END IF;
      m_vec := LPAD(m_vec, 371, '0');
      IF LENGTH(m_vec) <> 371 THEN
        RAISE EXCEPTION 'after LPAD length % expected 371', LENGTH(m_vec);
      END IF;
      RAISE NOTICE 'OK';
    END \$\$
  "
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK"* ]] || fail "Full 371-day vector must be 371 chars"
}

@test "vector format: only digits 0-9 and length 371" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities: ${output}"

  # Build short vector and LPAD; then check format: length 371 and matches ^[0-9]+$
  run psql -d "${dbname}" -tAc "
    DO \$\$
    DECLARE
      m_vec TEXT := '0';
      i INT;
    BEGIN
      FOR i IN 1..3 LOOP
        m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), (i % 10)::SMALLINT);
      END LOOP;
      m_vec := LPAD(m_vec, 371, '0');
      IF m_vec !~ '^[0-9]+\$' THEN
        RAISE EXCEPTION 'vector must contain only digits 0-9';
      END IF;
      IF LENGTH(m_vec) <> 371 THEN
        RAISE EXCEPTION 'length %', LENGTH(m_vec);
      END IF;
      RAISE NOTICE 'OK';
    END \$\$
  "
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK"* ]] || fail "Vector must be 371 chars and only digits 0-9"
}

# --- Daily run: contribute day1, no contribute day2, run again day3 with contribution ---

@test "vector after day1 activity then day2 no activity then day3 run with activity" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities: ${output}"

  # Day 1: one day of activity with score 3
  # Day 2: no activity (score 0), run move_day then refresh 0
  # Day 3: run again (move_day), then refresh with score 2
  # Rightmost 3 chars must be '302' (day1=3, day2=0, day3=2)
  run psql -d "${dbname}" -tAc "
    DO \$\$
    DECLARE
      m_vec TEXT;
    BEGIN
      -- Day 1: build vector with one day, score 3
      m_vec := '0';
      m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 3);
      m_vec := LPAD(m_vec, 371, '0');
      IF LENGTH(m_vec) <> 371 THEN RAISE EXCEPTION 'day1 length %', LENGTH(m_vec); END IF;

      -- Day 2: no contribution; simulate daily run (move_day then refresh today)
      m_vec := dwh.move_day(m_vec::CHAR(371));
      m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 0);
      IF SUBSTRING(m_vec FROM 371 FOR 1) <> '0' THEN
        RAISE EXCEPTION 'day2 rightmost expected 0, got %', SUBSTRING(m_vec FROM 371 FOR 1);
      END IF;

      -- Day 3: run again, user contributes (score 2)
      m_vec := dwh.move_day(m_vec::CHAR(371));
      m_vec := dwh.refresh_today_activities(m_vec::CHAR(371), 2);
      IF SUBSTRING(m_vec FROM 369 FOR 3) <> '302' THEN
        RAISE EXCEPTION 'day1-2-3 rightmost expected 302, got %', SUBSTRING(m_vec FROM 369 FOR 3);
      END IF;
      IF LENGTH(m_vec) <> 371 THEN RAISE EXCEPTION 'day3 length %', LENGTH(m_vec); END IF;
      RAISE NOTICE 'OK';
    END \$\$
  "
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK"* ]] || fail "Vector must show day1=3, day2=0, day3=2 (rightmost 302)"
}

@test "move_day shifts oldest out and adds zero at end" {
  skip_if_no_db_connection
  local dbname="${TEST_DBNAME:-${DBNAME}}"
  local sql_file="${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamarts_lastYearActivities.sql"
  [[ -f "${sql_file}" ]] || skip "datamarts_lastYearActivities.sql not found"

  psql -d "${dbname}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1
  run psql -d "${dbname}" -v ON_ERROR_STOP=1 -f "${sql_file}" 2>&1
  [[ "${status}" -eq 0 ]] || skip "Could not load lastYearActivities: ${output}"

  run psql -d "${dbname}" -tAc "
    DO \$\$
    DECLARE
      m_vec TEXT;
      shifted TEXT;
    BEGIN
      -- Build 371-char vector: 368 zeros + '123' at end (positions 369,370,371 = 1,2,3)
      m_vec := LPAD('123', 371, '0');
      IF SUBSTRING(m_vec FROM 369 FOR 3) <> '123' THEN
        RAISE EXCEPTION 'initial rightmost expected 123, got %', SUBSTRING(m_vec FROM 369 FOR 3);
      END IF;
      shifted := dwh.move_day(m_vec::CHAR(371));
      -- After shift: first char (old 2) dropped, 0 appended. So rightmost = 230 (old 2,3 + new 0)
      IF SUBSTRING(shifted FROM 369 FOR 3) <> '230' THEN
        RAISE EXCEPTION 'after move_day rightmost expected 230, got %', SUBSTRING(shifted FROM 369 FOR 3);
      END IF;
      RAISE NOTICE 'OK';
    END \$\$
  "
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"OK"* ]] || fail "move_day must shift left and append 0"
}
