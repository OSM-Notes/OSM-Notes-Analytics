---
title: "Testing Guide - OSM-Notes-Analytics"
description:
  "Comprehensive guide covering all aspects of testing in the OSM-Notes-Analytics project, including
  197+ tests organized into unit, integration, and quality validation tests"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "testing"
  - "guide"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Testing Guide - OSM-Notes-Analytics

## Overview

This comprehensive guide covers all aspects of testing in the OSM-Notes-Analytics project. The test
suite includes **197+ tests** organized into unit tests, integration tests, and quality validation
tests.

**Last Updated**: 2025-12-14  
**Test Framework**: BATS (Bash Automated Testing System)  
**Total Tests**: 197+ tests across 18 test files (includes new performance monitoring tests)

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Test Organization](#test-organization)
3. [Running Tests](#running-tests)
4. [Test Suites](#test-suites)
5. [Writing Tests](#writing-tests)
6. [Debugging Tests](#debugging-tests)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)
9. [CI/CD Integration](#cicd-integration)

---

## Quick Start

### Prerequisites

```bash
# Install BATS (if not already installed)
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# Verify installation
bats --version
```

### Run All Tests

```bash
# From project root
./tests/run_all_tests.sh
```

### Run Specific Test Suites

```bash
# Quality tests only (no database required, fast)
./tests/run_quality_tests.sh

# DWH tests only (requires database)
export DBNAME="your_test_db"
./tests/run_dwh_tests.sh

# Run a specific test file
bats tests/unit/bash/datamart_high_priority_metrics.test.bats
```

---

## Test Organization

### Directory Structure

```mermaid
graph TD
    ROOT[tests/]

    subgraph Unit["unit/ Unit tests"]
        subgraph Bash["bash/ Bash script unit tests 15 files"]
            B1[ETL_enhanced.test.bats]
            B2[ETL_integration.test.bats]
            B3[ETL_internal_functions.test.bats]
            B4[datamartCountries_integration.test.bats]
            B5[datamartUsers_integration.test.bats]
            B6[datamartGlobal_integration.test.bats]
            B7[datamart_full_integration.test.bats]
            B8[datamart_resolution_metrics.test.bats]
            B9[datamartUsers_resolution_metrics.test.bats]
            B10[datamart_application_statistics.test.bats]
            B11[datamart_content_quality.test.bats]
            B12[datamart_community_health.test.bats]
            B13[datamart_high_priority_metrics.test.bats]
            B14[hybrid_strategy_copy_fdw.test.bats]
        end

        subgraph SQL["sql/ SQL unit tests 3 files"]
            S1[dwh_cleanup.test.sql]
            S2[dwh_dimensions_enhanced.test.sql]
            S3[dwh_functions_enhanced.test.sql]
        end
    end

    subgraph Integration["integration/ Integration tests 3 files"]
        I1[ETL_enhanced_integration.test.bats]
        I2[datamart_enhanced_integration.test.bats]
        I3[resolution_temporal_metrics.test.bats]
    end

    subgraph Performance["performance/ Performance benchmarks"]
        P1[run_benchmark.sh]
        P2[README.md]
    end

    subgraph SQLSetup["sql/ Test data setup"]
        SQL1[setup_base_tables_data.sql]
        SQL2[setup_test_data.sql]
        SQL3[validate_resolution_temporal_metrics.sql]
    end

    ROOT --> Unit
    ROOT --> Integration
    ROOT --> Performance
    ROOT --> SQLSetup
    ROOT --> PROP[properties.sh<br/>Test configuration]
    ROOT --> HELPER[test_helper.bash<br/>Common test utilities]
    ROOT --> RUN_ALL[run_all_tests.sh<br/>Master test runner]
    ROOT --> QUALITY[run_quality_tests.sh<br/>Quality validation]
    ROOT --> DWH[run_dwh_tests.sh<br/>DWH/ETL tests]
    ROOT --> MOCK[run_mock_etl.sh<br/>Mock data setup]

    Unit --> Bash
    Unit --> SQL

    style ROOT fill:#90EE90
    style Unit fill:#E0F6FF
    style Integration fill:#FFFFE0
    style Performance fill:#FFE4B5
    style SQLSetup fill:#DDA0DD
```

### Test Categories

#### 1. Unit Tests (`tests/unit/`)

**Purpose**: Test individual components in isolation

**Bash Unit Tests** (15 files, ~180+ tests):

- **ETL Tests**: `ETL_enhanced.test.bats`, `ETL_integration.test.bats`,
  `ETL_internal_functions.test.bats`
  - ETL script functions
  - ETL database integration
  - Internal ETL helper functions
- **Datamart Tests**:
  - `datamartCountries_integration.test.bats` - Country datamart validation
  - `datamartUsers_integration.test.bats` - User datamart validation
  - `datamartGlobal_integration.test.bats` - Global datamart validation
  - `datamart_full_integration.test.bats` - Complete datamart workflow
- **Metric Tests**:
  - `datamart_resolution_metrics.test.bats` - Resolution time metrics
  - `datamartUsers_resolution_metrics.test.bats` - User resolution metrics
  - `datamart_application_statistics.test.bats` - Application usage metrics
  - `datamart_content_quality.test.bats` - Content quality metrics
  - `datamart_community_health.test.bats` - Community health metrics
  - `datamart_high_priority_metrics.test.bats` - High priority metrics (26 tests)
- **Hybrid Strategy Tests**:
  - `hybrid_strategy_copy_fdw.test.bats` - Hybrid ETL strategy

**SQL Unit Tests** (3 files):

- `dwh_cleanup.test.sql` - Cleanup procedures
- `dwh_dimensions_enhanced.test.sql` - Dimension table validation
- `dwh_functions_enhanced.test.sql` - SQL function validation

#### 2. Integration Tests (`tests/integration/`)

**Purpose**: Test end-to-end workflows

- `ETL_enhanced_integration.test.bats` - Full ETL workflow
- `datamart_enhanced_integration.test.bats` - Complete datamart workflow
- `resolution_temporal_metrics.test.bats` - Temporal resolution metrics

#### 3. Quality Tests

**Purpose**: Code quality validation (no database required)

- Shell script syntax (shellcheck)
- Code formatting (shfmt)
- File structure validation
- Configuration validation

---

## Running Tests

### Master Test Runner

```bash
# Run all test suites (quality + DWH)
./tests/run_all_tests.sh
```

**What it does**:

1. Runs quality tests (fast, no database)
2. Runs DWH tests (slower, requires database)
3. Shows overall summary

### Quality Tests (No Database)

```bash
# Fast validation tests (< 1 minute)
./tests/run_quality_tests.sh
```

**Checks**:

- ✅ Shellcheck (Bash syntax validation)
- ✅ shfmt (code formatting)
- ✅ Trailing whitespace
- ✅ Shebangs
- ✅ TODO/FIXME comments

### DWH Tests (Requires Database)

```bash
# Configure test database
export DBNAME="osm_notes_analytics_test"

# Run DWH tests
./tests/run_dwh_tests.sh
```

**What it does**:

1. Sets up test database with mock data (`run_mock_etl.sh`)
2. Executes all BATS test files:
   - `tests/unit/bash/*.test.bats` (15 files, includes performance monitoring tests)
   - `tests/integration/*.test.bats` (3 files)
3. Shows test results and summary

### Running Individual Test Files

```bash
# Run a specific test file
bats tests/unit/bash/datamart_high_priority_metrics.test.bats

# Run with verbose output (show output of passing tests)
bats --show-output-of-passing-tests tests/unit/bash/ETL_enhanced.test.bats

# Run a specific test by name
bats --filter "test name pattern" tests/unit/bash/datamart_high_priority_metrics.test.bats
```

### Running Tests by Category

```bash
# All unit tests
bats tests/unit/bash/*.test.bats

# All integration tests
bats tests/integration/*.test.bats

# All ETL-related tests
bats tests/unit/bash/ETL_*.test.bats

# All datamart-related tests
bats tests/unit/bash/datamart*.test.bats
```

---

## Test Suites

### Suite 1: Quality Tests

**Location**: `tests/run_quality_tests.sh`  
**Duration**: < 1 minute  
**Database Required**: No

**Purpose**: Validate code quality and syntax

**What it checks**:

- Shell script syntax errors (shellcheck)
- Code formatting consistency (shfmt)
- File structure and naming
- Configuration file validity

**Usage**:

```bash
./tests/run_quality_tests.sh
```

### Suite 2: DWH Tests

**Location**: `tests/run_dwh_tests.sh`  
**Duration**: 5-10 minutes  
**Database Required**: Yes

**Purpose**: Test data warehouse, ETL, and datamarts

**What it tests**:

- ETL process execution
- Dimension table population
- Fact table population
- Datamart creation and updates
- Data integrity constraints
- Metric calculations

**Prerequisites**:

```bash
# Create test database
createdb osm_notes_analytics_test
psql -d osm_notes_analytics_test -c "CREATE EXTENSION postgis;"

# Configure in tests/properties.sh or export
export DBNAME="osm_notes_analytics_test"
```

**Usage**:

```bash
export DBNAME="osm_notes_analytics_test"
./tests/run_dwh_tests.sh
```

### Suite 3: All Tests

**Location**: `tests/run_all_tests.sh`  
**Duration**: 6-11 minutes  
**Database Required**: Yes (for DWH tests)

**Purpose**: Run complete test suite

**What it does**:

1. Executes quality tests
2. Executes DWH tests
3. Shows comprehensive summary

**Usage**:

```bash
export DBNAME="osm_notes_analytics_test"
./tests/run_all_tests.sh
```

---

## Writing Tests

### BATS Test Structure

```bash
#!/usr/bin/env bats

# Load test helper functions
load test_helper

# Setup function (runs before each test)
setup() {
  # Setup test database if needed
  setup_test_database
}

# Teardown function (runs after each test)
teardown() {
  # Cleanup if needed
  # Usually handled by test_helper
}

# Test case
@test "Description of what is being tested" {
  # Arrange
  local expected_value=42

  # Act
  run psql -d "${DBNAME}" -tAc "SELECT COUNT(*) FROM dwh.facts"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" -gt 0 ]]
}
```

### Test Helper Functions

The `test_helper.bash` provides common utilities:

```bash
# Setup test database with base data
setup_test_database()

# Skip test if database not configured
if [[ -z "${DBNAME:-}" ]]; then
  skip "No database configured"
fi

# Run command and check status
run psql -d "${DBNAME}" -c "SELECT 1"
[[ "${status}" -eq 0 ]]

# Check output
[[ "${output}" =~ "expected pattern" ]]
```

### Example: Testing a Metric

```bash
@test "Resolution rate should be between 0 and 100" {
  if [[ -z "${DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  # Check that all resolution rates are valid
  run psql -d "${DBNAME}" -tAc "
    SELECT COUNT(*)
    FROM dwh.datamartCountries
    WHERE resolution_rate IS NOT NULL
      AND (resolution_rate < 0 OR resolution_rate > 100);
  "

  [[ "${status}" -eq 0 ]]
  count="${output// /}"
  [[ "${count}" == "0" ]] || echo "All resolution rates should be 0-100"
}
```

### Example: Testing JSON Metrics

```bash
@test "Application usage trends should be valid JSON" {
  if [[ -z "${DBNAME:-}" ]]; then
    skip "No database configured"
  fi

  # Check JSON validity
  run psql -d "${DBNAME}" -tAc "
    SELECT COUNT(*)
    FROM dwh.datamartCountries
    WHERE application_usage_trends IS NOT NULL
      AND NOT (application_usage_trends::text ~ '^\\[.*\\]$');
  "

  [[ "${status}" -eq 0 ]]
  count="${output// /}"
  [[ "${count}" == "0" ]] || echo "All JSON should be valid arrays"
}
```

### Best Practices for Writing Tests

1. **Use descriptive test names**: Clearly describe what is being tested
2. **One assertion per test**: Focus each test on a single behavior
3. **Use setup/teardown**: Ensure clean state for each test
4. **Skip when appropriate**: Skip tests if prerequisites aren't met
5. **Test edge cases**: Include boundary conditions and error cases
6. **Keep tests independent**: Tests should not depend on execution order
7. **Use meaningful assertions**: Provide clear error messages

---

## Debugging Tests

### Verbose Output

```bash
# Run with verbose output (show output of passing tests)
bats --show-output-of-passing-tests tests/unit/bash/datamart_high_priority_metrics.test.bats

# Run with trace (shows each command)
bats --trace tests/unit/bash/ETL_enhanced.test.bats
```

### Running Single Test

```bash
# Run specific test by name pattern
bats --filter "resolution rate" tests/unit/bash/datamart_resolution_metrics.test.bats
```

### Debugging Failed Tests

1. **Check test output**: Look for specific error messages
2. **Run test in isolation**: Execute just the failing test
3. **Check database state**: Verify test data is loaded correctly
4. **Review test helper**: Check if setup functions are working
5. **Enable verbose mode**: Use `--show-output-of-passing-tests` or `--trace` flags

### Common Debugging Commands

```bash
# Check database connection
psql -d "${DBNAME}" -c "SELECT version();"

# Check if tables exist
psql -d "${DBNAME}" -c "\dt dwh.*"

# Check test data
psql -d "${DBNAME}" -c "SELECT COUNT(*) FROM dwh.facts;"

# Check specific metric
psql -d "${DBNAME}" -c "SELECT resolution_rate FROM dwh.datamartCountries LIMIT 5;"
```

### Test Logs

Test output is typically displayed in the terminal. For CI/CD, logs are captured in GitHub Actions.

---

## Troubleshooting

### Tests Fail with "Database does not exist"

**Solution**:

```bash
# Create test database
createdb osm_notes_analytics_test
psql -d osm_notes_analytics_test -c "CREATE EXTENSION postgis;"

# Configure in tests/properties.sh or export
export DBNAME="osm_notes_analytics_test"
```

### BATS Not Found

**Solution**:

```bash
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core

# Verify
bats --version
```

### Permission Denied Errors

**Solution**:

```bash
# Make scripts executable
chmod +x tests/run_*.sh
chmod +x tests/unit/bash/*.bats
```

### Database Connection Issues

**Solution**:

```bash
# Verify database exists and is accessible
psql -d osm_notes_analytics_test -c "SELECT version();"

# Check configuration
cat tests/properties.sh

# Test connection
psql -d "${DBNAME}" -c "SELECT 1;"
```

### Tests Timeout

**Solution**:

- Some tests have timeout protection (e.g., 30 seconds)
- If tests consistently timeout, check database performance
- Verify test data size is reasonable

### Test Data Issues

**Solution**:

```bash
# Reload test data
export DBNAME="osm_notes_analytics_test"
./tests/run_mock_etl.sh

# Or manually load
psql -d "${DBNAME}" -f tests/sql/setup_base_tables_data.sql
```

### Specific Test Failures

**Common Issues**:

1. **Column doesn't exist**: Run datamart update procedures
2. **JSON validation fails**: Check JSON structure in database
3. **Metric calculation errors**: Verify facts table has data
4. **Constraint violations**: Check test data integrity

---

## Best Practices

### For Developers

1. **Run tests before committing**: Use `./tests/run_all_tests.sh`
2. **Write tests for new features**: Follow TDD when possible
3. **Keep tests fast**: Avoid unnecessary database operations
4. **Use descriptive names**: Test names should explain what's tested
5. **Test error conditions**: Don't just test happy paths
6. **Keep tests independent**: Each test should be self-contained
7. **Use test helpers**: Leverage `test_helper.bash` functions

### Test Organization

1. **Unit tests**: Test individual components
2. **Integration tests**: Test workflows end-to-end
3. **Quality tests**: Validate code quality
4. **Performance tests**: Benchmark critical operations (manual)

### Test Data Management

1. **Use mock data**: `run_mock_etl.sh` provides test data
2. **Keep data minimal**: Only include what's needed for tests
3. **Clean up**: Tests should clean up after themselves
4. **Isolate data**: Each test should use independent data when possible

---

## CI/CD Integration

### GitHub Actions Workflows

#### 1. Quality Checks (`.github/workflows/quality-checks.yml`)

**Triggers**: Every push and pull request  
**Duration**: ~1 minute  
**What it does**:

- Runs `run_quality_tests.sh`
- Validates code quality
- No database required

#### 2. Tests (`.github/workflows/tests.yml`)

**Triggers**: Push to main branch  
**Duration**: ~10 minutes  
**What it does**:

- Sets up PostgreSQL database
- Runs `run_all_tests.sh`
- Executes full test suite

#### 3. Dependency Check (`.github/workflows/dependency-check.yml`)

**Triggers**: Weekly  
**What it does**:

- Checks for outdated dependencies
- Validates required tools

### Local Pre-commit Hooks

Git hooks are available in `.git-hooks/`:

**Pre-commit Hook**:

- Runs shellcheck on modified Bash scripts
- Validates SQL syntax
- Fast, focused on changed files

**Pre-push Hook**:

- Runs quality tests
- Ensures code quality before pushing

**Installation** (optional):

```bash
# Copy hooks to .git/hooks/
cp .git-hooks/pre-commit .git/hooks/
cp .git-hooks/pre-push .git/hooks/
chmod +x .git/hooks/pre-*
```

---

## Test Execution Times

Approximate execution times:

| Test Suite       | Duration      | Database Required |
| ---------------- | ------------- | ----------------- |
| Quality Tests    | < 1 minute    | No                |
| DWH Tests        | 5-10 minutes  | Yes               |
| All Tests        | 6-11 minutes  | Yes               |
| Single Test File | 10-60 seconds | Depends           |
| Individual Test  | 1-5 seconds   | Depends           |

---

## Test Coverage

### Current Coverage

- **ETL Functions**: ~90% coverage
- **Datamart Procedures**: Validated through integration tests
- **SQL Functions**: Tested through SQL unit tests
- **Bash Scripts**: Syntax validated, functional tests for key scripts

### Coverage by Category

- **Resolution Metrics**: ✅ Fully tested
- **Application Statistics**: ✅ Fully tested
- **Content Quality Metrics**: ✅ Fully tested
- **Community Health Metrics**: ✅ Fully tested
- **User Behavior Metrics**: ✅ Fully tested (26 tests in high priority metrics)
- **High Priority Metrics**: ✅ Fully tested (26 tests)

---

## Performance Testing

Performance benchmarks are available in `tests/performance/`:

**Purpose**: Measure trigger performance impact  
**Execution**: Manual (not part of CI)  
**Usage**: `./tests/performance/run_benchmark.sh`

See [tests/performance/README.md](../tests/performance/README.md) for details.

---

## Related Documentation

### Essential Reading

- **[tests/README.md](../tests/README.md)** - Test directory overview
- **[tests/SCRIPTS.md](../tests/Scripts.md)** - Test scripts documentation
- **[Main README](../README.md)** - Project overview
- **[Contributing Guide](../CONTRIBUTING.md)** - Development standards

### Configuration

- **[tests/properties.sh](../tests/properties.sh)** - Test configuration
- **[bin/dwh/ENVIRONMENT_VARIABLES.md](../bin/dwh/Environment_Variables.md)** - Environment
  variables

### Troubleshooting

- **[Troubleshooting Guide](Troubleshooting_Guide.md)** - Common issues and solutions

### External References

- [BATS Documentation](https://github.com/bats-core/bats-core) - BATS testing framework
- [pgTAP Documentation](https://pgtap.org/) - PostgreSQL testing framework (future)

---

## Summary

The OSM-Notes-Analytics test suite provides comprehensive coverage with **197+ tests** across:

- ✅ **15 Bash unit test files** (~180+ tests)
- ✅ **3 Integration test files** (~20+ tests)
- ✅ **3 SQL unit test files** (~10+ tests)
- ✅ **Quality validation** (syntax, formatting, structure)

**Quick Commands**:

```bash
# Run all tests
./tests/run_all_tests.sh

# Quality only (fast)
./tests/run_quality_tests.sh

# DWH tests (requires DB)
export DBNAME="osm_notes_analytics_test"
./tests/run_dwh_tests.sh

# Single test file
bats tests/unit/bash/datamart_high_priority_metrics.test.bats
```

**For help**: See [Troubleshooting](#troubleshooting) section or create an issue.

---

**Last Updated**: 2025-12-14  
**Maintained By**: Development Team
