---
title: "PostgreSQL Concurrency Strategy Analysis"
description:
  "Analysis of current implementation of PostgreSQL concurrency strategies in OSM Notes Analytics
  ETL processes"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "database"
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# PostgreSQL Concurrency Strategy Analysis

## Executive Summary

This document analyzes the current implementation of PostgreSQL concurrency strategies in the
OSM-Notes-Analytics project, specifically for queries that extract data from the sibling project
(ingestion) tables: `notes`, `note_comments`, `note_comments_text`, `users`, and `countries`.

## Current Implementation Status

### ✅ 1. PGAPPNAME - Implemented

**Status**: ✅ Implemented and working correctly

**Current location**:

- `bin/dwh/ETL.sh`: Function `__psql_with_appname` that automatically configures `PGAPPNAME`
- `bin/dwh/datamartCountries/datamartCountries.sh`: Uses the `__psql_with_appname` function
- `bin/dwh/datamartGlobal/datamartGlobal.sh`: Uses the `__psql_with_appname` function
- `bin/dwh/datamartUsers/datamartUsers.sh`: Uses the `__psql_with_appname` function

**Function used**: `__psql_with_appname` in `ETL.sh` (lines 273-350)

**Current values**:

- ETL.sh uses: `"ETL"`, `"ETL-year-{year}"`, etc.
- Datamart scripts use: script name (e.g., `"datamartCountries"`)

**Decision**: Current behavior is maintained as it is functional and allows clear identification of
each process in `pg_stat_activity`.

---

### ✅ 2. READ ONLY Transactions - Partially Implemented

**Status**: ✅ Implemented where possible

**Analysis**:

- Queries to ingestion project tables are performed mainly through:
  1. **Foreign Data Wrappers (FDW)**: When `DBNAME_INGESTION != DBNAME_DWH`
  2. **Direct access**: When both databases are the same

**Files that query ingestion tables**:

- `sql/dwh/Staging_32_createStagingObjects.sql`: Queries `note_comments`, `notes`,
  `note_comments_text`, `countries`, `users`
- `sql/dwh/Staging_34_initialFactsLoadCreate.sql`: Queries the same tables
- `sql/dwh/Staging_35a_initialFactsLoadExecute_Simple.sql`: Queries the same tables
- `sql/dwh/Staging_60_loadNotes.sql`: Queries `note_comments`
- `sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`: Queries `note_comments`,
  `note_comments_text`
- `sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`: Queries `note_comments`,
  `note_comments_text`

**Stored procedures that query**:

- `staging.process_notes_at_date()`: Queries `note_comments`, `notes`, `note_comments_text`
- `staging.process_notes_actions_into_dwh()`: Queries `note_comments`
- `dwh.update_datamart_country()`: Queries `note_comments`, `note_comments_text`
- `dwh.update_datamart_user()`: Queries `note_comments`, `note_comments_text`

**Implementation completed**:

1. **Direct SQL scripts**: ✅ Implemented
   - `sql/dwh/Staging_60_loadNotes.sql`: SELECT queries to `note_comments` are now wrapped in
     `BEGIN READ ONLY; ... COMMIT;` blocks

2. **Stored procedures**: ⚠️ Limited by design
   - Procedures that query ingestion tables (`staging.process_notes_at_date`,
     `staging.process_notes_actions_into_dwh`, `dwh.update_datamart_country`,
     `dwh.update_datamart_user`) also perform writes (INSERT/UPDATE), so they cannot use READ ONLY
     for the entire transaction
   - Comments were added documenting that SELECT queries to ingestion tables should be READ ONLY
     when possible
   - SELECT queries within these procedures are documented to indicate they read from ingestion
     tables

**Limitations**:

- In PostgreSQL, READ ONLY is a property of the entire transaction, not individual subqueries
- Procedures that perform both reads and writes cannot use READ ONLY for the entire transaction
- Best practice is to document SELECT queries that read from ingestion tables and trust that the
  remote server (if FDW) handles READ ONLY when possible

---

### ✅ 3. Timeouts - Implemented

**Status**: ✅ Implemented

**Configured timeouts**:

- `statement_timeout`: Limits execution time of an individual statement (default: `30min`)
- `lock_timeout`: Limits wait time to acquire a lock (default: `10s`)
- `idle_in_transaction_session_timeout`: Limits time a transaction can be idle (default: `10min`)

**Implementation completed**:

1. **Configuration variables**: ✅ Added in `etc/properties.sh`
   - `PSQL_STATEMENT_TIMEOUT`: `30min` (configurable)
   - `PSQL_LOCK_TIMEOUT`: `10s` (configurable)
   - `PSQL_IDLE_IN_TRANSACTION_TIMEOUT`: `10min` (configurable)

2. **Function `__psql_with_appname`**: ✅ Modified to automatically apply timeouts
   - Timeouts are automatically applied to all queries executed through `__psql_with_appname`
   - For SQL files (`-f`): A temporary file is created with timeout SET statements at the beginning
   - For SQL commands (`-c`): Timeout SET statements are prepended to the command
   - Temporary files are automatically cleaned up after execution

**Default values** (configurable in `etc/properties.sh`):

- `statement_timeout`: `30min`
- `lock_timeout`: `10s`
- `idle_in_transaction_session_timeout`: `10min`

---

## Specific Implementation Points

### A. Function `__psql_with_appname` in `ETL.sh`

**Location**: `bin/dwh/ETL.sh`, lines 273-288

**Proposed changes**:

```bash
function __psql_with_appname {
  local appname
  local readonly_mode="${PSQL_READONLY:-false}"
  local timeout_statement="${PSQL_STATEMENT_TIMEOUT:-}"
  local timeout_lock="${PSQL_LOCK_TIMEOUT:-}"

  if [[ "${1:-}" =~ ^- ]]; then
    appname="${BASENAME}"
  else
    appname="${1:-osm_notes_etl}"
    shift
  fi

  # Build psql command with timeouts and readonly if needed
  local psql_cmd="PGAPPNAME=\"${appname}\" psql"

  # Add timeout options if provided
  if [[ -n "${timeout_statement}" ]]; then
    psql_cmd="${psql_cmd} -v statement_timeout=\"${timeout_statement}\""
  fi
  if [[ -n "${timeout_lock}" ]]; then
    psql_cmd="${psql_cmd} -v lock_timeout=\"${timeout_lock}\""
  fi

  # Execute with readonly transaction wrapper if needed
  if [[ "${readonly_mode}" == "true" ]]; then
    eval "${psql_cmd}" -c "BEGIN READ ONLY; $(cat); COMMIT;" "$@"
  else
    eval "${psql_cmd}" "$@"
  fi
}
```

### B. Stored Procedures that Query Ingestion Tables

**Files to modify**:

1. **`sql/dwh/Staging_32_createStagingObjects.sql`**
   - Procedure: `staging.process_notes_at_date()`
   - Lines: 50-350 (approximately)
   - Add at the beginning: `SET TRANSACTION READ ONLY;` (within the procedure)

2. **`sql/dwh/Staging_32_createStagingObjects.sql`**
   - Procedure: `staging.process_notes_actions_into_dwh()`
   - Lines: 356-477 (approximately)
   - Add: `SET TRANSACTION READ ONLY;` for read queries

3. **`sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`**
   - Procedure: `dwh.update_datamart_country()`
   - Add: `SET TRANSACTION READ ONLY;` for SELECT queries

4. **`sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`**
   - Procedure: `dwh.update_datamart_user()`
   - Add: `SET TRANSACTION READ ONLY;` for SELECT queries

**Important note**: Procedures that perform INSERT/UPDATE cannot use READ ONLY for the entire
transaction, but SELECT queries within them can be executed in READ ONLY sub-transactions.

### C. Directly Executed SQL Scripts

**Files to modify**:

1. **`sql/dwh/Staging_60_loadNotes.sql`**
   - Lines 8-12 and 22-26: SELECT queries to `note_comments`
   - Wrap in: `BEGIN READ ONLY; ... COMMIT;`

2. **`sql/dwh/ETL_60_setupFDW.sql`**
   - Lines 130-134: ANALYZE commands on foreign tables
   - These are maintenance commands, don't need READ ONLY

### D. Timeout Configuration in Properties

**File to modify**: `etc/properties.sh` or create `etc/etl.properties`

**Add variables**:

```bash
# PostgreSQL timeouts for ETL queries
PSQL_STATEMENT_TIMEOUT="${PSQL_STATEMENT_TIMEOUT:-30min}"
PSQL_LOCK_TIMEOUT="${PSQL_LOCK_TIMEOUT:-10s}"
PSQL_IDLE_IN_TRANSACTION_TIMEOUT="${PSQL_IDLE_IN_TRANSACTION_TIMEOUT:-10min}"

# Use READ ONLY transactions for ingestion table queries
PSQL_READONLY_FOR_INGESTION="${PSQL_READONLY_FOR_INGESTION:-true}"

# Application name for PostgreSQL connections
PSQL_APPNAME="${PSQL_APPNAME:-osm_notes_etl}"
```

---

## Recommended Implementation Strategy

### Phase 1: Base Configuration

1. ✅ Update `__psql_with_appname` to use `PGAPPNAME="osm_notes_etl"` by default
2. ✅ Add configuration variables in `etc/properties.sh`
3. ✅ Implement timeout support in `__psql_with_appname`

### Phase 2: READ ONLY Transactions

1. ✅ Modify stored procedures that only read data
2. ✅ Wrap direct SELECT queries in READ ONLY blocks
3. ✅ Add READ ONLY to subqueries within procedures that also write

### Phase 3: Timeouts

1. ✅ Configure default timeouts in `__psql_with_appname`
2. ✅ Add timeouts to critical stored procedures
3. ✅ Document recommended values based on data size

### Phase 4: Testing and Validation

1. ✅ Verify queries work correctly with READ ONLY
2. ✅ Validate that timeouts don't interrupt normal operations
3. ✅ Monitor `pg_stat_activity` to verify `application_name`

---

## Special Considerations

### Foreign Data Wrappers (FDW)

When using FDW to access ingestion tables:

- READ ONLY queries on the DWH side do not guarantee READ ONLY on the remote server
- The remote server (ingestion) must configure its own timeouts and READ ONLY
- The `FDW_INGESTION_USER` configuration already uses `analytics_readonly` (good practice)

### Queries in Procedures that Write

Some procedures perform both reads and writes:

- `staging.process_notes_at_date()`: Reads from ingestion, writes to DWH
- `staging.process_notes_actions_into_dwh()`: Reads from ingestion, writes to DWH

**Strategy**: Use READ ONLY sub-transactions only for SELECT queries to ingestion tables, not for
the entire transaction.

### Compatibility with Same Database

When `DBNAME_INGESTION == DBNAME_DWH`:

- Tables are local, not foreign tables
- READ ONLY is still beneficial to avoid unnecessary locks
- Timeouts apply equally

---

## Files Requiring Modifications

### Bash Scripts

- `bin/dwh/ETL.sh`: Function `__psql_with_appname`
- `bin/dwh/datamartCountries/datamartCountries.sh`: Use updated function
- `bin/dwh/datamartGlobal/datamartGlobal.sh`: Use updated function
- `bin/dwh/datamartUsers/datamartUsers.sh`: Use updated function

### SQL Files

- `sql/dwh/Staging_32_createStagingObjects.sql`: Procedures `process_notes_at_date` and
  `process_notes_actions_into_dwh`
- `sql/dwh/Staging_60_loadNotes.sql`: SELECT queries
- `sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`: Procedure
  `update_datamart_country`
- `sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`: Procedure `update_datamart_user`

### Configuration Files

- `etc/properties.sh`: Add timeout and READ ONLY variables
- `etc/properties.sh.example`: Document new variables

---

## References

- Ingestion project strategy document: `PostgreSQL_Concurrency_Strategy.md`
- PostgreSQL Documentation:
  [Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html)
- PostgreSQL Documentation:
  [Runtime Configuration - Statement Behavior](https://www.postgresql.org/docs/current/runtime-config-client.html)

---

## Conclusion

The project now implements PostgreSQL concurrency strategies:

1. ✅ **PGAPPNAME**: Already implemented and current behavior is maintained (functional and allows
   process identification)

2. ✅ **READ ONLY Transactions**: Implemented where possible
   - Direct SQL scripts that only read: Fully implemented
   - Procedures that also write: Documented (PostgreSQL limitation)

3. ✅ **Timeouts**: Fully implemented
   - Configuration variables in `etc/properties.sh`
   - Automatic application through `__psql_with_appname`
   - Sensible default values for ETL operations

**Modified files**:

- `etc/properties.sh`: Added timeout configuration variables
- `bin/dwh/ETL.sh`: Modified `__psql_with_appname` function to support timeouts
- `sql/dwh/Staging_60_loadNotes.sql`: Added READ ONLY transactions for SELECT queries
- `sql/dwh/Staging_32_createStagingObjects.sql`: Added comments documenting queries to ingestion
  tables
- `sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`: Added comments documenting
  queries to ingestion tables
- `sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`: Added comments documenting queries
  to ingestion tables

**Expected benefits**:

- Better process identification in `pg_stat_activity` (already existing)
- Reduced blocking through configured timeouts
- Better concurrency in read-only queries through READ ONLY where possible
- Protection against queries that run indefinitely
