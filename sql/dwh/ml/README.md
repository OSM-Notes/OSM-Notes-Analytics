# Machine Learning with pgml

This directory contains SQL scripts for implementing Machine Learning classification of OSM notes
using **pgml** (PostgreSQL Machine Learning).

**Production path:** follow the main repository [README.md](../../README.md) **Quick Start — Step 9**
for install order, cron (training + batch classification), and links back here for pgml system setup.

## Overview

**pgml** allows us to train and use ML models directly in PostgreSQL, eliminating the need for
external Python services. This approach:

- ✅ **Simplifies deployment**: No separate ML service needed
- ✅ **Integrates seamlessly**: Uses existing PostgreSQL infrastructure
- ✅ **Leverages existing data**: Builds on our star schema and datamarts
- ✅ **SQL-native**: Everything done in SQL, no language switching
- ✅ **Real-time predictions**: Fast inference directly in database

## Prerequisites

1. **PostgreSQL 14, 15, 16, or 17** (pgml requires PostgreSQL 14+)
   - ⚠️ **Note**: While this project works with PostgreSQL 12+, **pgml specifically requires 14+**
   - If you're using PostgreSQL 12 or 13, you'll need to upgrade to 14+ to use pgml
   - Check your current version: `SELECT version();`
2. **pgml extension installed** at system level (see Installation section)
3. **Training data**: Minimum 1000+ resolved notes (more is better)
4. **Features prepared**: Views with training features (see `ml_01_setupPgML.sql`)

## Installation

### ⚠️ Important: Two-Step Installation Process

**pgml requires TWO steps** - it's NOT just SQL commands:

1. **System-level installation** (install pgml extension on server)
2. **Database-level activation** (enable extension in database)

### Debian/Ubuntu: version and paths (generic)

Use the **same** `psql` connection you use for the DWH instance (adjust host/port if needed).

- **Major version `PG_VER`** (14–17): set explicitly, e.g. `export PG_VER=17`, or derive:
  `export PG_VER="$(psql -d postgres -Atqc "SELECT current_setting('server_version_num')::int / 10000")"`
- **Cluster name `PG_CLUSTER`**: usually `main` on Debian/Ubuntu packaged installs (see
  `systemctl list-units 'postgresql@*' --no-legend` if unsure).
- **`postgresql.auto.conf`**: the file **does not exist until the first successful `ALTER SYSTEM`**
  on that cluster. Its path is whatever **`pg_file_settings.sourcefile`** reports for your change (on
  some Debian/Ubuntu setups `postgresql.conf` lives under `/etc/postgresql/…` while
  `postgresql.auto.conf` is under **`/var/lib/postgresql/…/main/`** — both are normal).

```bash
# Directory of the main postgresql.conf (useful for manual edits to postgresql.conf only)
CONF_DIR="$(sudo -u postgres psql -d postgres -tAc 'SHOW config_file' | xargs dirname)"
```

- **Restart** (typical multi-version layout):  
  `sudo systemctl restart "postgresql@${PG_VER}-${PG_CLUSTER}"`  
  or `sudo systemctl restart postgresql` on single-instance layouts.

### Python: interpreter for pip (`PY`)

pgml uses whatever Python its **build** linked against (on the same host, that is usually the
distro’s default `python3`, e.g. 3.11 / 3.12 / 3.13 — not necessarily 3.10). If `CREATE EXTENSION
pgml` or logs mention a version, install pip packages **for that interpreter**.

Set once and reuse in the commands below:

```bash
export PY=python3
# Or an explicit minor, if that is what pgml reports (examples: python3.12, python3.13):
# export PY=python3.13
```

Use: `sudo "$PY" -m pip ...` and `sudo -u postgres "$PY" -c '...'`.

### Step 1: System-Level Installation

**This must be done FIRST** - installing pgml at the operating system level:

⚠️ **IMPORTANT**: pgml is **NOT available** as a standard apt/deb package. You must use one of the
methods below.

#### Option A: Automated Installation Script (RECOMMENDED for existing databases)

If you already have a PostgreSQL database with data, use the automated installation script:

```bash
# Run the installation script (requires sudo)
cd sql/dwh/ml
sudo ./install_pgml.sh
```

This script will:

- Install all required dependencies
- Install Rust compiler
- Clone and compile pgml from source
- Install pgml extension in your existing PostgreSQL
- Verify the installation

**After installation**, you need to:

1. **Install Python ML dependencies** (required for pgml):

```bash
# Install system packages (may not be sufficient - see troubleshooting below)
sudo apt-get install python3-numpy python3-scipy python3-xgboost

# CRITICAL: pgml requires additional packages that may not be available via apt:
# - lightgbm
# - scikit-learn (imported as 'sklearn')
# These must be installed with pip for the specific Python version pgml uses
```

2. **Configure shared_preload_libraries** (required for model deployment):

```bash
# Add pgml to shared_preload_libraries (target the instance that will load pgml)
psql -d postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,pgml';"
# Or if pg_stat_statements is not installed:
psql -d postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pgml';"

# Verify what PostgreSQL read from config files (14+; no need to open files by hand)
psql -d postgres -c "SELECT sourcefile, name, setting, applied FROM pg_file_settings WHERE name = 'shared_preload_libraries';"
# applied = f for this parameter is normal until you restart — it only becomes t after reload.
# psql may print setting with outer quotes; the stored value must be the comma-separated list only,
# e.g. pg_stat_statements,pgml (not a second layer of "quotes" inside the value).

# After restart, the active value:
# psql -d postgres -c "SHOW shared_preload_libraries;"

# Optional: inspect the real postgresql.auto.conf path (use sourcefile — not always dirname(config_file))
AUTO_CONF="$(psql -d postgres -Atqc "SELECT sourcefile FROM pg_file_settings WHERE name = 'shared_preload_libraries' AND sourcefile LIKE '%postgresql.auto.conf' LIMIT 1;")"
if [[ -n "$AUTO_CONF" ]] && sudo test -f "$AUTO_CONF"; then
  sudo grep shared_preload_libraries "$AUTO_CONF"
else
  echo "No postgresql.auto.conf row yet — run the ALTER SYSTEM command above first."
fi
# In the file, the line should look like: shared_preload_libraries = 'pg_stat_statements,pgml'
# NOT: shared_preload_libraries = '"pg_stat_statements,pgml"'

# If the line is wrong, edit that file (path from sourcefile above):
if [[ -n "$AUTO_CONF" ]] && sudo test -f "$AUTO_CONF"; then
  sudo "${EDITOR:-nano}" "$AUTO_CONF"
fi

# Restart PostgreSQL (set PG_VER / PG_CLUSTER per "Debian/Ubuntu: version and paths", or use generic restart)
export PG_CLUSTER="${PG_CLUSTER:-main}"
sudo systemctl restart "postgresql@${PG_VER}-${PG_CLUSTER}"
# If that unit does not exist: sudo systemctl restart postgresql
```

3. **Install Python packages for the specific Python version** (see troubleshooting section below):

```bash
# Default to distro python3 if PY not set (see "Python: interpreter for pip (PY)")
export PY="${PY:-python3}"
sudo "$PY" -m pip install --break-system-packages --ignore-installed --no-cache-dir \
  numpy scipy xgboost lightgbm scikit-learn

# Verify installation
sudo -u postgres "$PY" -c "import numpy, scipy, xgboost, lightgbm, sklearn; print('OK')"
```

4. **Enable extension in your database**:

```bash
# If several PostgreSQL versions are installed, use the client matching PG_VER (see "Debian/Ubuntu: version and paths")
PSQL_BIN="/usr/lib/postgresql/${PG_VER}/bin/psql"
sudo -u postgres "$PSQL_BIN" -d notes_dwh -c "CREATE EXTENSION IF NOT EXISTS pgml;"

# Verify
sudo -u postgres "$PSQL_BIN" -d notes_dwh -c "SELECT pgml.version();"
# When only one version is installed, plain: sudo -u postgres psql -d notes_dwh ...
```

**Note**: The `apt-get` packages may not be sufficient because:

- They may be compiled for a different Python version than what pgml uses
- `lightgbm` and `scikit-learn` are not available in standard apt repositories
- You MUST install them with pip for the **same** Python pgml uses (see `PY` above; often the
  distro default `python3`)

**Rust build: `xgboost-sys` / `is cmake not installed?`**: The C++ build uses CMake. Install it
(`sudo apt-get install -y cmake`) and ensure it is on `PATH`, or export the absolute path for the
`cmake` crate: `export CMAKE=/usr/bin/cmake` before `cargo build`. The `install_pgml.sh` script
installs CMake and sets `CMAKE` automatically.

**PostgreSQL fails to start — `FATAL: could not access file "pg_stat_statements,pgml"`**: PostgreSQL
is loading **one** library whose name includes the comma (the list was not parsed as two entries).
This almost always means **bad quoting** in `postgresql.auto.conf` (e.g. nested `"` around the
whole list). The line must look like this (single-quoted list, **no** extra double quotes inside):

```text
shared_preload_libraries = 'pg_stat_statements,pgml'
```

**Not** `shared_preload_libraries = '"pg_stat_statements,pgml"'`. While PostgreSQL is down, edit the
file as root (path is often under `/var/lib/postgresql/PG_VER/main/` or see `pg_file_settings.sourcefile`
from a working instance / backup). Then `sudo systemctl start postgresql@PG_VER-main`. If
`pg_stat_statements` is not installed, use `shared_preload_libraries = 'pgml'` only (and install
`postgresql-contrib` / enable the extension later if needed). `systemctl` changes require **sudo**
(or root).

**Troubleshooting**: If you get errors about missing Python modules or numpy source directory:

1. **Verify Python packages are accessible to PostgreSQL**:

```bash
# Check what Python PostgreSQL is using
sudo -u postgres python3 -c "import sys; print(sys.executable)"
sudo -u postgres python3 -c "import numpy; print(numpy.__version__)" || echo "numpy not found"
sudo -u postgres python3 -c "import xgboost; print(xgboost.__version__)" || echo "xgboost not found"
```

2. **If packages are missing for PostgreSQL's Python**, install them with pip using
   `--break-system-packages`:

```bash
# First, identify which Python version pgml is using (error message from CREATE EXTENSION / logs).
# Install pip packages for that exact interpreter (set PY — see "Python: interpreter for pip (PY)").

# CRITICAL: apt packages like python3-numpy may target a different runtime than pgml.

export PY="${PY:-python3}"

# Ensure pip / venv for that interpreter (Debian/Ubuntu: meta-packages track default python3)
sudo "$PY" -m ensurepip --upgrade 2>/dev/null || \
sudo apt-get install -y python3-venv python3-dev python3-pip

# Install required wheels
sudo "$PY" -m pip install --break-system-packages --ignore-installed --no-cache-dir \
  numpy scipy xgboost lightgbm scikit-learn

# Verify (repeat with the same PY)
sudo -u postgres "$PY" -c "import numpy; print('numpy:', numpy.__version__)"
sudo -u postgres "$PY" -c "import scipy; print('scipy:', scipy.__version__)"
sudo -u postgres "$PY" -c "import xgboost; print('xgboost:', xgboost.__version__)"
sudo -u postgres "$PY" -c "import lightgbm; print('lightgbm:', lightgbm.__version__)"
sudo -u postgres "$PY" -c "import sklearn; print('sklearn:', sklearn.__version__)"

sudo -u postgres "$PY" -c "import numpy, scipy, xgboost, lightgbm, sklearn; print('OK')"
```

**Important**: If you get errors about `numpy.core._multiarray_umath` or "numpy source directory",
it means the numpy package is not properly installed for that Python version. The apt packages
(`python3-numpy`) are compiled for one Python version, but pgml may use another. You MUST install
with pip for the interpreter pgml actually loads (`PY`).

3. **If you get numpy source directory error**, check PYTHONPATH in PostgreSQL environment:

```bash
# Check PostgreSQL's environment
sudo -u postgres env | grep PYTHONPATH

# Check systemd service file for PostgreSQL (set PG_VER / PG_CLUSTER to match your host)
UNIT="postgresql@${PG_VER}-${PG_CLUSTER}.service"
sudo systemctl show "$UNIT" | grep Environment
# Or check the main service
sudo systemctl show postgresql.service | grep Environment

# If PYTHONPATH includes numpy source directories, you need to fix it:
# Option 1: Edit PostgreSQL systemd service override
sudo systemctl edit "$UNIT"
# Add:
# [Service]
# Environment="PYTHONPATH="

# Option 2: Or edit the main PostgreSQL service
sudo systemctl edit postgresql.service
# Add:
# [Service]
# Environment="PYTHONPATH="

# Then reload and restart
sudo systemctl daemon-reload
sudo systemctl restart postgresql
```

**Alternative solution**: If the above doesn't work, check if there's a numpy source directory in
common locations:

```bash
# systemd unit for this cluster (PG_VER / PG_CLUSTER — see "Debian/Ubuntu: version and paths")
export PG_CLUSTER="${PG_CLUSTER:-main}"
UNIT="postgresql@${PG_VER}-${PG_CLUSTER}.service"

# Check for numpy source directories in /tmp (common build location)
find /tmp -name "numpy" -type d 2>/dev/null | head -5

# Check if there's a numpy source directory in the pgml build directory
find /tmp/pgml-build -name "numpy" -type d 2>/dev/null | head -5

# Remove any numpy source directories found
find /tmp -name "numpy" -type d -path "*/pgml-build/*" -exec rm -rf {} + 2>/dev/null || true
find /tmp -name "numpy" -type d -path "*/target/*" -exec rm -rf {} + 2>/dev/null || true

# Verify the systemd override was applied
sudo systemctl show "$UNIT" | grep -i environment

# If PYTHONPATH is still set, try unsetting it explicitly
sudo systemctl edit "$UNIT"
# Make sure it contains:
# [Service]
# Environment="PYTHONPATH="
# Environment="PYTHONHOME="

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart postgresql
```

**If the problem persists**, pgml may have been compiled against a different Python than the one
you install packages for. The error text usually states which Python version pgml expects.

**Solution**: install pip packages for **that** interpreter (`export PY=python3.X`), or recompile
pgml so it links to your intended `python3`:

```bash
# 1. Set PY from the pgml error (example: export PY=python3.13)
export PY="${PY:-python3}"
# 2. Install dev/venv packages for that minor on Debian/Ubuntu, e.g.:
#    sudo apt-get install python3.13-dev python3.13-venv
#    (replace 3.13 with your minor version)

sudo "$PY" -m pip install --break-system-packages numpy scipy xgboost lightgbm scikit-learn
sudo -u postgres "$PY" -c "import numpy, scipy, xgboost; print('OK')"

sudo systemctl restart postgresql
psql -d notes_dwh -c 'CREATE EXTENSION IF NOT EXISTS pgml;'
```

**Alternative — re-link pgml to the current default `python3`**: re-run the build on the same
machine so it picks up the interpreter that will run PostgreSQL:

```bash
cd sql/dwh/ml
sudo ./install_pgml.sh
```

**Version mismatch** (pgml built for Python A, system default is Python B): either install packages
with `PY` pointing at Python A, or make Python B the one used during `install_pgml.sh` / `cargo`
(e.g. `update-alternatives` for `python3`, or install `python3-A` and set `PY` for pip), then
rebuild pgml.

**If the numpy source directory error persists**, it might be that pgml is finding a numpy source
directory during import. Try:

```bash
# Find and remove any numpy source directories
find /tmp -type d -name "numpy" -not -path "*/site-packages/*" -exec rm -rf {} + 2>/dev/null || true
find /root -type d -name "numpy" -not -path "*/site-packages/*" -exec rm -rf {} + 2>/dev/null || true

# Also check if there's a numpy directory in the current working directory
# when PostgreSQL tries to load pgml
# This can happen if the working directory contains numpy source
```

4. **Restart PostgreSQL after installing packages**:

```bash
sudo systemctl restart postgresql
```

#### Option B: Using Docker (Only if starting fresh)

⚠️ **Not recommended if you already have a database** - Docker requires migrating your entire
database.

This is only practical if you're starting a new project:

```bash
# Use official pgml Docker image
docker run -d \
  --name postgres-pgml \
  -e POSTGRES_PASSWORD=yourpassword \
  -e POSTGRES_DB=notes_dwh \
  -p 5432:5432 \
  ghcr.io/postgresml/postgresml:latest

# Connect to the containerized database
docker exec -it postgres-pgml psql -U postgres -d notes_dwh
```

**Note**: If using Docker with an existing database, you'll need to:

1. Export your database: `pg_dump notes_dwh > backup.sql`
2. Import into Docker container:
   `docker exec -i postgres-pgml psql -U postgres -d notes_dwh < backup.sql`
3. Update all connection strings to point to the Docker container

#### Option C: Manual Compilation from Source

**Prerequisites**:

- PostgreSQL 14+ development headers
- Rust compiler (pgml is written in Rust)
- Python 3.8+ with development headers
- Build tools (make, gcc, etc.) and **CMake** (required to compile XGBoost/LightGBM bundled with pgml)

```bash
# Set PG_VER to your PostgreSQL major version (14–17); see "Debian/Ubuntu: version and paths"
export PG_VER=17

# Install build dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  cmake \
  "postgresql-server-dev-${PG_VER}" \
  libpython3-dev \
  python3-pip \
  curl \
  git

# Install Rust (required for pgml)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source $HOME/.cargo/env

# Clone pgml repository
git clone https://github.com/postgresml/postgresml.git
cd postgresml

# Build and install
# This will take 10-30 minutes depending on your system
cargo build --release

# Install the extension
sudo make install

# Verify installation
ls /usr/share/postgresql/*/extension/pgml*
```

**For detailed build instructions**, see:

- https://github.com/postgresml/postgresml#installation
- https://postgresml.org/docs/guides/getting-started/installation

#### Option D: Using Pre-built Binaries (If Available)

Check the pgml releases page for pre-built binaries:

- https://github.com/postgresml/postgresml/releases

**Note**: Pre-built binaries may not be available for all platforms/PostgreSQL versions.

**Check system installation**:

```bash
# Verify pgml files are installed
ls /usr/share/postgresql/*/extension/pgml*
```

### Step 2: Database-Level Activation

**After system installation**, enable the extension in your database:

```sql
-- Connect to your database
\c notes_dwh

-- Enable pgml extension
CREATE EXTENSION IF NOT EXISTS pgml;

-- Verify installation
SELECT * FROM pg_extension WHERE extname = 'pgml';
SELECT pgml.version();
```

**Expected output**:

```
 extname | extversion
---------+------------
 pgml    | 2.8.0      (or similar version)
```

### Step 3: Verify Full Installation

```sql
-- Core sanity checks (pgml 2.10+ — older docs sometimes used pgml.available_algorithms(), which
-- is not present in current extension builds; algorithms are passed by name to pgml.train().)
SELECT pgml.version();
SELECT pgml.python_version();
-- Optional: ensure Python deps pgml expects are importable
SELECT pgml.validate_python_dependencies();
```

If you see errors, the system-level installation or Python packages may be incomplete.

**Algorithms**: see upstream supervised-learning docs and examples (e.g. `xgboost`, `lightgbm`,
`linear`, `random_forest`) rather than a SQL `available_algorithms()` helper.

## Setup Steps

### Step 0: Install pgml (System Level) ⚠️ REQUIRED FIRST

**This is NOT just SQL - you must install pgml at the OS level first:**

⚠️ **pgml is NOT available as a standard apt package**. Use the automated script or compile from
source.

```bash
# Check PostgreSQL version (must be 14+)
psql -d notes_dwh -c "SELECT version();"

# Option 1: Use automated installation script (RECOMMENDED for existing databases)
cd sql/dwh/ml
sudo ./install_pgml.sh

# Option 2: Compile from source manually (see Installation section above)

# Verify installation (after compiling from source)
ls /usr/share/postgresql/*/extension/pgml*
```

### Step 1: Check Prerequisites

**Before training, verify that required tables exist and have data:**

```bash
# Check prerequisites (core tables, datamarts, training data)
psql -d notes_dwh -f sql/dwh/ml/ml_00_check_prerequisites.sql
```

**What you need:**

- ✅ **Required**: `dwh.facts`, `dwh.dimension_days`, `dwh.dimension_applications`
- ⚠️ **Recommended**: `dwh.datamartCountries`, `dwh.datamartUsers` (for better features)
- ⚠️ **Recommended**: `dwh.v_note_hashtag_features` (for hashtag features)

**Note**: You can train **without datamarts** (they use LEFT JOIN with default values), but accuracy
will be lower. Datamarts are automatically populated by ETL, but may take time to fully populate
(especially `datamartUsers` which processes incrementally).

### Step 2: Enable Extension in Database

```sql
-- Connect to database
\c notes_dwh

-- Enable pgml extension (this is the SQL part)
CREATE EXTENSION IF NOT EXISTS pgml;

-- Verify
SELECT pgml.version();
```

### Step 3: Create Feature Views

```bash
psql -d notes_dwh -f sql/dwh/ml/ml_01_setupPgML.sql
```

This creates:

- `dwh.v_note_ml_training_features`: Features + target variables for training
- `dwh.v_note_ml_prediction_features`: Features for new notes (no targets)

**Note**: The views use `LEFT JOIN` with `COALESCE`, so they work even if datamarts are empty (using
default values of 0).

### Step 4: Train Models

```bash
psql -d notes_dwh -f sql/dwh/ml/ml_02_trainPgMLModels.sql
```

**⚠️ Training takes time** (several minutes to hours depending on data size):

- This trains three hierarchical models:
  1. **Main Category** (2 classes): `contributes_with_change` vs `doesnt_contribute`
  2. **Specific Type** (18+ classes): `adds_to_map`, `modifies_map`, `personal_data`, etc.
  3. **Action Recommendation** (3 classes): `process`, `close`, `needs_more_data`

**Monitor training**:

```sql
-- Check training status
SELECT * FROM pgml.training_runs ORDER BY created_at DESC LIMIT 5;

-- Check deployed models
SELECT * FROM pgml.deployed_models WHERE project_name LIKE 'note_classification%';
```

### Step 5: Make Predictions

```bash
psql -d notes_dwh -f sql/dwh/ml/ml_03_predictWithPgML.sql
```

Or use the helper function:

```sql
-- Classify a single note
SELECT * FROM dwh.predict_note_category_pgml(12345);

-- Classify new notes in batch
CALL dwh.classify_new_notes_pgml(1000);
```

## Architecture

### Feature Engineering

Features are derived from existing analysis patterns:

1. **Text Features**: `comment_length`, `has_url`, `has_mention`, `hashtag_number`
2. **Hashtag Features**: From `dwh.v_note_hashtag_features` (see
   `ml_00_analyzeHashtagsForClassification.sql`)
3. **Application Features**: `is_assisted_app`, `is_mobile_app`
4. **Geographic Features**: `country_resolution_rate`, `country_notes_health_score`
5. **User Features**: `user_response_time`, `user_total_notes`, `user_experience_level` (1–7, from
   dimension_experience_levels), `user_contributor_type_id` (contributor type from datamart)
6. **Temporal Features**: `day_of_week`, `hour_of_day`, `month`
7. **Age Features**: `days_open`

**Total**: ~24 features (all informed by existing analysis)

### Model Hierarchy

```
Level 1: Main Category (2 classes)
  ↓
Level 2: Specific Type (18+ classes)
  ↓
Level 3: Action Recommendation (3 classes)
```

Each level is a separate model, allowing:

- Independent optimization
- Different algorithms per level
- Easier debugging and interpretation

## Usage Examples

### Check Training Data

```sql
SELECT
  COUNT(*) as total_notes,
  COUNT(DISTINCT main_category) as categories,
  COUNT(DISTINCT specific_type) as types
FROM dwh.v_note_ml_training_features
WHERE main_category IS NOT NULL;
```

### Train a Model

```sql
-- This will take several minutes
SELECT * FROM pgml.train(
  project_name => 'note_classification_main_category',
  task => 'classification',
  relation_name => 'dwh.v_note_ml_training_features',
  y_column_name => 'main_category',
  algorithm => 'xgboost'
);
```

**Training without datamarts**: If datamarts are not populated, the model will still train but will
use default values (0) for geographic and user features. You can re-train later when datamarts are
populated for better accuracy.

## Training Time and Performance

### Expected Training Times

Training time depends on:

- **Data size**: Number of training samples
- **Model complexity**: Number of classes and features
- **Hardware**: CPU and memory available

**Estimated times** (for typical dataset sizes):

| Model                 | Classes | Training Samples | Estimated Time |
| --------------------- | ------- | ---------------- | -------------- |
| Main Category         | 2       | 10,000           | 5-15 minutes   |
| Main Category         | 2       | 100,000          | 30-60 minutes  |
| Specific Type         | 18+     | 10,000           | 15-30 minutes  |
| Specific Type         | 18+     | 100,000          | 60-120 minutes |
| Action Recommendation | 3       | 10,000           | 10-20 minutes  |
| Action Recommendation | 3       | 100,000          | 45-90 minutes  |

**Total for all 3 models**: 30-120 minutes (depending on data size)

### Performance Considerations

- **CPU Usage**: Training is CPU-intensive. May slow down other database operations.
- **Memory Usage**: XGBoost requires significant memory (2-4GB for 100K samples).
- **Database Load**: Training reads from `dwh.v_note_ml_training_features` view.
- **Best Practice**: Run training during low-traffic periods or schedule it separately.

## Model Retraining Strategy

### When to Retrain

Models should be retrained when:

1. **New Data Available**: 10%+ new training samples since last training
2. **Time-Based**: Monthly or quarterly (even without much new data)
3. **Performance Degradation**: Model accuracy drops significantly
4. **Data Drift**: Distribution of note types changes over time
5. **After Datamart Updates**: When datamarts are fully populated (better features)

### Retraining Frequency Recommendations

| Frequency                  | Use Case                                        | Command                            |
| -------------------------- | ----------------------------------------------- | ---------------------------------- |
| **Monthly**                | Recommended for production                      | `bin/dwh/ml_retrain.sh` (via cron) |
| **Quarterly**              | Stable systems with slow data growth            | `bin/dwh/ml_retrain.sh` (via cron) |
| **On-Demand**              | After major data updates or when accuracy drops | `bin/dwh/ml_retrain.sh --force`    |
| **After Initial Training** | When datamarts are first populated              | `bin/dwh/ml_retrain.sh --force`    |

### Automated Training/Retraining

The script is **fully automatic** - it detects system state and decides what to do:

**Decision Logic**:

1. **No data** → Do nothing (exit silently)
2. **Facts + dimensions ready** → Initial training (basic features)
3. **Datamarts populated** → Full training (all features)
4. **Models exist** → Retraining (if 10%+ new data or 30+ days old)

**Usage**:

```bash
# Just run it - no options needed!
bin/dwh/ml_retrain.sh
```

**Cron Example** (monthly - recommended):

```bash
# Intelligent ML training/retraining (1st day of month at 2 AM)
# Script automatically decides what to do based on system state
0 2 1 * * /path/to/OSM-Notes-Analytics/bin/dwh/ml_retrain.sh >> /var/log/ml-retrain.log 2>&1
```

**What it does automatically**:

- ✅ Checks if enough data exists (exits silently if not)
- ✅ Detects if datamarts are populated
- ✅ Checks if models already exist
- ✅ Decides between initial training vs retraining
- ✅ Only retrains if significant new data (10%+) or 30+ days old

## ETL Integration

### Current Status: NOT Integrated

**⚠️ Important**: ML training is **NOT currently integrated** into the ETL workflow. This is
intentional:

- **Training is expensive**: Takes 30-120 minutes, CPU-intensive
- **Not needed frequently**: Models don't need retraining every ETL run
- **Separate concern**: Training vs. prediction are different processes
- **Flexible scheduling**: Can run training independently when convenient

### Integration Strategy

**Recommended approach**:

1. **Initial Training**: Manual (one-time setup)

   ```bash
   psql -d notes_dwh -f sql/dwh/ml/ml_02_trainPgMLModels.sql
   ```

2. **Predictions**: Can be integrated into ETL (fast, uses trained models)

   ```sql
   -- In ETL, after processing new notes:
   CALL dwh.classify_new_notes_pgml(1000);
   ```

3. **Retraining**: Automated via cron (monthly/quarterly)
   ```bash
   # Via cron (see cron.example)
   0 2 1 * * /path/to/bin/dwh/ml_retrain.sh
   ```

### Future Integration Options

If you want to integrate training into ETL (not recommended for frequent runs):

```bash
# Add to ETL.sh (after datamart updates):
if [[ "${RETRAIN_ML:-false}" == "true" ]]; then
  __logi "Retraining ML models..."
  "${PROJECT_ROOT}/bin/dwh/ml_retrain.sh"
fi
```

**Usage**:

```bash
RETRAIN_ML=true ./bin/dwh/ETL.sh  # Only when you want to retrain
```

**Note**: This is optional and not recommended for regular ETL runs due to training time.

### Make Predictions (How to Consume)

#### Option 1: Direct SQL Query

```sql
-- Single note prediction
SELECT
  id_note,
  pgml.predict(
    'note_classification_main_category',
    ARRAY[
      comment_length, has_url_int, has_mention_int, hashtag_number,
      total_comments_on_note, hashtag_count, has_fire_keyword,
      has_air_keyword, has_access_keyword, has_campaign_keyword,
      has_fix_keyword, is_assisted_app, is_mobile_app,
      country_resolution_rate, country_avg_resolution_days,
      country_notes_health_score, user_response_time,
      user_total_notes, user_experience_level,
      day_of_week, hour_of_day, month, days_open
    ]
  )::VARCHAR as predicted_category
FROM dwh.v_note_ml_prediction_features
WHERE id_note = 12345;
```

#### Option 2: Using Helper Function

```sql
-- Simpler interface
SELECT * FROM dwh.predict_note_category_pgml(12345);
```

#### Option 3: Batch Classification

```sql
-- Classify all new notes
CALL dwh.classify_new_notes_pgml(1000);
```

#### Option 4: In Dashboard Queries

```sql
-- Get high-priority notes for dashboard
SELECT
  f.id_note,
  f.opened_dimension_id_date,
  c.country_name_en,
  pgml.predict('note_classification_main_category', ...)::VARCHAR as category,
  pgml.predict('note_classification_action', ...)::VARCHAR as action
FROM dwh.facts f
JOIN dwh.v_note_ml_prediction_features pf ON f.id_note = pf.id_note
JOIN dwh.dimension_countries c ON f.dimension_id_country = c.dimension_country_id
WHERE pgml.predict('note_classification_action', ...)::VARCHAR = 'process'
ORDER BY f.opened_dimension_id_date DESC;
```

### View Model Performance

```sql
SELECT
  project_name,
  algorithm,
  metrics->>'accuracy' as accuracy,
  metrics->>'f1' as f1_score
FROM pgml.deployed_models
WHERE project_name LIKE 'note_classification%';
```

### Get Predictions with Confidence

```sql
-- Get prediction probabilities
SELECT
  id_note,
  pgml.predict('note_classification_main_category', ...)::VARCHAR as prediction,
  pgml.predict_proba('note_classification_main_category', ...) as probabilities
FROM dwh.v_note_ml_prediction_features
WHERE id_note = 12345;
```

## Integration with Existing System

### Classification Table

Predictions are stored in `dwh.note_type_classifications` (see `ML_Implementation_Plan.md`):

```sql
SELECT
  id_note,
  main_category,
  specific_type,
  recommended_action,
  priority_score,
  type_method  -- Will be 'ml_based'
FROM dwh.note_type_classifications
WHERE type_method = 'ml_based';
```

### ETL Integration

Add to ETL pipeline:

```bash
# After datamart updates
psql -d notes_dwh -c "
  INSERT INTO dwh.note_type_classifications (...)
  SELECT ... FROM dwh.v_note_ml_prediction_features
  WHERE id_note NOT IN (SELECT id_note FROM dwh.note_type_classifications);
"
```

## Model Maintenance

### Retrain Models

Models should be retrained periodically (monthly/quarterly):

```sql
-- Retrain with latest data
SELECT * FROM pgml.train(
  project_name => 'note_classification_main_category',
  ...
);
```

### Monitor Performance

```sql
-- Track accuracy over time
SELECT
  created_at,
  metrics->>'accuracy' as accuracy
FROM pgml.deployed_models
WHERE project_name = 'note_classification_main_category'
ORDER BY created_at DESC;
```

### Compare Models

```sql
-- Compare different algorithms
SELECT
  algorithm,
  AVG((metrics->>'accuracy')::numeric) as avg_accuracy
FROM pgml.deployed_models
WHERE project_name = 'note_classification_main_category'
GROUP BY algorithm;
```

## Advantages of pgml Approach

1. **No External Services**: Everything in PostgreSQL
2. **SQL-Native**: No Python/API calls needed
3. **Real-time**: Fast predictions directly in queries
4. **Integrated**: Uses existing DWH infrastructure
5. **Simple Deployment**: Just install extension
6. **Version Control**: Models tracked in database

## Limitations

1. **Limited Algorithms**: pgml supports fewer algorithms than scikit-learn
2. **Text Features**: Basic text features only (no advanced NLP)
3. **Model Size**: Large models may impact database performance
4. **Training Time**: Training happens in database (may slow down other queries)

## Next Steps

1. **Enhance Features**: Add more text features (word counts, semantic patterns)
2. **Tune Hyperparameters**: Optimize model performance
3. **Add Text Embeddings**: Use pgml's text embedding features
4. **Hybrid Approach**: Combine pgml with rule-based classification
5. **Monitor Performance**: Track accuracy and update models regularly

## Related Documentation

- [ML Implementation Plan](../docs/ML_Implementation_Plan.md): Overall ML strategy
- [Note Categorization](../docs/Note_Categorization.md): Classification system
- [External Classification Strategies](../docs/External_Classification_Strategies.md):
  Keyword/hashtag approaches
- [Hashtag Analysis](ml_00_analyzeHashtagsForClassification.sql): Hashtag feature extraction

## References

- **pgml Documentation**: https://postgresml.org/
- **pgml GitHub**: https://github.com/postgresml/postgresml
- **pgml Examples**: https://postgresml.org/docs/guides/

---

**Status**: Implementation Ready  
**Dependencies**: pgml extension, training data, feature views
