#!/usr/bin/env bash

# Minimal mock ETL to prepare local test DB with required schemas/tables and sample data
# Uses local peer authentication (no password). Target DB defaults to 'notes_dwh'.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DBNAME="${TEST_DBNAME:-${DBNAME:-notes_dwh}}"

# Configure PostgreSQL connection parameters from environment variables
# This allows the script to work in both local (peer auth) and CI/CD (password auth) environments
if [[ -n "${TEST_DBHOST:-}" ]]; then
 export PGHOST="${TEST_DBHOST}"
fi
if [[ -n "${TEST_DBPORT:-}" ]]; then
 export PGPORT="${TEST_DBPORT}"
fi
if [[ -n "${TEST_DBUSER:-}" ]]; then
 export PGUSER="${TEST_DBUSER}"
fi
if [[ -n "${TEST_DBPASSWORD:-}" ]]; then
 export PGPASSWORD="${TEST_DBPASSWORD}"
elif [[ -n "${TEST_DBHOST:-}" ]]; then
 # In CI/CD environment, default password is 'postgres' if not specified
 export PGPASSWORD="${PGPASSWORD:-postgres}"
fi

echo "[MOCK-ETL] Using database: ${DBNAME}"
if [[ -n "${PGHOST:-}" ]]; then
 echo "[MOCK-ETL] Connection: ${PGUSER:-$(whoami)}@${PGHOST}:${PGPORT:-5432}/${DBNAME}"
else
 echo "[MOCK-ETL] Connection: ${PGUSER:-$(whoami)}@localhost/${DBNAME}"
fi

# Verify database connection before proceeding
# Build psql command based on environment (CI/CD vs local)
if [[ -n "${TEST_DBHOST:-}" ]]; then
 # CI/CD environment - use explicit connection parameters
 echo "[MOCK-ETL] Verifying database connection (CI/CD mode)..."
 CONNECTION_OUTPUT=$(PGPASSWORD="${TEST_DBPASSWORD:-postgres}" psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT:-5432}" -U "${TEST_DBUSER:-postgres}" -d "${DBNAME}" -c "SELECT 1;" 2>&1)
 CONNECTION_EXIT_CODE=$?
 if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
  echo "[MOCK-ETL] ERROR: Cannot connect to database ${DBNAME}" >&2
  echo "[MOCK-ETL] Connection attempt failed with exit code: ${CONNECTION_EXIT_CODE}" >&2
  echo "[MOCK-ETL] Connection details:" >&2
  echo "[MOCK-ETL]   Host: ${TEST_DBHOST}" >&2
  echo "[MOCK-ETL]   Port: ${TEST_DBPORT:-5432}" >&2
  echo "[MOCK-ETL]   User: ${TEST_DBUSER:-postgres}" >&2
  echo "[MOCK-ETL]   Database: ${DBNAME}" >&2
  echo "[MOCK-ETL]   Password: ${TEST_DBPASSWORD:+***set***}" >&2
  echo "[MOCK-ETL] Error output:" >&2
  if [[ -n "${CONNECTION_OUTPUT}" ]]; then
   echo "${CONNECTION_OUTPUT}" | sed 's/^/[MOCK-ETL]   /' | while IFS= read -r line || [[ -n "${line}" ]]; do
    echo "${line}" >&2
   done
  fi
  exit 1
 fi
 echo "[MOCK-ETL] Database connection verified"
 psql_cmd=(psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT:-5432}" -U "${TEST_DBUSER:-postgres}" -d "${DBNAME}" -v ON_ERROR_STOP=1)
else
 # Local environment - use peer authentication
 echo "[MOCK-ETL] Verifying database connection (local mode)..."
 CONNECTION_OUTPUT=$(psql -d "${DBNAME}" -c "SELECT 1;" 2>&1)
 CONNECTION_EXIT_CODE=$?
 if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
  echo "[MOCK-ETL] ERROR: Cannot connect to database ${DBNAME}" >&2
  echo "[MOCK-ETL] Connection attempt failed with exit code: ${CONNECTION_EXIT_CODE}" >&2
  echo "[MOCK-ETL] Database: ${DBNAME}" >&2
  echo "[MOCK-ETL] Error output:" >&2
  if [[ -n "${CONNECTION_OUTPUT}" ]]; then
   echo "${CONNECTION_OUTPUT}" | sed 's/^/[MOCK-ETL]   /' | while IFS= read -r line || [[ -n "${line}" ]]; do
    echo "${line}" >&2
   done
  fi
  exit 1
 fi
 echo "[MOCK-ETL] Database connection verified"
 psql_cmd=(psql -d "${DBNAME}" -v ON_ERROR_STOP=1)
fi

echo "[MOCK-ETL] Ensuring enum type exists (mock scope only)..."
"${psql_cmd[@]}" << 'SQL'
DO $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'note_event_enum') THEN
  CREATE TYPE note_event_enum AS ENUM ('opened','closed','commented','reopened','hidden');
 END IF;
END
$$;
SQL

echo "[MOCK-ETL] Applying base DWH DDL (stripping enum CREATE and DO blocks for compatibility)..."
TMP_DDL="$(mktemp)"
awk '
  BEGIN {skip=0; skip1=0; skip_do=0}
  /^DO[[:space:]]+\$\$$/ {skip_do=1; next}
  skip_do && /^\$\$;/ {skip_do=0; next}
  skip_do {next}
  /CREATE[[:space:]]+TYPE[[:space:]]+(IF[[:space:]]+NOT[[:space:]]+EXISTS[[:space:]]+)?note_event_enum[[:space:]]+AS[[:space:]]+ENUM[[:space:]]*\(/ {skip=1; next}
  skip && /^\);/ {skip=0; next}
  skip {next}
  /COMMENT[[:space:]]+ON[[:space:]]+TYPE[[:space:]]+note_event_enum/ {skip1=1; next}
  skip1 {skip1=0; next}
  {print}
' "${PROJECT_ROOT}/sql/dwh/ETL_20_createDWHTables.sql" > "${TMP_DDL}"
# Execute SQL, ignoring errors about existing objects (tables may already exist from previous runs)
set +e
SQL_OUTPUT=$("${psql_cmd[@]}" -f "${TMP_DDL}" 2>&1)
SQL_EXIT_CODE=$?
set -e
if [[ ${SQL_EXIT_CODE} -ne 0 ]]; then
 # Filter out expected messages about existing objects (in English and Spanish)
 # Filter ERROR lines that contain "ya existe" or "already exists" - these are expected
 FILTERED_OUTPUT=$(echo "${SQL_OUTPUT}" | grep -vE "(already exists|NOTICE|ya existe|la relación|ERROR.*ya existe|ERROR.*already exists|psql:.*ERROR.*ya existe)" || true)
 # Also check if the error is specifically about existing objects
 # If filtered output is empty or only contains expected patterns, it's OK
 if [[ -n "${FILTERED_OUTPUT}" ]]; then
  # Check if remaining output contains actual errors (not just about existing objects)
  REAL_ERRORS=$(echo "${FILTERED_OUTPUT}" | grep -vE "(CREATE SCHEMA|COMMENT|^$)" | grep -E "^ERROR:" || true)
  if [[ -n "${REAL_ERRORS}" ]]; then
   echo "[MOCK-ETL] ERROR: Failed to apply base DWH DDL" >&2
   echo "[MOCK-ETL] Check the SQL file: ${PROJECT_ROOT}/sql/dwh/ETL_20_createDWHTables.sql" >&2
   echo "${FILTERED_OUTPUT}" >&2
   rm -f "${TMP_DDL}"
   exit 1
  fi
  # If no real errors, it was just expected warnings about existing objects - continue
 fi
 # If no filtered output, it was just expected warnings - continue
fi
rm -f "${TMP_DDL}"
HAS_PKS=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND constraint_name='pk_users_dim')" 2> /dev/null || echo "f")
HAS_FKS=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND constraint_name='fk_region')" 2> /dev/null || echo "f")

MODE="ALL"
if [[ "${HAS_PKS}" == "t" && "${HAS_FKS}" == "t" ]]; then
 MODE="NO_PK_FK"
elif [[ "${HAS_PKS}" == "t" ]]; then
 MODE="NO_PK"
fi

if [[ "${MODE}" == "ALL" ]]; then
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/ETL_23_addFunctions.sql"
else
 TMP_FUNCS_DDL="$(mktemp)"
 if [[ "${MODE}" == "NO_PK" ]]; then
  awk '
      BEGIN {skip=0; skipidx=0}
      /Creating primary keys/ {skip=1; next}
      skip && /Creating foreign keys/ {skip=0}
      skip {next}
      /^CREATE UNIQUE INDEX (dimension_country_id_uniq|dimension_day_id_uniq)/ {skipidx=1; next}
      skipidx && /;[[:space:]]*$/ {skipidx=0; next}
      skipidx {next}
      {print}
    ' "${PROJECT_ROOT}/sql/dwh/ETL_23_addFunctions.sql" > "${TMP_FUNCS_DDL}"
 else
  awk '
      BEGIN {skip=0; skip2=0; skipidx=0}
      /Creating primary keys/ {skip=1; next}
      skip && /Creating foreign keys/ {skip=0}
      skip {next}
      /Creating foreign keys/ {skip2=1; next}
      skip2 && /Creating indexes/ {skip2=0}
      skip2 {next}
      /^CREATE UNIQUE INDEX (dimension_country_id_uniq|dimension_day_id_uniq)/ {skipidx=1; next}
      skipidx && /;[[:space:]]*$/ {skipidx=0; next}
      skipidx {next}
      {print}
    ' "${PROJECT_ROOT}/sql/dwh/ETL_23_addFunctions.sql" > "${TMP_FUNCS_DDL}"
 fi
 "${psql_cmd[@]}" -f "${TMP_FUNCS_DDL}"
 rm -f "${TMP_FUNCS_DDL}"
fi
HAS_FACT_FK=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='facts' AND constraint_name='fk_country')" 2> /dev/null || echo "f")
HAS_FACT_IDX=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='dwh' AND indexname='facts_action_date')" 2> /dev/null || echo "f")
if [[ "${HAS_FACT_FK}" == "t" || "${HAS_FACT_IDX}" == "t" ]]; then
 TMP_41_DDL="$(mktemp)"
 awk -v skip_fk="${HAS_FACT_FK}" -v skip_idx="${HAS_FACT_IDX}" '
    BEGIN {s1=0; s2=0}
    /Creating foreign keys/ { if (skip_fk=="t") { s1=1; next } }
    s1 && /Creating indexes/ { s1=0 }
    s1 { next }
    /Creating indexes/ { if (skip_idx=="t") { s2=1; next } }
    s2 && /Creating triggers/ { s2=0; print "SELECT /* Notes-ETL */ clock_timestamp() AS Processing,"; print $0; next }
    /^SELECT .*Processing,/ { next }
    /Skipping primary key \(partitioned table\)/ { print "SELECT /* Notes-ETL */ clock_timestamp() AS Processing,"; print $0; next }
    s2 { next }
    { print }
  ' "${PROJECT_ROOT}/sql/dwh/ETL_40_addConstraintsIndexesTriggers.sql" > "${TMP_41_DDL}"
 "${psql_cmd[@]}" -f "${TMP_41_DDL}"
 rm -f "${TMP_41_DDL}"
else
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/ETL_40_addConstraintsIndexesTriggers.sql"
fi

echo "[MOCK-ETL] Creating datamart tables..."
# datamartCountries: create table first, then add new columns if needed
# datamartUsers: create table first, then add new columns if needed

# datamartCountries: create table, then add new columns before executing full script
HAS_PK_DC=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='datamartcountries' AND constraint_type='PRIMARY KEY')" 2> /dev/null || echo "f")
if [[ "${HAS_PK_DC}" == "t" ]]; then
 # Table exists: add new columns first, then execute script (which will skip CREATE TABLE)
 # Ensure all basic columns exist before executing COMMENT statements
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS iso_alpha2 VARCHAR(2);" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS iso_alpha3 VARCHAR(3);" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS dimension_continent_id INTEGER;" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS latest_open_note_id INTEGER;" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS latest_commented_note_id INTEGER;" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS latest_closed_note_id INTEGER;" 2> /dev/null || true
 "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS latest_reopened_note_id INTEGER;" 2> /dev/null || true
 TMP_DC12_DDL="$(mktemp)"
 awk '
   BEGIN {skip=0}
   /^ALTER TABLE dwh\.datamartCountries/ {skip=1; next}
   skip && /;[[:space:]]*$/ {skip=0; next}
   skip {next}
   {print}
 ' "${PROJECT_ROOT}/sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql" > "${TMP_DC12_DDL}"
 "${psql_cmd[@]}" -f "${TMP_DC12_DDL}"
 rm -f "${TMP_DC12_DDL}"
else
 # Table doesn't exist: create it with full script (includes new columns)
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql"
fi

# datamartUsers: create table, then add new columns before executing full script
HAS_PK_DU=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='datamartusers' AND constraint_type='PRIMARY KEY')" 2> /dev/null || echo "f")
HAS_PK_BADGES=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='badges' AND constraint_type='PRIMARY KEY')" 2> /dev/null || echo "f")
HAS_PK_BADGE_USERS=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='badges_per_users' AND constraint_type='PRIMARY KEY')" 2> /dev/null || echo "f")
HAS_PK_CONTR_TYPES=$("${psql_cmd[@]}" -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.table_constraints WHERE table_schema='dwh' AND table_name='contributor_types' AND constraint_type='PRIMARY KEY')" 2> /dev/null || echo "f")
if [[ "${HAS_PK_DU}" == "t" || "${HAS_PK_BADGES}" == "t" || "${HAS_PK_BADGE_USERS}" == "t" || "${HAS_PK_CONTR_TYPES}" == "t" ]]; then
 # Table exists: add new columns first, then execute script (which will skip CREATE TABLE)
 if [[ "${HAS_PK_DU}" == "t" ]]; then
  # Ensure all basic columns exist before executing COMMENT statements
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS iso_week SMALLINT;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS quarter SMALLINT;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS month_name VARCHAR(16);" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS hour_of_week SMALLINT;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS period_of_day VARCHAR(16);" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS latest_open_note_id INTEGER;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS latest_commented_note_id INTEGER;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS latest_closed_note_id INTEGER;" 2> /dev/null || true
  "${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS latest_reopened_note_id INTEGER;" 2> /dev/null || true
 fi
 TMP_DU12_DDL="$(mktemp)"
 awk -v pk_du="${HAS_PK_DU}" -v pk_b="${HAS_PK_BADGES}" -v pk_bu="${HAS_PK_BADGE_USERS}" -v pk_ct="${HAS_PK_CONTR_TYPES}" '
   BEGIN {skip=0}
   /^ALTER TABLE dwh\.datamartUsers/ { if (pk_du=="t") { skip=1; next } }
   /^ALTER TABLE dwh\.badges$/ { if (pk_b=="t") { skip=1; next } }
   /^ALTER TABLE dwh\.badges_per_users$/ { if (pk_bu=="t") { skip=1; next } }
   /^ALTER TABLE dwh\.contributor_types$/ { if (pk_ct=="t") { skip=1; next } }
   skip && /;[[:space:]]*$/ { skip=0; next }
   skip { next }
   { print }
 ' "${PROJECT_ROOT}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql" > "${TMP_DU12_DDL}"
 "${psql_cmd[@]}" -f "${TMP_DU12_DDL}"
 rm -f "${TMP_DU12_DDL}"
else
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql"
fi

# Ensure new temporal resolution JSON columns exist (idempotent)
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_year JSON;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS resolution_by_month JSON;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_year JSON;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS resolution_by_month JSON;"

# Ensure new ISO and continent columns exist in datamartCountries (idempotent)
# These must be added AFTER table creation but BEFORE procedure execution
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS iso_alpha2 VARCHAR(2);"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS iso_alpha3 VARCHAR(3);"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartCountries ADD COLUMN IF NOT EXISTS dimension_continent_id INTEGER;"

# Ensure new enhanced date/time columns exist in datamartUsers (idempotent)
# These must be added AFTER table creation but BEFORE procedure execution
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS iso_week SMALLINT;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS quarter SMALLINT;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS month_name VARCHAR(16);"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS hour_of_week SMALLINT;"
"${psql_cmd[@]}" -c "ALTER TABLE dwh.datamartUsers ADD COLUMN IF NOT EXISTS period_of_day VARCHAR(16);"

# Create global datamart if script exists (best effort)
if [[ -f "${PROJECT_ROOT}/sql/dwh/datamartGlobal/datamartGlobal_11_createTable.sql" ]]; then
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/datamartGlobal/datamartGlobal_11_createTable.sql" || true
fi

echo "[MOCK-ETL] Loading sample test data..."
"${psql_cmd[@]}" -f "${PROJECT_ROOT}/tests/sql/setup_test_data.sql"

echo "[MOCK-ETL] Ensuring dimension flags are set for recalculation..."
"${psql_cmd[@]}" -c "UPDATE dwh.dimension_countries SET modified = TRUE;"
"${psql_cmd[@]}" -c "UPDATE dwh.dimension_users SET modified = TRUE;" || true

echo "[MOCK-ETL] Creating/refreshing datamart procedures (best effort) ..."
# Create procedures if needed; rely on existing files
# IMPORTANT: Procedures must be created AFTER columns are added, as they reference the new columns
if [[ -f "${PROJECT_ROOT}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql" ]]; then
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql"
fi
if [[ -f "${PROJECT_ROOT}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql" ]]; then
 "${psql_cmd[@]}" -f "${PROJECT_ROOT}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql"
fi

echo "[MOCK-ETL] Populating datamartCountries..."
"${psql_cmd[@]}" -c '
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT DISTINCT dimension_id_country AS id
    FROM dwh.facts
    WHERE dimension_id_country IS NOT NULL
  ) LOOP
    BEGIN
      CALL dwh.update_datamart_country(r.id);
    EXCEPTION WHEN OTHERS THEN
      -- ignore test data gaps
      NULL;
    END;
  END LOOP;
END$$;
'

echo "[MOCK-ETL] Populating datamartUsers..."
"${psql_cmd[@]}" -c '
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN (
    SELECT DISTINCT action_dimension_id_user AS id
    FROM dwh.facts
    WHERE action_dimension_id_user IS NOT NULL
  ) LOOP
    BEGIN
      CALL dwh.update_datamart_user(r.id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END$$;
'

echo "[MOCK-ETL] Done."
echo "Mock ETL Pipeline Completed Successfully"
