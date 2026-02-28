# Machine Learning with pgml

This directory contains SQL scripts for implementing Machine Learning classification of OSM notes
using **pgml** (PostgreSQL Machine Learning).

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
# Add pgml to shared_preload_libraries
psql -d postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements,pgml';"
# Or if pg_stat_statements is not installed:
psql -d postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pgml';"

# IMPORTANT: Check the configuration file to ensure correct format
sudo cat /var/lib/postgresql/14/main/postgresql.auto.conf | grep shared_preload_libraries
# Should show: shared_preload_libraries = 'pg_stat_statements,pgml'
# NOT: shared_preload_libraries = '"pg_stat_statements,pgml"'

# If format is wrong, fix it:
sudo nano /var/lib/postgresql/14/main/postgresql.auto.conf
# Change: shared_preload_libraries = '"pg_stat_statements,pgml"'
# To:     shared_preload_libraries = 'pg_stat_statements,pgml'

# Restart PostgreSQL
sudo systemctl restart postgresql@14-main
```

3. **Install Python packages for the specific Python version** (see troubleshooting section below):

```bash
# pgml typically uses Python 3.10, check the error message to confirm
# Install all required packages:
sudo python3.10 -m pip install --break-system-packages --ignore-installed --no-cache-dir \
  numpy scipy xgboost lightgbm scikit-learn

# Verify installation
sudo -u postgres python3.10 -c "import numpy, scipy, xgboost, lightgbm, sklearn; print('OK')"
```

4. **Enable extension in your database**:

```bash
# Use the PostgreSQL 14 binary directly (if psql defaults to another version)
sudo -u postgres /usr/lib/postgresql/14/bin/psql -d notes_dwh -c "CREATE EXTENSION IF NOT EXISTS pgml;"

# Verify
sudo -u postgres /usr/lib/postgresql/14/bin/psql -d notes_dwh -c "SELECT pgml.version();"
```

**Note**: The `apt-get` packages may not be sufficient because:

- They may be compiled for a different Python version than what pgml uses
- `lightgbm` and `scikit-learn` are not available in standard apt repositories
- You MUST install them with pip for the specific Python version (usually 3.10)

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
# First, identify which Python version pgml is using (check the error message)
# If pgml says "Python version: 3.10.12", you need Python 3.10 packages
# If pgml says "Python version: 3.11.x", you need Python 3.11 packages

# CRITICAL: The packages installed via apt may be compiled for a different Python version
# You MUST install them with pip for the specific Python version pgml is using

# For Python 3.10 (most common case):
# First, ensure pip is available for Python 3.10
sudo python3.10 -m ensurepip --upgrade 2>/dev/null || \
sudo apt-get install python3.10-distutils python3.10-venv

# Install packages specifically for Python 3.10 (all required packages)
sudo python3.10 -m pip install --break-system-packages --ignore-installed --no-cache-dir \
  numpy scipy xgboost lightgbm scikit-learn

# Verify installation for Python 3.10
sudo -u postgres python3.10 -c "import numpy; print('numpy:', numpy.__version__)"
sudo -u postgres python3.10 -c "import scipy; print('scipy:', scipy.__version__)"
sudo -u postgres python3.10 -c "import xgboost; print('xgboost:', xgboost.__version__)"
sudo -u postgres python3.10 -c "import lightgbm; print('lightgbm:', lightgbm.__version__)"
sudo -u postgres python3.10 -c "import sklearn; print('sklearn:', sklearn.__version__)"

# If all work, try importing all together
sudo -u postgres python3.10 -c "import numpy, scipy, xgboost, lightgbm, sklearn; print('All packages available for Python 3.10')"
```

**Important**: If you get errors about `numpy.core._multiarray_umath` or "numpy source directory",
it means the numpy package is not properly installed for that Python version. The apt packages
(`python3-numpy`) are compiled for the default Python version (usually 3.12), but pgml might be
using Python 3.10. You MUST install with pip for the specific Python version.

3. **If you get numpy source directory error**, check PYTHONPATH in PostgreSQL environment:

```bash
# Check PostgreSQL's environment
sudo -u postgres env | grep PYTHONPATH

# Check systemd service file for PostgreSQL
sudo systemctl show postgresql@14-main.service | grep Environment
# Or check the main service
sudo systemctl show postgresql.service | grep Environment

# If PYTHONPATH includes numpy source directories, you need to fix it:
# Option 1: Edit PostgreSQL systemd service override
sudo systemctl edit postgresql@14-main.service
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
# Check for numpy source directories in /tmp (common build location)
find /tmp -name "numpy" -type d 2>/dev/null | head -5

# Check if there's a numpy source directory in the pgml build directory
find /tmp/pgml-build -name "numpy" -type d 2>/dev/null | head -5

# Remove any numpy source directories found
find /tmp -name "numpy" -type d -path "*/pgml-build/*" -exec rm -rf {} + 2>/dev/null || true
find /tmp -name "numpy" -type d -path "*/target/*" -exec rm -rf {} + 2>/dev/null || true

# Verify the systemd override was applied
sudo systemctl show postgresql@14-main.service | grep -i environment

# If PYTHONPATH is still set, try unsetting it explicitly
sudo systemctl edit postgresql@14-main.service
# Make sure it contains:
# [Service]
# Environment="PYTHONPATH="
# Environment="PYTHONHOME="

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart postgresql
```

**If the problem persists**, the issue might be that pgml was compiled with a different Python
version. The error message shows which Python version pgml is using (e.g., "Python version:
3.10.12").

**Solution**: Recompile pgml with the correct Python version, or install Python packages for the
version pgml is using:

```bash
# 1. Check what Python version pgml is using (from the error message)
# If it says "Python version: 3.10.12", you need Python 3.10

# 2. Install Python 3.10 if not available
sudo apt-get install python3.10 python3.10-dev python3.10-distutils

# 3. Install packages for Python 3.10 specifically
sudo python3.10 -m pip install --break-system-packages numpy scipy xgboost

# 4. Verify packages are accessible
sudo -u postgres python3.10 -c "import numpy, scipy, xgboost; print('OK')"

# 5. Restart PostgreSQL
sudo systemctl restart postgresql

# 6. Try creating extension again
psql -d notes_dwh -c 'CREATE EXTENSION IF NOT EXISTS pgml;'
```

**Alternative**: If Python 3.10 is not available, you may need to recompile pgml with Python 3.11:

```bash
# Re-run the installation script, which will recompile with current Python
cd sql/dwh/ml
sudo ./install_pgml.sh
```

**Important Note**: If pgml was compiled with Python 3.10 but your system has Python 3.11, you have
two options:

1. **Install Python 3.10 and packages for it** (if Python 3.10 is available):

```bash
# Check if Python 3.10 is available
python3.10 --version 2>/dev/null || echo "Python 3.10 not found"

# If available, install packages for Python 3.10 (all required packages)
sudo python3.10 -m pip install --break-system-packages --ignore-installed --no-cache-dir \
  numpy scipy xgboost lightgbm scikit-learn

# Verify
sudo -u postgres python3.10 -c "import numpy, scipy, xgboost, lightgbm, sklearn; print('OK')"
```

2. **Force pgml to use Python 3.11** by ensuring Python 3.11 is the default during compilation:

```bash
# Make sure Python 3.11 is the default
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1
sudo update-alternatives --set python3 /usr/bin/python3.11

# Verify
python3 --version  # Should show 3.11.x

# Recompile pgml
cd sql/dwh/ml
sudo ./install_pgml.sh
```

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
- Build tools (make, gcc, etc.)

```bash
# Install build dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  postgresql-server-dev-15 \
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
ls /usr/share/postgresql/15/extension/pgml*
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
-- Test pgml functions
SELECT pgml.version();
SELECT pgml.available_algorithms();
```

If you see errors, the system-level installation may be missing.

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
