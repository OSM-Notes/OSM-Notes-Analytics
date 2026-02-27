# Test Scripts Documentation

## Overview

This document describes the test scripts in the `tests/` directory.

## Scripts Comparison

| Script                   | Purpose                                   | Requires DB? | Executes                                   | Output                |
| ------------------------ | ----------------------------------------- | ------------ | ------------------------------------------ | --------------------- |
| **run_all_tests.sh**     | Master test runner - runs ALL test suites | Yes          | run_quality_tests.sh + run_dwh_tests.sh    | Comprehensive report  |
| **run_quality_tests.sh** | Code quality validation (NO database)     | No           | shellcheck, shfmt, file validation         | Quality check results |
| **run_dwh_tests.sh**     | DWH/ETL/Datamart tests (with database)    | Yes          | run_mock_etl.sh + BATS tests               | Test results          |
| **run_mock_etl.sh**      | Populate test DB with mock data           | Yes          | generate_mock_staging_data.sql + DWH setup | Test data loaded      |

## Detailed Description

### run_all_tests.sh

**Purpose**: Orchestrates all test suites **Execution**:

1. Runs quality tests (code validation)
2. Runs DWH tests (database + ETL)
3. Shows overall summary

**Usage**:

```bash
export TEST_DBNAME="osm_notes_analytics_test"
bash tests/run_all_tests.sh
```

**Output**: Overall pass/fail summary for all test suites

---

### run_quality_tests.sh

**Purpose**: Validates code quality without requiring database **What it checks**:

- ✅ Shellcheck (bash syntax validation)
- ✅ shfmt (code formatting)
- ✅ Trailing whitespace
- ✅ Shebangs
- ✅ TODO/FIXME comments

**Requires**: shellcheck, shfmt **Usage**:

```bash
bash tests/run_quality_tests.sh
```

**Output**: Quality validation results

---

### run_dwh_tests.sh

**Purpose**: Tests data warehouse, ETL, and Datamarts with real database **What it does**:

1. **Setup**: Runs `run_mock_etl.sh` to populate test database
2. **Tests**: Executes all BATS test files in:
   - `tests/unit/bash/*.bats` - Unit tests
   - `tests/integration/*.bats` - Integration tests

**Requires**: PostgreSQL database, BATS **Usage**:

```bash
export TEST_DBNAME="osm_notes_analytics_test"
bash tests/run_dwh_tests.sh
```

**Output**: Individual test results and summary

---

### run_mock_etl.sh

**Purpose**: Populates test database with mock data **What it does**:

1. Generates mock staging data
2. Creates DWH schema using ETL_20_createDWHTables.sql
3. Populates dimensions (users, countries, applications)
4. Inserts facts from staging data
5. Updates datamarts

**Requires**: PostgreSQL database **Usage**:

```bash
export TEST_DBNAME="osm_notes_analytics_test"
bash tests/run_mock_etl.sh
```

**Output**: Data population summary

---

## Test Execution Flow

```
User runs: bash tests/run_all_tests.sh
    │
    ├─→ run_quality_tests.sh (no DB)
    │    ├─→ shellcheck
    │    ├─→ shfmt
    │    └─→ file validation
    │
    └─→ run_dwh_tests.sh (with DB)
         │
         ├─→ run_mock_etl.sh (data setup)
         │    ├─→ generate_mock_staging_data.sql
         │    ├─→ ETL_20_createDWHTables.sql
         │    └─→ Populate dimensions & facts
         │
         └─→ Execute BATS tests
              ├─→ tests/unit/bash/*.bats
              └─→ tests/integration/*.bats
```

## Available Tests

### Unit Tests (tests/unit/bash/)

- `datamartGlobal_integration.test.bats` - Global datamart tests
- `datamartCountries_integration.test.bats` - Country datamart tests
- `datamartUsers_integration.test.bats` - User datamart tests
- `datamart_last_year_activity.test.bats` - last_year_activity 371-char string and LPAD padding
- `ETL_enhanced.test.bats` - ETL enhancements
- `datamart_resolution_metrics.test.bats` - Resolution metrics

### Integration Tests (tests/integration/)

- `ETL_enhanced_integration.test.bats` - ETL integration
- `datamart_enhanced_integration.test.bats` - Datamart integration

## Quick Reference

```bash
# Run all tests
bash tests/run_all_tests.sh

# Run only quality checks (fast, no DB)
bash tests/run_quality_tests.sh

# Run only DWH tests (slow, needs DB)
export TEST_DBNAME="osm_notes_analytics_test"
bash tests/run_dwh_tests.sh

# Just populate test data
export TEST_DBNAME="osm_notes_analytics_test"
bash tests/run_mock_etl.sh
```

## Configuration

Set database in `tests/properties.sh` or environment variables:

- `TEST_DBNAME` - Database name (default: dwh)
- `TEST_DBUSER` - Database user
- `TEST_DBHOST` - Database host
- `TEST_DBPORT` - Database port
