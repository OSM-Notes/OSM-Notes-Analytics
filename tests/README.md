# Tests Directory

This directory contains the comprehensive test suite for the OSM-Notes-Analytics project, including
unit tests, integration tests, and quality validation tests.

## Overview

The test suite is built using:

- **BATS** (Bash Automated Testing System) for Bash script testing
- **PostgreSQL pgTAP** for SQL testing (future enhancement)
- Custom test helpers and utilities

## Directory Structure

```text
tests/
├── unit/                      # Unit tests
│   ├── bash/                  # Bash script unit tests
│   │   ├── ETL_enhanced.test.bats
│   │   ├── ETL_integration.test.bats
│   │   ├── datamartCountries_integration.test.bats
│   │   ├── datamart_last_year_activity.test.bats
│   │   ├── datamartUsers_integration.test.bats
│   │   ├── datamart_resolution_metrics.test.bats
│   │   ├── datamartUsers_resolution_metrics.test.bats
│   │   └── datamart_application_statistics.test.bats
│   └── sql/                   # SQL unit tests
│       ├── dwh_cleanup.test.sql
│       ├── dwh_dimensions_enhanced.test.sql
│       └── dwh_functions_enhanced.test.sql
├── integration/               # Integration tests
│   ├── ETL_enhanced_integration.test.bats
│   └── datamart_enhanced_integration.test.bats
├── sql/                       # Test data setup
│   └── setup_test_data.sql    # SQL for test database setup
├── properties.sh              # Test configuration properties
├── test_helper.bash           # Common test utilities and helpers
├── run_all_tests.sh          # Run all test suites
├── run_dwh_tests.sh          # Run DWH and database tests
└── run_quality_tests.sh      # Run quality and validation tests
```

## Test Suites

### 1. Quality Tests (No Database Required)

Quick validation tests that don't require database connectivity:

- Shell script syntax validation (shellcheck)
- Code formatting checks (shfmt)
- File structure validation
- Configuration file validation

**Run:**

```bash
./tests/run_quality_tests.sh
```

**Features:**

- ✅ Fast execution (< 1 minute)
- ✅ No database dependency
- ✅ Checks all Bash scripts for syntax errors
- ✅ Validates SQL file structure
- ✅ Validates configuration files

### 2. DWH Tests (Database Required)

Tests that validate the data warehouse ETL processes and datamarts:

- ETL process testing
- Datamart population testing
- SQL function testing
- Data integrity validation

**Run:**

```bash
./tests/run_dwh_tests.sh
```

**Prerequisites:**

- PostgreSQL database named `osm_notes_analytics_test` must exist (default for local testing)
- Database configured in `tests/properties.sh` (defaults to `osm_notes_analytics_test`)
- PostGIS extension installed

**Features:**

- ✅ Tests ETL process execution
- ✅ Validates dimension table population
- ✅ Tests datamart creation and updates
- ✅ Verifies data integrity constraints

### 3. All Tests

Runs both quality and DWH tests sequentially:

**Run:**

```bash
./tests/run_all_tests.sh
```

## Test Configuration

### Database Configuration

Edit `tests/properties.sh` to configure test database settings:

```bash
# Test database name (default: osm_notes_analytics_test)
export TEST_DBNAME="osm_notes_analytics_test"

# Database user (default: current user for peer authentication)
export TEST_DBUSER="myuser"

# Other test-specific settings
```

**Note**: The default test database name is `osm_notes_analytics_test` for local testing.

### Test Helper Functions

The `test_helper.bash` file provides common utilities:

- Database connection testing
- Setup and teardown functions
- Assertion helpers
- Mock data generation

## Writing Tests

### Bash Script Tests (BATS)

Example test structure:

```bash
#!/usr/bin/env bats

load test_helper

@test "ETL creates dimension tables" {
  run psql -d "${DBNAME}" -c "SELECT COUNT(*) FROM dwh.dimension_users"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}
```

### SQL Tests

SQL tests use pgTAP framework (planned):

```sql
-- Test that dimension_users table exists
SELECT has_table('dwh', 'dimension_users', 'dimension_users table should exist');

-- Test that required columns exist
SELECT has_column('dwh', 'dimension_users', 'dimension_user_id');
```

## Test Categories

### Unit Tests

Located in `unit/`, these tests verify individual components in isolation:

- **ETL_enhanced.test.bats**: Tests ETL script functions
- **ETL_integration.test.bats**: Tests ETL integration with database
- **datamartCountries_integration.test.bats**: Tests country datamart
- **datamartUsers_integration.test.bats**: Tests user datamart
- **dwh\_\*.test.sql**: Tests SQL functions and procedures

### Integration Tests

Located in `integration/`, these tests verify end-to-end workflows:

- **ETL_enhanced_integration.test.bats**: Full ETL workflow testing
- **datamart_enhanced_integration.test.bats**: Full datamart workflow testing

## Continuous Integration

Tests are automatically run in CI/CD pipelines:

### GitHub Actions Workflows

1. **Quality Checks** (`.github/workflows/quality-checks.yml`)
   - Runs on every push and pull request
   - Executes quality tests without database

2. **Tests** (`.github/workflows/tests.yml`)
   - Runs on push to main branch
   - Executes full test suite with database

3. **Dependency Check** (`.github/workflows/dependency-check.yml`)
   - Checks for outdated dependencies
   - Validates required tools are available

### Git Hooks

Git hooks are available in `.git-hooks/` and can be installed manually if needed for local testing.

**Pre-commit Hook:**

- Runs shellcheck on modified Bash scripts
- Validates SQL syntax
- Fast, focused on changed files

**Pre-push Hook:**

- Runs quality tests
- Ensures code quality before pushing

## Test Execution Times

Approximate execution times:

- **Quality Tests**: < 1 minute
- **DWH Tests**: 5-10 minutes (depends on database size)
- **All Tests**: 6-11 minutes total

## Troubleshooting

### Tests Fail with "Database does not exist"

Create the test database:

```bash
createdb osm_notes_analytics_test
psql -d dwh -c "CREATE EXTENSION postgis;"
```

### BATS Not Found

Install BATS:

```bash
# Ubuntu/Debian
sudo apt-get install bats

# macOS
brew install bats-core
```

### Permission Denied Errors

Ensure scripts are executable:

```bash
chmod +x tests/run_*.sh
chmod +x scripts/*.sh
chmod +x bin/dwh/*.sh
```

### Database Connection Issues

Verify database configuration:

```bash
psql -d osm_notes_analytics_test -c "SELECT version();"
```

Check `tests/properties.sh` settings match your database.

**Important**: Tests will now **fail explicitly** if the database is not available, rather than
silently skipping. This helps identify configuration issues early.

If you see connection errors:

1. Ensure PostgreSQL is running: `sudo systemctl status postgresql` (Linux) or `brew services list`
   (macOS)
2. Create the test database: `createdb osm_notes_analytics_test`
3. Verify connection: `psql -d osm_notes_analytics_test -c "SELECT 1;"`
4. Check `tests/properties.sh` for correct database name

## Best Practices

1. **Run quality tests locally** before committing
2. **Write tests for new features** before implementation
3. **Keep tests independent** - each test should set up and clean up
4. **Use descriptive test names** that explain what is being tested
5. **Mock external dependencies** when possible
6. **Test error conditions** not just happy paths

## Performance Testing

Performance benchmarks are available in the `tests/performance/` directory:

- **Manual execution**: Run benchmarks when needed to measure trigger impact
- **Not part of CI**: Performance tests are not automated (long-running)
- **Usage**: `./tests/performance/run_benchmark.sh`

See [tests/performance/README.md](performance/README.md) for details.

## Future Enhancements

- [ ] Add pgTAP framework for comprehensive SQL testing
- [ ] Automate performance benchmarking in CI (monthly runs)
- [ ] Add data quality tests
- [ ] Increase test coverage to 80%+ (currently ~90% on main functions)
- [ ] Add mutation testing
- [ ] Add test reports and coverage metrics

## Contributing

When adding new features:

1. Write tests first (TDD approach)
2. Ensure all existing tests pass
3. Add tests to appropriate suite (unit/integration)
4. Update this README if adding new test categories
5. Run full test suite before submitting PR

## Related Documentation

### Essential Reading

- **[Main README](../README.md)** - Project overview and quick start
- **[Contributing Guide](../CONTRIBUTING.md)** - Development standards and testing requirements
- **[CI/CD Guide](../docs/CI_CD_Guide.md)** - CI/CD workflows and test integration

### Scripts and Entry Points

- **[bin/dwh/ENTRY_POINTS.md](../bin/dwh/Entry_Points.md)** - Script entry points (what to test)
- **[bin/README.md](../bin/README.md)** - Script usage and examples

### Configuration

- **[etc/README.md](../etc/README.md)** - Configuration files for test environment
- **[bin/dwh/ENVIRONMENT_VARIABLES.md](../bin/dwh/Environment_Variables.md)** - Environment
  variables

### Troubleshooting

- **[Troubleshooting Guide](../docs/Troubleshooting_Guide.md)** - Common test failures and solutions

### External References

- [BATS Documentation](https://github.com/bats-core/bats-core) - BATS testing framework
- [pgTAP Documentation](https://pgtap.org/) - PostgreSQL testing framework

## References

- [BATS Documentation](https://github.com/bats-core/bats-core)
- [pgTAP Documentation](https://pgtap.org/)
- [Testing Guide](../tests/README.md)
- [CI/CD Guide](../docs/CI_CD_Guide.md)

## Support

For test-related issues:

1. Check test output for specific error messages
2. Review test logs in `/tmp/` directory
3. Consult this Testing Guide
4. Create an issue with test failure details
