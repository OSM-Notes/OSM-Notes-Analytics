---
title: "Installation and Dependencies Guide"
description: "Complete guide to install dependencies and set up OSM-Notes-Analytics for development"
version: "1.0.0"
last_updated: "2026-04-20"
author: "AngocA"
tags:
  - "installation"
  - "dependencies"
  - "setup"
audience:
  - "developers"
  - "data-engineers"
  - "system-admins"
project: "OSM-Notes-Analytics"
status: "active"
---

# Installation and Dependencies Guide

Complete guide to install all dependencies and set up OSM-Notes-Analytics for development and
production.

## Table of Contents

1. [System Requirements](#system-requirements)
2. [System Dependencies](#system-dependencies)
3. [Internal Dependencies](#internal-dependencies)
4. [Database Setup](#database-setup)
5. [Project Installation](#project-installation)
6. [Configuration](#configuration)
7. [Verification](#verification)
8. [Optional: User datamart catch-up (shell)](#optional-user-datamart-catch-up-shell)
9. [Troubleshooting](#troubleshooting)

---

## System Requirements

### Operating System

- **Linux** (Ubuntu 20.04+ / Debian 11+ recommended)
- **Bash** 4.0 or higher
- **Git** for cloning repositories

### Hardware Requirements

- **CPU**: 4+ cores recommended (for parallel processing)
- **RAM**: 8GB minimum, 16GB+ recommended (for large ETL operations)
- **Disk**: 100GB+ free space (for data warehouse and exports)
- **Network**: Low latency to PostgreSQL database (< 5ms ideal)

---

## System Dependencies

### Required Software

Install all required dependencies on Ubuntu/Debian:

```bash
# Update package list
sudo apt-get update

# PostgreSQL with PostGIS extension
sudo apt-get install -y postgresql postgresql-contrib postgis postgresql-14-postgis-3

# Standard UNIX utilities
sudo apt-get install -y grep awk sed curl jq bc

# Parallel processing (required for parallel ETL execution)
sudo apt-get install -y parallel

# Git (if not already installed)
sudo apt-get install -y git
```

### Verify Installation

```bash
# Check PostgreSQL version
psql --version  # Should be 12+

# Check PostGIS
psql -d postgres -c "SELECT PostGIS_version();"

# Check Bash version
bash --version  # Should be 4.0+

# Check parallel
parallel --version

# Check other tools
jq --version
curl --version
```

---

## Internal Dependencies

### ⚠️ Required: OSM-Notes-Ingestion

**OSM-Notes-Analytics REQUIRES OSM-Notes-Ingestion to be installed first.**

The Analytics project reads from the Ingestion database base tables:

- `public.notes`
- `public.note_comments`
- `public.note_comments_text`
- `public.users`
- `public.countries`

### Installation Order

1. **First**: Install and configure OSM-Notes-Ingestion
2. **Second**: Install OSM-Notes-Analytics (this project)
3. **Verify**: Ensure Ingestion database is populated before running ETL

### Database Configuration Options

Analytics supports two database configurations:

#### Option 1: Same Database (Single Database)

- **Ingestion database**: `notes`
- **Analytics database**: `notes` (same database)
- **Schema separation**: Ingestion uses `public`, Analytics uses `dwh`
- **No FDW required**: Direct access to base tables

#### Option 2: Separate Databases (Hybrid Strategy)

- **Ingestion database**: `notes` (on different server/host)
- **Analytics database**: `notes_dwh` (local)
- **FDW required**: Foreign Data Wrappers for remote access
- **Initial load**: Copies tables locally, then uses FDW for incremental

See [Hybrid Strategy Guide](Hybrid_Strategy_Copy_FDW.md) for details.

---

## Database Setup

### 1. Create Analytics Database

```bash
# Switch to postgres user
sudo su - postgres

# Create database (if using separate database)
psql << EOF
CREATE DATABASE notes_dwh WITH OWNER notes;
\q
EOF

exit
```

### 2. Enable PostGIS Extension

```bash
# For same database (uses Ingestion database)
psql -d notes -U notes << EOF
CREATE EXTENSION IF NOT EXISTS postgis;
\q
EOF

# For separate database
psql -d notes_dwh -U notes << EOF
CREATE EXTENSION IF NOT EXISTS postgis;
\q
EOF
```

### 3. Grant Permissions (if using separate databases)

```bash
# Grant access to Ingestion database (if separate)
psql -d notes -U postgres << EOF
GRANT CONNECT ON DATABASE notes TO notes;
GRANT USAGE ON SCHEMA public TO notes;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO notes;
\q
EOF
```

### 4. `postgres_fdw` in the Analytics database (separate databases only)

When `DBNAME_INGESTION` and `DBNAME_DWH` differ, the ETL creates a foreign server and foreign tables
in the **DWH** database using `postgres_fdw`. Two steps require a PostgreSQL **superuser** (or
equivalent), because the ETL user is usually **not** a superuser:

1. **Install the extension** in the DWH database (`DBNAME_DWH`, e.g. `notes_dwh`).
2. **Grant usage of the wrapper** to the role that runs the ETL (`DB_USER_DWH`, e.g. `notes`).
   Without this, `CREATE SERVER ... FOREIGN DATA WRAPPER postgres_fdw` fails with:
   `permission denied for foreign-data wrapper postgres_fdw`.

Run as superuser connected to the DWH database:

```sql
\c notes_dwh  -- use your DBNAME_DWH

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- Replace 'notes' with your DB_USER_DWH if different
GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO notes;
```

The ETL prerequisite step only checks that the extension exists in `DBNAME_DWH`; it does not grant
`USAGE` on the wrapper. You must apply the `GRANT` above (once per cluster/DWH role as needed).

---

## Project Installation

### 1. Clone Repository with Submodules

```bash
# Clone with submodules (recommended)
git clone --recurse-submodules https://github.com/OSM-Notes/OSM-Notes-Analytics.git
cd OSM-Notes-Analytics

# Or if already cloned, initialize submodules
git submodule update --init --recursive
```

### 2. Verify Submodule Installation

```bash
# Check submodule status
git submodule status

# Verify common functions exist
ls -la lib/osm-common/commonFunctions.sh
ls -la lib/osm-common/validationFunctions.sh
ls -la lib/osm-common/errorHandlingFunctions.sh
ls -la lib/osm-common/bash_logger.sh
```

### 3. Verify Ingestion Database Access

```bash
# Test connection to Ingestion database
psql -h localhost -U notes -d notes -c "SELECT COUNT(*) FROM public.notes;"

# Verify base tables exist
psql -h localhost -U notes -d notes -c "\dt public.*"
```

---

## Configuration

### 1. Environment Variables

Set required environment variables:

```bash
# Database configuration
export DBNAME_INGESTION="notes"          # Ingestion database name
export DBNAME_DWH="notes_dwh"        # Analytics database name (or same as Ingestion)
export DB_USER="notes"                   # Database user
export DB_PASSWORD="your_password"      # Database password
export DB_HOST="localhost"               # Database host
export DB_PORT="5432"                    # Database port

# ETL configuration
export LOG_LEVEL="INFO"                  # Logging level
export CLEAN="true"                     # Clean temporary files after processing

# Parallel processing
export PARALLEL_JOBS=$(($(nproc) - 1))  # Number of parallel jobs
```

### 2. Configuration File

Create or edit `etc/properties.sh`:

```bash
# Copy example if exists
cp etc/properties.sh.example etc/properties.sh

# Edit configuration
nano etc/properties.sh
```

### 3. Source Configuration

```bash
# Source the configuration
source etc/properties.sh

# Or export variables in your shell
export DBNAME_INGESTION="notes"
export DBNAME_DWH="notes_dwh"
# ... etc
```

---

## Verification

### 1. Verify Prerequisites

```bash
# Check all tools are installed
which psql parallel jq curl

# Check PostgreSQL connection
psql -h localhost -U notes -d notes -c "SELECT version();"
```

### 2. Verify Ingestion Database Access

```bash
# Check base tables exist
psql -h localhost -U notes -d notes -c "\dt public.*"

# Check data exists
psql -h localhost -U notes -d notes -c "SELECT COUNT(*) FROM public.notes;"
psql -h localhost -U notes -d notes -c "SELECT COUNT(*) FROM public.users;"
```

### 3. Run Tests

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test suites
./tests/unit/bash/run_unit_tests.sh
```

### 4. Verify Entry Points

```bash
# Check available entry points
cat bin/dwh/Entry_Points.md

# Verify scripts are executable
ls -la bin/dwh/*.sh
```

---

## Optional: User datamart catch-up (shell)

After installation and a successful `ETL.sh` run, `datamartUsers.sh` only processes up to
`MAX_USERS_PER_CYCLE` users per invocation (with higher limits in catch-up mode when the backlog is
large). See [Parallel_Processing.md](../bin/dwh/datamartUsers/Parallel_Processing.md) and
[Environment_Variables.md](../bin/dwh/Environment_Variables.md).

To **chain multiple cycles from the command line** without modifying repository code—each run starts
as soon as the previous one finishes—use a `while` loop that matches the same “pending work”
definition as the script (dimension users still `modified` and present in `dwh.facts`):

```bash
cd /path/to/OSM-Notes-Analytics

# Load DBNAME_DWH and connection defaults if you use properties.sh (same as ETL/cron)
set -a && source etc/properties.sh && set +a

PENDING_Q="
SELECT COUNT(DISTINCT f.action_dimension_id_user)
FROM dwh.facts f
JOIN dwh.dimension_users u ON f.action_dimension_id_user = u.dimension_user_id
WHERE u.modified = TRUE;
"

while [[ "$(psql -d "${DBNAME_DWH:-notes_dwh}" -Atq -c "$PENDING_Q")" -gt 0 ]]; do
  ./bin/dwh/datamartUsers/datamartUsers.sh || exit $?
done
echo "No remaining modified users in this backlog (per facts + dimension_users)."
```

**Operational notes:**

- Run **one** `datamartUsers.sh` at a time; the script enforces a lock.
- To process more users per iteration, export `MAX_USERS_PER_CYCLE`, `CATCHUP_MULTIPLIER`, or
  `MAX_USERS_PER_CYCLE_CATCHUP` in the same shell before the loop (see Parallel_Processing.md).
- Interrupt with Ctrl+C; if a run exits non-zero, the loop stops—fix the error before resuming.

---

## Troubleshooting

### Ingestion Database Not Found

**Error**: `relation "public.notes" does not exist`

**Solution**:

1. Ensure OSM-Notes-Ingestion is installed and configured
2. Verify Ingestion database is populated with data
3. Check database connection settings
4. Verify user has SELECT permissions on Ingestion tables

### Submodule Issues

```bash
# Initialize submodules
git submodule update --init --recursive

# Verify submodule exists
ls -la lib/osm-common/commonFunctions.sh
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
psql -h localhost -U notes -d notes

# Check user permissions
psql -U postgres -c "\du notes"
```

### Foreign Data Wrapper Issues (Hybrid Strategy)

If using separate databases and FDW:

```bash
# Install extension in DWH (superuser)
psql -d notes_dwh -c "CREATE EXTENSION IF NOT EXISTS postgres_fdw;"

# Allow the ETL user to create foreign servers (superuser; replace notes with DB_USER_DWH)
psql -d notes_dwh -c "GRANT USAGE ON FOREIGN DATA WRAPPER postgres_fdw TO notes;"

# Verify FDW server exists (after a successful ETL FDW step)
psql -d notes_dwh -c "SELECT * FROM pg_foreign_server;"
```

If you see **`permission denied for foreign-data wrapper postgres_fdw`**, the extension may be
installed but the `GRANT USAGE` line above was not applied for the role that runs `ETL.sh`.

See [Hybrid Strategy Guide](Hybrid_Strategy_Copy_FDW.md) for detailed FDW setup.

---

## Next Steps

After installation:

1. **Read Entry Points**: `bin/dwh/Entry_Points.md` - Which scripts to use
2. **Review Environment Variables**: `bin/dwh/Environment_Variables.md` - Configuration options
3. **Run ETL**: `./bin/dwh/ETL.sh` - Initial data warehouse load
4. **Large user datamart backlog**: Optional shell loop in
   [Optional: User datamart catch-up (shell)](#optional-user-datamart-catch-up-shell)
5. **Read Documentation**: `docs/README.md` - Complete documentation index

---

## Related Documentation

- [Entry Points](bin/dwh/Entry_Points.md) - Which scripts can be called directly
- [Environment Variables](bin/dwh/Environment_Variables.md) - Complete configuration reference
- [Hybrid Strategy Guide](Hybrid_Strategy_Copy_FDW.md) - Separate database setup
- [ETL Enhanced Features](ETL_Enhanced_Features.md) - ETL capabilities
- [Troubleshooting Guide](Troubleshooting_Guide.md) - Common issues and solutions
