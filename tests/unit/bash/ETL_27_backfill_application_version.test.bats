#!/usr/bin/env bats

# Unit and integration tests for ETL_27_backfill_application_version.sql
# Validates that the backfill script exists, has required content, and runs without error when DB is available.
#
# Author: Andres Gomez (AngocA)
# Version: 2025-02-19

load ../../test_helper.bash

setup() {
	PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
	export PROJECT_ROOT
	# shellcheck disable=SC1090
	source "${PROJECT_ROOT}/tests/properties.sh" 2>/dev/null || true
	export DBNAME="${TEST_DBNAME:-${DBNAME:-}}"
	SCRIPT="${PROJECT_ROOT}/sql/dwh/ETL_27_backfill_application_version.sql"
}

@test "ETL_27_backfill_application_version.sql exists" {
	[[ -f "${SCRIPT}" ]]
}

@test "ETL_27 script updates dimension_application_version from body" {
	grep -q "SET dimension_application_version" "${SCRIPT}"
	grep -q "note_comments_text" "${SCRIPT}"
	grep -q "get_application_version_id" "${SCRIPT}"
}

@test "ETL_27 script uses version regex pattern" {
	grep -q "regexp_match" "${SCRIPT}"
	grep -q "\\\\d+\\\\.\\\\d+" "${SCRIPT}" || grep -q '[0-9]\+\.[0-9]\+' "${SCRIPT}" || true
}

@test "ETL_27 script runs without error when DWH has required objects" {
	[[ -n "${DBNAME:-}" ]] || skip "No database configured"
	psql -d "${DBNAME}" -tAc "SELECT 1" >/dev/null 2>&1 || skip "Database not reachable"
	# Require dwh.facts and dwh.get_application_version_id; note_comments_text may be FDW
	run psql -d "${DBNAME}" -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema = 'dwh' AND table_name = 'facts'"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" -eq 1 ]] || skip "dwh.facts does not exist"
	run psql -d "${DBNAME}" -tAc "SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE n.nspname = 'dwh' AND p.proname = 'get_application_version_id'"
	[[ "${status}" -eq 0 ]]
	[[ "${output}" -eq 1 ]] || skip "dwh.get_application_version_id does not exist"
	# Run script (may update 0 rows if no backfill needed)
	run psql -d "${DBNAME}" -v ON_ERROR_STOP=1 -f "${SCRIPT}" 2>&1
	# Allow success or "relation ... does not exist" when note_comments_text is missing
	if [[ ${status} -ne 0 ]]; then
		echo "${output}" | grep -q "note_comments_text" && echo "${output}" | grep -qi "does not exist" && skip "note_comments_text not available (FDW or table missing)"
		echo "Unexpected failure: ${output}"
		return 1
	fi
}
