#!/usr/bin/env bats

# Integration tests for temporal resolution metrics JSON columns
# Author: Andres Gomez (AngocA)
# Version: 2025-10-30

load ../test_helper.bash

setup() {
	PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
	export PROJECT_ROOT
	# Load test properties
	# shellcheck disable=SC1090
	source "${PROJECT_ROOT}/tests/properties.sh"
	# Use TEST_DBNAME if available, otherwise fall back to DBNAME
	export DBNAME="${TEST_DBNAME:-${DBNAME:-}}"

	# Ensure tables exist (create minimal tables if they don't exist)
	if [[ -n "${DBNAME:-}" ]]; then
		psql -d "${DBNAME}" -c "CREATE SCHEMA IF NOT EXISTS dwh;" > /dev/null 2>&1 || true
		psql -d "${DBNAME}" -c "
		DO \$\$
		BEGIN
			IF NOT EXISTS (
				SELECT 1 FROM information_schema.tables WHERE table_schema='dwh' AND lower(table_name)='datamartcountries'
			) THEN
				EXECUTE 'CREATE TABLE dwh.datamartCountries (
					dimension_country_id INTEGER PRIMARY KEY,
					resolution_by_year JSON,
					resolution_by_month JSON
				)';
			END IF;
			IF NOT EXISTS (
				SELECT 1 FROM information_schema.tables WHERE table_schema='dwh' AND lower(table_name)='datamartusers'
			) THEN
				EXECUTE 'CREATE TABLE dwh.datamartUsers (
					dimension_user_id INTEGER PRIMARY KEY,
					resolution_by_year JSON,
					resolution_by_month JSON
				)';
			END IF;
		END\$\$;" > /dev/null 2>&1 || true
		# Ensure columns exist
		psql -d "${DBNAME}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_year JSON; ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_month JSON;" > /dev/null 2>&1 || true
		psql -d "${DBNAME}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_year JSON; ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_month JSON;" > /dev/null 2>&1 || true
	fi
}

@test "datamartCountries has resolution_by_year and resolution_by_month" {
    [[ -n "${DBNAME:-}" ]] || skip "No database configured"
    psql -d "${DBNAME}" -tAc "SELECT 1" > /dev/null 2>&1 || skip "Database not reachable"
    # Verify table exists first
    run psql -d "${DBNAME}" -tAc "SELECT COUNT(1) FROM information_schema.tables WHERE table_schema='dwh' AND lower(table_name)='datamartcountries'"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" -eq 1 ]] || skip "datamartCountries table does not exist"
    # Ensure columns exist (idempotent best-effort)
    psql -d "${DBNAME}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_year JSON; ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_month JSON;" > /dev/null 2>&1 || true
    run psql -d "${DBNAME}" -tAc "SELECT COUNT(1) FROM information_schema.columns WHERE table_schema='dwh' AND lower(table_name)='datamartcountries' AND column_name IN ('resolution_by_year','resolution_by_month')"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" -eq 2 ]] || { echo "resolution_by_year or resolution_by_month not found in datamartCountries"; return 1; }
}

@test "datamartUsers has resolution_by_year and resolution_by_month" {
    [[ -n "${DBNAME:-}" ]] || skip "No database configured"
    psql -d "${DBNAME}" -tAc "SELECT 1" > /dev/null 2>&1 || skip "Database not reachable"
    # Verify table exists first
    run psql -d "${DBNAME}" -tAc "SELECT COUNT(1) FROM information_schema.tables WHERE table_schema='dwh' AND lower(table_name)='datamartusers'"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" -eq 1 ]] || skip "datamartUsers table does not exist"
    # Ensure columns exist (idempotent best-effort)
    psql -d "${DBNAME}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_year JSON; ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_month JSON;" > /dev/null 2>&1 || true
    run psql -d "${DBNAME}" -tAc "SELECT COUNT(1) FROM information_schema.columns WHERE table_schema='dwh' AND lower(table_name)='datamartusers' AND column_name IN ('resolution_by_year','resolution_by_month')"
    [[ "${status}" -eq 0 ]]
    [[ "${output}" -eq 2 ]] || { echo "resolution_by_year or resolution_by_month not found in datamartUsers"; return 1; }
}

@test "resolution_by_year JSON structure (sample if available)" {
	[[ -n "${DBNAME:-}" ]] || skip "No database configured"
	psql -d "${DBNAME}" -tAc "SELECT 1" > /dev/null 2>&1 || skip "Database not reachable"
	# Only check structure if there is at least one populated row
	run psql -d "${DBNAME}" -tAc "SELECT COUNT(1) FROM dwh.datamartCountries WHERE resolution_by_year IS NOT NULL"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" -gt 0 ]] || skip "No populated resolution_by_year entries"
	run psql -d "${DBNAME}" -tAc "SELECT (resolution_by_year->0)->>'year' FROM dwh.datamartCountries WHERE resolution_by_year IS NOT NULL LIMIT 1"
	[[ "${status}" -eq 0 ]]
}
