# Contributing to OSM-Notes-Analytics

Thank you for your interest in contributing to the OSM-Notes-Analytics project! This document
provides comprehensive guidelines for contributing to this OpenStreetMap notes analytics and data
warehouse system.

## Table of Contents

- [Project Context](#project-context)
- [System Architecture Overview](#system-architecture-overview)
- [Code Standards](#code-standards)
- [Development Workflow](#development-workflow)
- [Testing Requirements](#testing-requirements)
- [File Organization](#file-organization)
- [Naming Conventions](#naming-conventions)
- [Code Documentation](#code-documentation)
- [Quality Assurance](#quality-assurance)
- [Pull Request Process](#pull-request-process)

## Project Context

### What is OSM-Notes-Analytics?

OSM-Notes-Analytics is a data warehouse and analytics system for OpenStreetMap notes. It:

- **Transforms** raw note data into a [star schema data warehouse](../docs/DWH_Star_Schema_ERD.md)
- **Processes** data through ETL (Extract, Transform, Load) pipelines
- **Generates** pre-computed analytics datamarts (users and countries)
- **Exports** data to JSON for web visualization
- **Provides** comprehensive analytics with 70+ metrics per user/country

> **Note:** Base data ingestion is handled by the
> [OSM-Notes-Ingestion](https://github.com/OSM-Notes/OSM-Notes-Ingestion) system. This analytics
> system reads from those base tables.

### Key Design Principles

1. **Star Schema Design**: Dimensional modeling for fast analytical queries (see
   [DWH Star Schema ERD](../docs/DWH_Star_Schema_ERD.md))
2. **Performance**: Partitioned facts table, pre-computed datamarts, parallel processing
3. **Reliability**: Comprehensive error handling, recovery mechanisms, data validation
4. **Maintainability**: Modular design, shared libraries, comprehensive testing
5. **Incremental Processing**: Efficient updates processing only new data

### Essential Documentation

Before contributing, familiarize yourself with:

#### Core Documentation

- **[README.md](../README.md)**: Project overview and quick start
- **[docs/Rationale.md](../docs/Rationale.md)**: Project motivation and design decisions
- **[docs/DWH_Star_Schema_ERD.md](../docs/DWH_Star_Schema_ERD.md)**: Data warehouse structure and
  relationships
- **[docs/Troubleshooting_Guide.md](../docs/Troubleshooting_Guide.md)**: Centralized troubleshooting
  guide

#### Technical Documentation

- **[docs/ETL_Enhanced_Features.md](../docs/ETL_Enhanced_Features.md)**: ETL capabilities and
  features
- **[docs/DWH_Star_Schema_Data_Dictionary.md](../docs/DWH_Star_Schema_Data_Dictionary.md)**:
  Complete schema reference
- **[docs/DWH_Maintenance_Guide.md](../docs/DWH_Maintenance_Guide.md)**: Maintenance and cleanup
  procedures
- **[docs/Partitioning_Strategy.md](../docs/Partitioning_Strategy.md)**: Facts table partitioning
  strategy

#### Script Reference

- **[bin/README.md](../bin/README.md)**: Script usage examples and workflows
- **[bin/dwh/ENTRY_POINTS.md](../bin/dwh/Entry_Points.md)**: Which scripts can be called directly
- **[bin/dwh/ENVIRONMENT_VARIABLES.md](../bin/dwh/Environment_Variables.md)**: Environment variable
  documentation

#### Testing Documentation

- **[tests/README.md](../tests/README.md)**: Testing infrastructure overview
- **[docs/CI_CD_Guide.md](../docs/CI_CD_Guide.md)**: CI/CD workflows and git hooks

## System Architecture Overview

### High-Level Architecture

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    OSM-Notes-Analytics System                        │
└─────────────────────────────────────────────────────────────────────┘

Data Sources:
    └─▶ Base Tables (from OSM-Notes-Ingestion)
        ├─▶ notes
        ├─▶ note_comments
        ├─▶ note_comments_text
        ├─▶ users
        └─▶ countries

Processing Layer:
    ├─▶ ETL.sh (data warehouse creation and updates)
    ├─▶ datamartUsers.sh (user analytics)
    ├─▶ datamartCountries.sh (country analytics)
    └─▶ datamartGlobal.sh (global analytics)

Storage Layer:
    └─▶ PostgreSQL Database
        └─▶ Schema: dwh (data warehouse)
            ├─▶ facts (partitioned by year)
            ├─▶ dimension_* (dimension tables)
            └─▶ datamart_* (pre-computed analytics)

Output:
    ├─▶ JSON Export (for OSM-Notes-Viewer)
    └─▶ Profile Generator (command-line profiles)
```

### Core Components

#### 1. ETL Process (`bin/dwh/ETL.sh`)

- **Purpose**: Transforms base data into
  [star schema data warehouse](../docs/DWH_Star_Schema_ERD.md)
- **Auto-detection**: Automatically detects first execution (creates DWH) vs incremental updates
- **Features**:
  - Parallel processing by year (2013-present)
  - Automatic partition management
  - Recovery and resume capabilities
  - Resource monitoring
  - Automatic datamart updates
- **See [docs/ETL_Enhanced_Features.md](../docs/ETL_Enhanced_Features.md) for details**

#### 2. Datamart Scripts (`bin/dwh/datamart*/`)

- **`datamartUsers.sh`**: Pre-computes user analytics (70+ metrics)
  - Processes incrementally (500 users per run)
  - Tracks historical activity, resolution metrics, content quality
- **`datamartCountries.sh`**: Pre-computes country analytics (70+ metrics)
  - Processes all countries at once
  - Tracks community health, resolution rates, application usage
- **`datamartGlobal.sh`**: Pre-computes global statistics
  - System-wide aggregated metrics

#### 3. Export Scripts (`bin/dwh/export*.sh`)

- **`exportDatamartsToJSON.sh`**: Exports datamarts to JSON files
  - Atomic writes with validation
  - Schema validation before export
  - Fail-safe error handling
- **`exportAndPushJSONToGitHub.sh`**: Exports and deploys to GitHub Pages
  - For OSM-Notes-Viewer (sister project) consumption

#### 4. Profile Generator (`bin/dwh/profile.sh`)

- **Purpose**: Generates detailed profiles for users and countries
- **Usage**: Command-line tool for testing and validation
- **Output**: Formatted text profiles with statistics

#### 5. Function Libraries (`lib/osm-common/`)

- **`lib/osm-common/`**: Shared functions (OSM-Notes-Common Git submodule)
  - `commonFunctions.sh`: Core utilities
  - `validationFunctions.sh`: Data validation
  - `errorHandlingFunctions.sh`: Error handling and recovery
  - `bash_logger.sh`: Logging library (log4j-style)
  - `consolidatedValidationFunctions.sh`: Enhanced validation

#### 6. Database Layer (`sql/dwh/`)

- **`ETL_*.sql`**: ETL SQL scripts (creation, population, constraints)
- **`Staging_*.sql`**: Staging procedures for data transformation
- **`datamartCountries/*.sql`**: Country datamart SQL
- **`datamartUsers/*.sql`**: User datamart SQL
- **`datamartGlobal/*.sql`**: Global datamart SQL

### Data Flow

1. **ETL Flow**:

   ```
   Base Tables → Staging → Facts (partitioned) + Dimensions → Datamarts
   ```

2. **Datamart Flow**:

   ```
   Facts + Dimensions → Aggregations → Datamart Tables (pre-computed)
   ```

3. **Export Flow**:
   ```
   Datamart Tables → JSON Export → Validation → OSM-Notes-Viewer
   ```

For detailed flow diagrams, see [docs/DWH_Star_Schema_ERD.md](../docs/DWH_Star_Schema_ERD.md).

### Database Schema

The system uses a **[star schema](../docs/DWH_Star_Schema_ERD.md)** design:

- **Fact Table**: `dwh.facts` - One row per note action (open, comment, close, reopen) - see
  [Data Dictionary](../docs/DWH_Star_Schema_Data_Dictionary.md#table-dwhfacts) for complete details
  - Partitioned by year (2013-2025+)
  - Foreign keys to all dimension tables
- **Dimension Tables**: Descriptive attributes
  - `dimension_users` - User information (SCD2 for username changes)
  - `dimension_countries` - Country data with ISO codes
  - `dimension_days` - Date dimension with enhanced attributes
  - `dimension_time_of_week` - Temporal dimension (hour of week)
  - `dimension_applications` - Application tracking
  - `dimension_application_versions` - Version history
  - `dimension_hashtags` - Hashtag catalog
  - `dimension_timezones` - Timezone information
  - `dimension_seasons` - Seasonal classifications
  - `dimension_automation_level` - Bot/script detection
  - `dimension_experience_levels` - User experience classification

- **Datamart Tables**: Pre-computed aggregations
  - `datamartusers` - User analytics (70+ metrics)
  - `datamartcountries` - Country analytics (70+ metrics)
  - `datamartglobal` - Global statistics

For complete schema documentation, see
[docs/DWH_Star_Schema_Data_Dictionary.md](../docs/DWH_Star_Schema_Data_Dictionary.md).

## Code Standards

### Bash Script Standards

All bash scripts must follow these standards:

#### Required Header Structure

```bash
#!/bin/bash

# Brief description of the script functionality
#
# This script [describe what it does]
# * [key feature 1]
# * [key feature 2]
# * [key feature 3]
#
# These are some examples to call this script:
# * [example 1]
# * [example 2]
#
# This is the list of error codes:
# [list all error codes with descriptions]
#
# For contributing, please execute these commands before submitting:
# * shellcheck -x -o all [SCRIPT_NAME].sh
# * shfmt -w -i 1 -sr -bn [SCRIPT_NAME].sh
#
# Author: Andres Gomez (AngocA)
# Version: [YYYY-MM-DD]
VERSION="[YYYY-MM-DD]"
```

#### Required Script Settings

```bash
#set -xv
# Fails when a variable is not initialized.
set -u
# Fails with a non-zero return code.
set -e
# Fails if the commands of a pipe return non-zero.
set -o pipefail
# Fails if an internal function fails.
set -E
```

#### Variable Declaration Standards

- **Global variables**: Use `declare -r` for readonly variables
- **Local variables**: Use `local` declaration
- **Integer variables**: Use `declare -i`
- **Arrays**: Use `declare -a`
- **All variables must be braced**: `${VAR}` instead of `$VAR`

#### Function Naming Convention

- **All functions must start with double underscore**: `__function_name`
- **Use descriptive names**: `__download_planet_notes`, `__validate_xml_file`
- **Include function documentation**:

```bash
# Downloads the planet notes file from OSM servers.
# Parameters: None
# Returns: 0 on success, non-zero on failure
function __download_planet_notes {
  # Function implementation
}
```

#### Error Handling

- **Define error codes at the top**:

```bash
# Error codes.
# 1: Help message.
declare -r ERROR_HELP_MESSAGE=1
# 241: Library or utility missing.
declare -r ERROR_MISSING_LIBRARY=241
# 242: Invalid argument for script invocation.
declare -r ERROR_INVALID_ARGUMENT=242
```

### SQL Standards

#### File Naming Convention

- **Process files**: `processAPINotes_20_createApiTables.sql`
- **ETL files**: `ETL_11_checkDWHTables.sql`
- **Function files**: `functionsProcess_20_createFunctionToGetCountry.sql`
- **Drop files**: `processAPINotes_10_dropApiTables.sql`

#### SQL Code Standards

- **Keywords in UPPERCASE**: `SELECT`, `INSERT`, `UPDATE`, `DELETE`
- **Identifiers in lowercase**: `table_name`, `column_name`
- **Use proper indentation**: 2 spaces
- **Include comments for complex queries**
- **Use parameterized queries when possible**

## Development Workflow

### 1. Environment Setup

Before contributing, ensure you have the required tools:

```bash
# Install development tools
sudo apt-get install shellcheck shfmt bats

# Install database tools
sudo apt-get install postgresql
```

### 2. Project Structure Understanding

Familiarize yourself with the project structure:

- **`bin/`**: Executable scripts (ETL, datamarts, profile generator)
- **`sql/`**: Database scripts (star schema, ETL procedures, datamarts)
- **`tests/`**: Comprehensive testing infrastructure (unit, integration)
- **`docs/`**: System documentation (ERD, data dictionary, guides)
- **`etc/`**: Configuration files (database, ETL settings)
- **`lib/`**: Shared libraries (logging, validation, error handling)
- **`scripts/`**: Utility scripts (setup, hooks, validation)

### 3. Development Process

1. **Create a feature branch**:

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Follow the established patterns**:
   - Use existing function names and patterns
   - Follow the error code numbering system
   - Maintain the logging structure
   - Use the established variable naming

3. **Test your changes**:

   ```bash
   # Run quality tests (fast, no database)
   ./tests/run_quality_tests.sh

   # Run DWH tests (requires database)
   ./tests/run_dwh_tests.sh

   # Run all tests
   ./tests/run_all_tests.sh
   ```

## Testing Requirements

### Overview

All contributions must include comprehensive testing. The project uses BATS testing suites and SQL
tests covering all system components, including DWH functionality.

### Test Categories

#### Unit Tests

- **Bash Scripts**: BATS test suites for ETL and datamart scripts
  - `tests/unit/bash/ETL_enhanced.test.bats`
  - `tests/unit/bash/ETL_integration.test.bats`
  - `tests/unit/bash/datamartCountries_integration.test.bats`
  - `tests/unit/bash/datamartUsers_integration.test.bats`
- **SQL Tests**: SQL test suites for DWH functions and procedures
  - `tests/unit/sql/dwh_cleanup.test.sql`
  - `tests/unit/sql/dwh_dimensions_enhanced.test.sql`
  - `tests/unit/sql/dwh_functions_enhanced.test.sql`

#### Integration Tests

- **End-to-End Workflows**: Complete system integration testing
  - `tests/integration/ETL_enhanced_integration.test.bats`
  - `tests/integration/datamart_enhanced_integration.test.bats`

#### Quality Tests

- **Code Quality**: Shellcheck linting, shfmt formatting, code conventions
- **Configuration**: Validation of properties files and SQL syntax
- **Database**: PostgreSQL extension checks

### DWH Testing Requirements

When contributing to DWH features, you must include tests for:

#### Dimensions

- **`dimension_timezones`**: Timezone support testing
- **`dimension_seasons`**: Seasonal analysis testing
- **`dimension_continents`**: Continental grouping testing
- **`dimension_application_versions`**: Application version testing
- **`fact_hashtags`**: Bridge table testing
- **`dimension_time_of_week`**: Time-of-week attributes testing
- **`dimension_users`**: SCD2 implementation testing
- **`dimension_countries`**: ISO codes testing
- **`dimension_days`**: Date attributes testing
- **`dimension_applications`**: Application attributes testing

#### Functions

- **`get_timezone_id_by_lonlat()`**: Timezone calculation testing
- **`get_season_id()`**: Season calculation testing
- **`get_application_version_id()`**: Application version management testing
- **`get_local_date_id()`**: Local date calculation testing
- **`get_local_hour_of_week_id()`**: Local hour calculation testing

#### ETL Components

- **Staging Procedures**: New columns, SCD2, bridge tables
- **Datamart Compatibility**: Integration with dimensions
- **Documentation**: Consistency with implementation

### Running Tests

#### Complete Test Suite

```bash
# Run all tests (quality + DWH)
./tests/run_all_tests.sh

# Run quality tests only (fast, no database)
./tests/run_quality_tests.sh

# Run DWH tests only (requires database)
./tests/run_dwh_tests.sh
```

#### Individual Test Categories

```bash
# Unit tests
bats tests/unit/bash/ETL_enhanced.test.bats
bats tests/unit/bash/datamartCountries_integration.test.bats
bats tests/unit/bash/datamartUsers_integration.test.bats

# Integration tests
bats tests/integration/ETL_enhanced_integration.test.bats
bats tests/integration/datamart_enhanced_integration.test.bats

# SQL tests (requires psql and database 'dwh')
psql -d dwh -f tests/unit/sql/dwh_cleanup.test.sql
psql -d dwh -f tests/unit/sql/dwh_dimensions_enhanced.test.sql
psql -d dwh -f tests/unit/sql/dwh_functions_enhanced.test.sql
```

#### Test Validation

```bash
# Git hooks are available in .git-hooks/ and can be installed manually if needed
# See scripts/README.md for details
```

### Test Documentation

All new tests must be documented in:

- [Tests README](./tests/README.md) - Complete testing guide and test suite documentation

### CI/CD Integration

Tests are automatically run in GitHub Actions workflows:

- **Quality Checks** (`.github/workflows/quality-checks.yml`):
  - Shellcheck linting on all Bash scripts
  - shfmt formatting validation
  - SQL syntax validation
  - Configuration file validation
  - Runs on every push and pull request
- **Tests** (`.github/workflows/tests.yml`):
  - Quality tests (no database required)
  - DWH tests (with PostgreSQL setup)
  - Integration tests
  - Runs on push to main branch
- **Dependency Check** (`.github/workflows/dependency-check.yml`):
  - Validates required tools are available
  - Checks for outdated dependencies

- **Git Hooks**:
  - **Pre-commit**: Fast checks on staged files only
  - **Pre-push**: Full validation before pushing

### Test Quality Standards

#### Test Requirements

- **Test all new ETL features** (dimensions, functions, procedures)
- **Test all new datamart features** (aggregations, calculations)
- **Test error handling** for edge cases and failures
- **Test data integrity** (referential integrity, constraints)

#### Test Quality

- **Descriptive test names** that explain what is being tested
- **Comprehensive assertions** that validate expected behavior
- **Independent tests** that don't depend on each other
- **Clean up after tests** to avoid side effects

#### Documentation

- **Test descriptions** in the test file comments
- **Setup requirements** documented in test README
- **Expected behavior** explained in assertions
- **Known issues** documented in test comments

## File Organization

### Directory Structure Standards

```text
OSM-Notes-Analytics/
├── bin/                    # Executable scripts
│   └── dwh/               # data warehouse scripts
│       ├── ETL.sh         # Main ETL process
│       ├── profile.sh     # Profile generator
│       ├── datamartCountries/  # Country datamart
│       └── datamartUsers/      # User datamart
├── sql/                   # Database scripts
│   └── dwh/              # data warehouse SQL
│       ├── ETL_*.sql     # ETL scripts
│       ├── Staging_*.sql # Staging procedures
│       ├── datamartCountries/  # Country datamart SQL
│       └── datamartUsers/      # User datamart SQL
├── tests/                # Testing infrastructure
│   ├── unit/            # Unit tests
│   │   ├── bash/        # Bash script tests
│   │   └── sql/         # SQL tests
│   ├── integration/     # Integration tests
│   ├── run_all_tests.sh       # Run all tests
│   ├── run_quality_tests.sh   # Quality tests
│   └── run_dwh_tests.sh       # DWH tests
├── scripts/              # Utility scripts
│   └── README.md         # Scripts documentation
├── docs/                 # Documentation
│   ├── DWH_Star_Schema_ERD.md
│   ├── DWH_Star_Schema_Data_Dictionary.md
│   ├── ETL_Enhanced_Features.md
│   ├── CI_CD_Guide.md
│   └── Testing_*.md
├── etc/                  # Configuration
│   ├── properties.sh     # Database config
│   └── etl.properties    # ETL config
└── lib/                  # Shared libraries
    └── osm-common/       # Common utilities
        ├── bash_logger.sh
        ├── commonFunctions.sh
        ├── validationFunctions.sh
        └── errorHandlingFunctions.sh
```

### File Naming Conventions

#### Script Files

- **Main scripts**: `ETL.sh`, `profile.sh`, `datamartCountries.sh`, `datamartUsers.sh`
- **Utility scripts**: See `scripts/README.md` for available scripts
- **Test runners**: `run_all_tests.sh`, `run_quality_tests.sh`, `run_dwh_tests.sh`

#### SQL Files

Follow the naming pattern: `<Component>_<Phase><Step>_<Description>.sql`

- **ETL scripts**: `ETL_20_createDWHTables.sql`, `ETL_25_populateDimensionTables.sql`
- **Staging scripts**: `Staging_31_createBaseStagingObjects.sql`, `Staging_60_loadNotes.sql`
- **Datamart scripts**: `datamartCountries_30_populateDatamartCountriesTable.sql`
- **Phase numbers**: 1x=validation, 2x=creation, 3x=population, 4x=constraints, 5x=finalization,
  6x=incremental

#### Test Files

- **Unit tests**: `ETL_enhanced.test.bats`, `datamartCountries_integration.test.bats`
- **Integration tests**: `ETL_enhanced_integration.test.bats`,
  `datamart_enhanced_integration.test.bats`
- **SQL tests**: `dwh_cleanup.test.sql`, `dwh_dimensions_enhanced.test.sql`

## Naming Conventions

### Variables

- **Global variables**: `UPPERCASE_WITH_UNDERSCORES`
- **Local variables**: `lowercase_with_underscores`
- **Constants**: `UPPERCASE_WITH_UNDERSCORES`
- **Environment variables**: `UPPERCASE_WITH_UNDERSCORES`

### Functions

- **All functions**: `__function_name_with_underscores`
- **Private functions**: `__private_function_name`
- **Public functions**: `__public_function_name`

### Database Objects

- **Tables**: `lowercase_with_underscores`
- **Columns**: `lowercase_with_underscores`
- **Functions**: `function_name_with_underscores`
- **Procedures**: `procedure_name_with_underscores`

## Shared Libraries

### Library Organization

The project uses shared libraries from
[OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common) (Git submodule located at
`lib/osm-common/`) to eliminate code duplication and improve maintainability:

**Repository**: [OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common)  
**Location**: `lib/osm-common/` (Git submodule)  
**Used by**: OSM-Notes-Ingestion, OSM-Notes-Analytics (and potentially OSM-Notes-Viewer)

#### 1. Logging (`lib/osm-common/bash_logger.sh`)

- **Purpose**: Centralized logging framework with multiple log levels
- **Functions**: `__logt`, `__logd`, `__logi`, `__logw`, `__loge`, `__logf`, `__log_start`,
  `__log_finish`
- **Usage**: All scripts should source this for consistent logging
- **Log Levels**: TRACE, DEBUG, INFO, WARN, ERROR, FATAL

#### 2. Common Functions (`lib/osm-common/commonFunctions.sh`)

- **Purpose**: Shared utility functions used across scripts
- **Functions**: `__checkPrereqsCommands`, `__waitForJobs`, `__start_logger`
- **Usage**: Source this for common operations like prerequisite checks

#### 3. Validation Functions (`lib/osm-common/validationFunctions.sh`)

- **Purpose**: Validation functions for files, configuration, and database
- **Functions**: `__validate_sql_structure`, `__validate_config_file`,
  `__validate_database_connection`
- **Usage**: Use these for all validation operations

#### 4. Error Handling (`lib/osm-common/errorHandlingFunctions.sh`)

- **Purpose**: Centralized error handling and traps
- **Functions**: `__trapOn`, `__handle_error`, `__cleanup`
- **Usage**: Set up error traps for robust error handling

#### 5. Implementation Guidelines

- **New Functions**: Add to appropriate library file in OSM-Notes-Common repository rather than
  duplicating
- **Consistent Usage**: All scripts should source and use these libraries
- **Testing**: Test library functions independently
- **Submodule Updates**: Update submodule when new library features are needed
  ```bash
  cd lib/osm-common
  git pull origin main
  cd ../..
  git add lib/osm-common
  git commit -m "Update OSM-Notes-Common submodule"
  ```

### Using the Libraries

All scripts should source the required libraries at the beginning:

```bash
# Load common functions from OSM-Notes-Common submodule
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/bash_logger.sh"
```

**Note**: The `lib/osm-common/` directory is a Git submodule pointing to the
[OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common) repository. Always initialize
submodules when cloning:

```bash
git clone --recurse-submodules https://github.com/OSM-Notes/OSM-Notes-Analytics.git
# Or after cloning:
git submodule update --init --recursive
```

## Code Documentation

### Required Documentation

1. **Script Headers**: Every script must have a comprehensive header (see template above)
2. **Function Documentation**: All functions must be documented with parameters and return values
3. **README Files**: Each major directory has a README.md (bin/, etc/, sql/, tests/, docs/, lib/,
   scripts/)
4. **SQL Documentation**: Document complex queries, procedures, and functions
5. **Configuration Documentation**: Document all configuration options in etc/README.md
6. **Test Documentation**: Document test purpose, setup, and expected results

### Documentation Standards

#### Script Documentation

```bash
# Brief description of what the script does
#
# Detailed explanation of functionality
# * Key feature 1
# * Key feature 2
# * Key feature 3
#
# Usage examples:
# * Example 1
# * Example 2
#
# Error codes:
# 1: Help message
# 241: Library missing
# 242: Invalid argument
#
# Author: [Your Name]
# Version: [YYYY-MM-DD]
```

#### Function Documentation

```bash
# Brief description of what the function does
# Parameters: [list of parameters]
# Returns: [return value description]
# Side effects: [any side effects]
function __function_name {
  # Implementation
}
```

## Quality Assurance

### Pre-Submission Checklist

Before submitting your contribution, ensure:

- [ ] **Code formatting**: Run `shfmt -w -i 1 -sr -bn` on all bash scripts
- [ ] **Linting**: Run `shellcheck -x -o all` on all bash scripts
- [ ] **Tests**: All tests pass (`./tests/run_tests.sh`)
- [ ] **Documentation**: All new code is documented
- [ ] **Error handling**: Proper error codes and handling
- [ ] **Logging**: Appropriate logging levels and messages
- [ ] **Performance**: No performance regressions
- [ ] **Security**: No security vulnerabilities

### Code Quality Tools

#### Required Tools

```bash
# Format bash scripts
shfmt -w -i 1 -sr -bn script.sh

# Lint bash scripts
shellcheck -x -o all script.sh

# Run tests
./tests/run_tests.sh

# Run advanced tests
./tests/advanced/run_advanced_tests.sh
```

#### Quality Standards

- **ShellCheck**: No warnings or errors
- **shfmt**: Consistent formatting
- **Test Coverage**: Minimum 80% coverage
- **Performance**: No significant performance degradation
- **Security**: No security vulnerabilities

## Pull Request Process

### 1. Preparation

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/your-feature`
3. **Make your changes following the standards above**
4. **Test thoroughly**: Run all test suites
5. **Update documentation**: Add/update relevant documentation

### 2. Submission

1. **Commit your changes**:

   ```bash
   git add .
   git commit -m "feat: add new feature description"
   ```

2. **Push to your fork**:

   ```bash
   git push origin feature/your-feature
   ```

3. **Create a Pull Request** with:
   - **Clear title**: Describe the feature/fix
   - **Detailed description**: Explain what and why
   - **Test results**: Include test output
   - **Screenshots**: If applicable

### 3. Review Process

1. **Automated checks** must pass
2. **Code review** by maintainers
3. **Test verification** by maintainers
4. **Documentation review** for completeness
5. **Final approval** and merge

### 4. Commit Message Standards

Use conventional commit messages:

```text
type(scope): description

[optional body]

[optional footer]
```

**Types**:

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

**Examples**:

```text
feat(process): add parallel processing for large datasets
fix(sql): correct country boundary import for Austria
docs(readme): update installation instructions
test(api): add integration tests for new endpoints
```

## Getting Help

### Resources

- **Project README**: Main project documentation
- **Directory READMEs**: Specific component documentation
- **Test Examples**: See existing tests for patterns
- **Code Examples**: Study existing scripts for patterns

### Contact

- **Issues**: Use GitHub Issues for bugs and feature requests
- **Discussions**: Use GitHub Discussions for questions
- **Pull Requests**: For code contributions

### Development Environment

#### Database Setup

For local testing, you need PostgreSQL with PostGIS:

```bash
# Create test database (name matches tests/properties.sh default)
createdb osm_notes_analytics_test
psql -d osm_notes_analytics_test -c "CREATE EXTENSION postgis;"
psql -d osm_notes_analytics_test -c "CREATE EXTENSION btree_gist;"

# Configure in tests/properties.sh or export (optional, these are the defaults)
export TEST_DBNAME="osm_notes_analytics_test"
```

See [tests/README.md](tests/README.md) for complete test setup instructions.

### Local Configuration

To avoid accidentally committing local configuration changes:

```bash
# Tell Git to ignore changes to properties files (local development only)
git update-index --assume-unchanged etc/properties.sh
git update-index --assume-unchanged etc/etl.properties

# Verify that the files are now ignored
git ls-files -v | grep '^[[:lower:]]'

# To re-enable tracking (if needed)
git update-index --no-assume-unchanged etc/properties.sh
git update-index --no-assume-unchanged etc/etl.properties
```

This allows you to customize database settings, user names, and ETL configurations for local
development without affecting the repository.

## Version Control

### Branch Strategy

- **main**: Production-ready code
- **develop**: Integration branch
- **feature/\***: New features
- **bugfix/\***: Bug fixes
- **hotfix/\***: Critical fixes

### Release Process

1. **Feature complete**: All features implemented and tested
2. **Documentation complete**: All documentation updated
3. **Tests passing**: All test suites pass
4. **Code review**: All changes reviewed
5. **Release**: Tag and release

---

**Thank you for contributing to OSM-Notes-Analytics!**

Your contributions help make OpenStreetMap notes analytics and data warehouse more accessible and
powerful for the community.
