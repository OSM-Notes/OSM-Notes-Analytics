---
title: "Hybrid Strategy: Database Separation"
description:
  "Strategy to copy base tables locally to avoid millions of cross-database queries, improving ETL
  performance"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
  - "etl"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Hybrid Strategy: Database Separation

## Summary

**Implemented strategy:**

- **Initial load**: Copy base tables locally to avoid millions of cross-database queries
- **Incremental execution**: Use Foreign Data Wrappers (FDW) to access new data

**Benefits:**

- ✅ Initial load without FDW overhead (local tables)
- ✅ Incremental with FDW only for small volumes
- ✅ Better performance: ~30.5h initial, ~6-18min incremental

---

## Implementation

### Created Files

**Scripts:**

- `bin/dwh/copyBaseTables.sh` - Copies base tables for initial load
- `bin/dwh/dropCopiedBaseTables.sh` - Drops copied tables after load
- `sql/dwh/ETL_60_setupFDW.sql` - Configures FDW for incremental

**Tests:**

- `tests/unit/bash/hybrid_strategy_copy_fdw.test.bats`

### How It Works

**Initial load (first execution):**

```
1. ETL.sh detects first execution
   ↓
2. copyBaseTables.sh copies tables: notes, note_comments, note_comments_text, users, countries
   ↓
3. ETL processes data (local tables, no FDW)
   ↓
4. dropCopiedBaseTables.sh drops copied tables
```

**Incremental execution:**

```
1. ETL.sh detects incremental execution
   ↓
2. ETL compares DBNAME_INGESTION and DBNAME_DWH
   ↓
3a. If databases are DIFFERENT:
    - ETL_60_setupFDW.sql configures FDW (if not exists)
    - ETL processes new data using foreign tables
3b. If databases are the SAME:
    - FDW setup is skipped (tables are directly accessible)
    - ETL processes new data using local tables
```

---

## Configuration

### Variables in `etc/properties.sh`

**Option 1: Separate Databases (FDW enabled)**

```bash
# Separate databases
DBNAME_INGESTION="notes"
DBNAME_DWH="notes_dwh"
DB_USER_INGESTION="ingestion_user"
DB_USER_DWH="analytics_user"

# FDW configuration (required for incremental when databases are different)
FDW_INGESTION_HOST="localhost"
FDW_INGESTION_DBNAME="notes"
FDW_INGESTION_PORT="5432"
FDW_INGESTION_USER="analytics_readonly"
FDW_INGESTION_PASSWORD=""  # Use .pgpass or environment variable
```

**Option 2: Same Database (FDW disabled automatically)**

```bash
# Same database for both Ingestion and Analytics
# Option 2a: Use recommended variables (set to same value)
DBNAME_INGESTION="notes_dwh"
DBNAME_DWH="notes_dwh"

# Option 2b: Use legacy DBNAME (for backward compatibility)
DBNAME="notes_dwh"
# When DBNAME_INGESTION and DBNAME_DWH are not set, DBNAME is used for both

# FDW configuration is not needed (will be skipped automatically)
```

**Note:** When `DBNAME_INGESTION` and `DBNAME_DWH` are the same (or both unset and `DBNAME` is
used), the ETL automatically skips FDW setup since tables are directly accessible in the same
database. The recommended approach is to use `DBNAME_INGESTION` and `DBNAME_DWH` even when they have
the same value, for clarity and consistency.

### Create Read-Only User for FDW

**Important:** This step must be completed **before** running the ETL when using separate databases.
The FDW user needs read-only access to the Ingestion database tables.

**Step 1: Create the user (if it doesn't exist)**

```sql
-- Connect to the Ingestion database
\c notes  -- or whatever your DBNAME_INGESTION is

-- Create the FDW user (replace 'secure_password' with a strong password)
-- Replace 'osm_notes_ingestion_user' with your FDW_INGESTION_USER value
CREATE USER osm_notes_ingestion_user WITH PASSWORD 'secure_password';
```

**Step 2: Grant read-only permissions**

```sql
-- Grant connection to the database
GRANT CONNECT ON DATABASE notes TO osm_notes_ingestion_user;

-- Grant usage on the public schema
GRANT USAGE ON SCHEMA public TO osm_notes_ingestion_user;

-- Grant SELECT on all existing tables
GRANT SELECT ON ALL TABLES IN SCHEMA public TO osm_notes_ingestion_user;

-- Grant SELECT on future tables (so permissions persist for new tables)
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO osm_notes_ingestion_user;
```

**Step 3: Verify permissions**

```sql
-- Verify the user exists
SELECT usename, usecreatedb, usesuper FROM pg_user WHERE usename = 'osm_notes_ingestion_user';

-- Verify permissions on required tables
SELECT grantee, privilege_type, table_name
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND table_name IN ('note_comments', 'notes', 'note_comments_text', 'users', 'countries')
  AND grantee = 'osm_notes_ingestion_user'
ORDER BY table_name, privilege_type;
```

**Note:** If the user already exists, skip Step 1 and only run Steps 2 and 3. The `GRANT` statements
are idempotent and safe to run multiple times.

**Complete example script:**

```sql
-- Setup FDW user for Analytics ETL
-- Run this in the Ingestion database (DBNAME_INGESTION)

-- Create user if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'osm_notes_ingestion_user') THEN
    CREATE USER osm_notes_ingestion_user WITH PASSWORD 'secure_password';
    RAISE NOTICE 'User osm_notes_ingestion_user created';
  ELSE
    RAISE NOTICE 'User osm_notes_ingestion_user already exists';
  END IF;
END $$;

-- Grant permissions
GRANT CONNECT ON DATABASE notes TO osm_notes_ingestion_user;
GRANT USAGE ON SCHEMA public TO osm_notes_ingestion_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO osm_notes_ingestion_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO osm_notes_ingestion_user;

-- Verify
SELECT
  'User exists: ' || EXISTS(SELECT 1 FROM pg_user WHERE usename = 'osm_notes_ingestion_user') as status
UNION ALL
SELECT
  'Has SELECT on note_comments: ' || EXISTS(
    SELECT 1 FROM information_schema.role_table_grants
    WHERE grantee = 'osm_notes_ingestion_user'
      AND table_name = 'note_comments'
      AND privilege_type = 'SELECT'
  ) as status;
```

---

## Usage

### First Execution (Initial Load)

```bash
./bin/dwh/ETL.sh
```

Auto-detects first execution and:

1. Copies base tables from Ingestion to Analytics
2. Populates DWH using local tables (no FDW)
3. Drops copied tables after completion

### Subsequent Executions (Incremental)

```bash
./bin/dwh/ETL.sh
```

Auto-detects incremental execution and:

1. Compares `DBNAME_INGESTION` and `DBNAME_DWH` to determine if databases are separate
2. **If databases are different:**
   - Configures FDW (if not exists)
   - Processes new data using foreign tables
3. **If databases are the same:**
   - Skips FDW setup (tables are directly accessible)
   - Processes new data using local tables directly

---

## Troubleshooting

### Error: "Cannot connect to source database"

**Solution:** Verify `DBNAME_INGESTION` and `DB_USER_INGESTION` variables in `etc/properties.sh`

### Error: "Failed to setup Foreign Data Wrappers"

**Solution:**

- Verify that the FDW user (value of `FDW_INGESTION_USER`) exists in Ingestion DB
- Verify read permissions (see "Create Read-Only User for FDW" section above)
- Verify `FDW_INGESTION_*` variables in `etc/properties.sh`
- Check that `FDW_INGESTION_PASSWORD` is set correctly or `.pgpass` is configured

### Error: "permission denied for table note_comments"

**Solution:** The FDW user doesn't have SELECT permissions. Run the permission grants:

```sql
-- In Ingestion DB
GRANT CONNECT ON DATABASE notes TO osm_notes_ingestion_user;
GRANT USAGE ON SCHEMA public TO osm_notes_ingestion_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO osm_notes_ingestion_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO osm_notes_ingestion_user;
```

Replace `osm_notes_ingestion_user` with your `FDW_INGESTION_USER` value and `notes` with your
`DBNAME_INGESTION` value.

### Error: "Table already exists in target database"

**Solution:** The script handles this automatically (drops and recreates). If it persists:

```bash
psql -d notes_dwh -c "DROP TABLE IF EXISTS public.notes, public.note_comments, public.note_comments_text, public.users, public.countries CASCADE;"
```

---

## Testing

```bash
# Hybrid strategy tests
bats tests/unit/bash/hybrid_strategy_copy_fdw.test.bats

# All tests
./tests/run_all_tests.sh
```

---

## Technical Details

### Copy Method

The `copyBaseTables.sh` script uses **COPY with piping** (fastest method):

```bash
psql -d "${INGESTION_DB}" -c "\COPY public.notes TO STDOUT" | \
psql -d "${ANALYTICS_DB}" -c "\COPY public.notes FROM STDIN"
```

**Estimated performance:**

- notes: ~1-5 minutes
- note_comments: ~5-20 minutes
- note_comments_text: ~2-10 minutes
- users: ~10-30 seconds
- countries: ~1-5 seconds
- **Total: 10-40 minutes** for all tables

### Foreign Data Wrappers

The `ETL_60_setupFDW.sql` script configures:

- Foreign server pointing to Ingestion DB
- Foreign tables: `notes`, `note_comments`, `note_comments_text`, `users`, `countries`
- Optimizations: `fetch_size='10000'`, `use_remote_estimate='true'`

**Estimated overhead:** 15-25% on incremental queries (acceptable for small volumes)

**Automatic Skip:** When `DBNAME_INGESTION` equals `DBNAME_DWH` (or both are unset), the ETL
automatically skips FDW setup. The system logs:
`"Ingestion and Analytics use same database, skipping FDW setup"`. This prevents SQL errors that
would occur when trying to create foreign tables pointing to the same database.

---

## Status

✅ **Implemented and ready to use**

The strategy is fully integrated in `ETL.sh` and runs automatically based on detected mode.
