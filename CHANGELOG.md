# Changelog

All notable changes to this project will be documented in this file.

## [2026-01-26] - Recent Updates and Improvements

### Added

- **CI/CD Testing Infrastructure**: Added local CI testing scripts and improved test workflows
- **Datamart Enhancements**: Added new tracking columns and metrics to datamartUsers and
  datamartCountries
- **Enhanced Export Functionality**: Improved CSV and JSON export processes with incremental updates
  and conflict resolution

### Changed

- **Documentation**: Comprehensive documentation updates including standardized links, metadata
  sections, and Mermaid diagrams
- **ETL Process**: Enhanced ETL execution with improved phase handling and closed dimension date
  updates
- **Database**: Updated SQL scripts to use public schema and improved query optimization
- **Performance**: Optimized SQL queries, export processes, and added locking mechanisms
- **Code Quality**: Standardized code formatting, improved error handling, and enhanced logging

### Fixed

- **Timestamp handling**: Fixed multiple issues related to timestamp handling

---

## [2025-12-27] - Machine Learning Integration and Complete Datamart Implementation

### Added

- **pgml Extension Installation**: Complete installation script for PostgreSQL Machine Learning
  extension
  - `sql/dwh/ml/install_pgml.sh`: Automated script to compile and install pgml from source
  - Supports multiple PostgreSQL versions (14+)
  - Automatic detection of installed PostgreSQL versions
  - Comprehensive error handling and build dependency management
  - Documentation: `sql/dwh/ml/README.md` with installation and usage guide
- **User Contribution Statistics (DOC-001)**: Complete implementation of user contribution analysis
  - `sql/dwh/queries/DOC_001_user_contribution_stats.sql`: Query for users with single contribution
  - Enhanced query with distribution by contribution levels (1, 2-5, 6-10, 11-50, 51-100, 101-500,
    501-1000, 1000+)
  - View `dwh.v_user_contribution_distribution` for easy access
  - Function `dwh.get_user_contribution_summary()` for programmatic statistics
- **Complete Datamart Implementation (DM-001 to DM-016)**: All datamart features completed
  - DM-001: Applications used metrics (mobile/desktop apps tracking)
  - DM-002: Complete hashtag analyzer with filtering capabilities
  - DM-003: Hashtag queries enhanced with sequence tracking
  - DM-004: Badge system with automatic assignment
  - DM-005: Parallel processing with intelligent prioritization (6-level system)
  - DM-006: Note quality classification (poor, fair, good, complex, treatise)
  - DM-007: Peak day for note creation tracking
  - DM-008: Peak hour for note creation tracking
  - DM-009: Open notes by year (JSONB structure)
  - DM-010: Longest resolution notes per country
  - DM-011: Last comment timestamp in global datamart
  - DM-012: Ranking system (top 100 historical, last year, last month, today)
  - DM-013: Country rankings by metrics
  - DM-014: User rankings globally
  - DM-015: Average comments per note
  - DM-016: Average comments per note by country

### Changed

- **Parallel Processing Enhancement**: Intelligent user prioritization system
  - 6-level prioritization based on recency and historical activity
  - Parallel execution with concurrency control (`nproc - 1` threads)
  - Atomic transactions for data integrity
  - Comprehensive documentation: `bin/dwh/datamartUsers/PARALLEL_PROCESSING.md`
- **ETL Integrity Validation**: Enhanced monitoring and validation
  - `sql/dwh/ETL_57_validateETLIntegrity.sql`: Complete integrity checks
  - Validation of comment counts between `public.note_comments` and `dwh.facts`
  - Detection of notes with reopens after closure
  - Integrated in `monitor_etl.sh` and `ETL.sh`
- **ETL Report Generation**: Comprehensive ETL execution reports
  - `sql/dwh/ETL_56_generateETLReport.sql`: Report generation procedure
  - Metrics for facts, dimensions, datamarts
  - Statistics for users, countries, hashtags
  - Integrated in `bin/dwh/ETL.sh` at end of execution
- **Note Current Status Tracking**: Efficient tracking of note states
  - `sql/dwh/ETL_55_createNoteCurrentStatus.sql`: Current status table and procedures
  - Views: `dwh.v_currently_open_notes_by_user`, `dwh.v_currently_open_notes_by_country`
  - Procedures: `dwh.initialize_note_current_status()`, `dwh.update_note_current_status()`
  - Integrated in datamarts for better performance
- **Shared Helper Functions**: Code factorization for staging procedures
  - `sql/dwh/Staging_30_sharedHelperFunctions.sql`: Common functions
  - `staging.get_or_create_country_dimension()`: Country dimension handling
  - `staging.process_hashtags()`: Hashtag processing
  - `staging.calculate_comment_metrics()`: Comment metrics
  - `staging.get_timezone_and_local_metrics()`: Timezone metrics
- **Profile Script Enhancements**: Improved user and country profile output
  - Enhanced hashtag analysis display with `jq`
  - Comment quality metrics visualization
  - User statistics and achievements reporting
  - Activity printing and working hours reporting
  - Current notes status display

### Technical Details

- **pgml Installation**: Script handles multiple PostgreSQL versions, Rust installation, pgrx
  configuration, and compilation with Python support
- **Parallel Processing**: Uses Bash process management with PostgreSQL transactions for atomicity
- **ETL Validation**: Compares comment counts at multiple levels (total, per note, by action type)
- **Datamart Metrics**: All new metrics automatically calculated during datamart updates
- **Badge System**: Automatic badge assignment based on user activity patterns

### Files Modified

- `sql/dwh/ml/install_pgml.sh` (new)
- `sql/dwh/ml/README.md` (new)
- `sql/dwh/queries/DOC_001_user_contribution_stats.sql` (new)
- `bin/dwh/datamartUsers/datamartUsers.sh`: Parallel processing implementation
- `sql/dwh/datamartUsers/datamartUsers_32_populateDatamartUsersTable.sql`: Prioritization logic
- `bin/dwh/datamartUsers/PARALLEL_PROCESSING.md` (new)
- `sql/dwh/ETL_57_validateETLIntegrity.sql` (new)
- `sql/dwh/ETL_56_generateETLReport.sql` (new)
- `sql/dwh/ETL_55_createNoteCurrentStatus.sql` (new)
- `sql/dwh/Staging_30_sharedHelperFunctions.sql` (new)
- `bin/dwh/profile.sh`: Enhanced visualization
- `sql/dwh/datamarts/58_addNewDatamartMetrics.sql` (new)
- `sql/dwh/datamarts/59_calculateNewDatamartMetrics.sql` (new)
- `sql/dwh/datamarts/60_enhanceHashtagQueriesWithSequence.sql` (new)
- `sql/dwh/datamarts/61_createRankingSystem.sql` (new)
- `sql/dwh/datamarts/62_createBadgeSystem.sql` (new)
- `sql/dwh/datamarts/63_completeHashtagAnalysis.sql` (new)

### Documentation

- Added `bin/dwh/datamartUsers/PARALLEL_PROCESSING.md`: Complete documentation of parallel
  processing system
- Added `sql/dwh/ml/README.md`: pgml installation and usage guide
- Updated `ToDo/TODO_LIST.md`: All datamart tasks marked as completed
- Removed obsolete files: `ToDo/ToDos.md`, `ToDo/DATAMARTS_IMPLEMENTATION_PLAN.md`

---

## [2025-12-26] - ETL Enhancements and Script Standardization

### Added

- **ETL Report Generation**: `sql/dwh/ETL_56_generateETLReport.sql` for comprehensive ETL execution
  reports
- **Note Current Status Tracking**: `sql/dwh/ETL_55_createNoteCurrentStatus.sql` for efficient note
  state tracking
- **Shared Helper Functions**: `sql/dwh/Staging_30_sharedHelperFunctions.sql` for code reuse in
  staging procedures
- **Profile Script Enhancements**: Improved visualization with `jq` for hashtags, quality metrics,
  and achievements

### Changed

- **Script Standardization**: Standardized variable naming conventions across DWH scripts
- **Exit Code Handling**: Consistent exit code handling across all scripts
- **Error Handling**: Improved error handling in `run_mock_etl.sh` for existing objects
- **ETL Table Validation**: Enhanced validation for incremental executions
- **Monitor Script**: Improved consistency and readability in `monitor_etl.sh`

### Files Modified

- `bin/dwh/ETL.sh`: Report generation integration
- `bin/dwh/monitor_etl.sh`: Improved consistency
- `bin/dwh/profile.sh`: Enhanced output
- Multiple staging SQL files: Shared helper functions integration

---

## [2025-12-25] - Performance Monitoring and ETL Improvements

### Added

- **Dynamic SQL for Performance Logging**: Performance logging in datamart procedures
- **ETL Performance Logging**: Datamart performance logging and schema management
- **Detailed Timing Logs**: Enhanced ETL process with detailed timing logs and initial load handling

### Changed

- **ETL Process**: Enhanced with datamart performance logging
- **Schema Management**: Improved schema management in ETL script
- **Table Validation**: Enhanced ETL table validation for incremental executions

---

## [2025-12-23] - Export and Publication Features

### Added

- **JSON Export Script**: `bin/dwh/exportAndPushJSONToGitHub.sh` for JSON export and deployment
- **CSV Export Script**: `bin/dwh/exportAndPushCSVToGitHub.sh` for closed notes CSV export
- **Contributor Type Information**: Enhanced `exportDatamartsToJSON` script to include contributor
  type information

### Changed

- **Closed Notes Export**: Updated SQL query to use `dimension_days` for `opened_at`
- **Export Scripts**: Enhanced to include JSON schema copying

---

## [2025-12-22] - Documentation Consolidation

### Changed

- **Action Plan Consolidation**: Consolidated Action Plan into TODO_LIST
- **Documentation Updates**: Simplified documentation in ProgressTracker and README files
- **Submodule Updates**: Updated subproject references

### Removed

- **API Proposal**: Removed API Proposal document from repository

---

## [2025-12-20] - ETL Script Enhancements

### Added

- **Timeout Configuration**: ETL script with timeout configuration for psql commands
- **Process Locking**: Process locking mechanism in ETL script
- **Schema Management**: Enhanced schema management in ETL script

### Changed

- **Error Handling**: Enhanced error handling and verification in ETL script
- **Logging**: Improved logging and output handling in ETL script

---

## [2025-12-19] - Country Dimension and Resolution Ratio Improvements

### Added

- **FORCE_SWAP_ON_WARNING**: Environment variable to hybrid setup script
- **REST API Proposal**: Added REST API proposal for OSM Notes Analytics and Ingestion

### Changed

- **Country Dimension Handling**: Enhanced country dimension handling in staging procedures
- **Resolution Ratio**: Updated `resolution_ratio` column precision and calculation logic
- **psql Function**: Updated `__psql_with_appname` function for improved argument handling

---

## [2025-12-18] - Automation Detection and Experience Levels

### Added

- **Automation Detection**: Automation detection system in ETL process
- **Experience Levels**: Experience levels system in ETL process

### Changed

- **Error Handling**: Improved error handling and logging in datamart scripts
- **Error Logging**: Corrected error logging in ETL script for datamart processes

---

## [2025-12-16] - Database Connection and Streaming Analytics

### Added

- **LISTEN/NOTIFY Implementation Guide**: Implementation guide in Bash for streaming analytics
- **Real-time Streaming Analytics Plan**: Implementation plan for real-time streaming analytics
- **Function Existence Check**: Function existence check and safe trigger disablement in ETL script
- **Database Connection Verification**: Enhanced database connection verification in ETL workflow

### Changed

- **NULL Handling**: Fixed NULL handling for `recent_opened_dimension_id_date` in staging process
- **Error Handling**: Improved error handling in mock ETL script for DWH DDL execution
- **Cleanup Script**: Enhanced cleanupDWH script with additional options

### Removed

- **Obsolete DWH Objects**: Removed obsolete DWH objects from ETL script

---

## [2025-12-15] - PostgreSQL Process Identification Enhancement

### Changed

- **PostgreSQL Application Name**: All scripts now set `PGAPPNAME` to display script names instead
  of "psql" in `pg_stat_activity`
  - `ETL.sh` processes show as `ETL` instead of `psql`
  - Parallel year loads show as `ETL-year-2017`, `ETL-year-2018`, etc. for better identification
  - `datamartUsers.sh` shows as `datamartUsers` with specific names for parallel batches
    (`datamartUsers-batch-1-1000`, `datamartUsers-user-123`)
  - `datamartCountries.sh` shows as `datamartCountries`
  - `datamartGlobal.sh` shows as `datamartGlobal`
- Improved process monitoring: All PostgreSQL connections now use descriptive application names for
  easier identification in `pg_stat_activity`

### Technical Details

- Added `__psql_with_appname()` helper function to all main scripts
- Function sets `PGAPPNAME` environment variable before executing `psql`
- Defaults to script basename (without `.sh` extension) if no custom name provided
- Parallel processes use descriptive names (e.g., `ETL-year-2017`, `datamartUsers-batch-1-1000`)

### Files Modified

- `bin/dwh/ETL.sh`: Added helper function and updated all `psql` calls
- `bin/dwh/datamartUsers/datamartUsers.sh`: Added helper function and updated all `psql` calls
- `bin/dwh/datamartCountries/datamartCountries.sh`: Added helper function and updated all `psql`
  calls
- `bin/dwh/datamartGlobal/datamartGlobal.sh`: Added helper function and updated all `psql` calls

### Documentation

- Updated `docs/Troubleshooting_Guide.md`: Enhanced monitoring queries to use new application names

---

## [2025-12-14] - User Behavior Metric Completion

### Added

- **User Behavior Metric**: Completed user behavior analysis with final missing metric
  - `notes_opened_but_not_closed_by_user` (INTEGER): Number of notes opened by user but never closed
    by same user (closed by others or still open)

### Changed

- Updated `datamartUsers` table: Added 1 new column (78+ total metrics)
- Updated datamartUsers procedure to calculate new metric automatically
- Updated documentation: `docs/Metric_Definitions.md`, `docs/Dashboard_Analysis.md`, `README.md`
- Updated metric counts: 77+ → 78+ metrics for users
- Updated `ToDo/ActionPlan.md`: Marked user behavior patterns as COMPLETED

### Testing

- Added 4 new tests for `notes_opened_but_not_closed_by_user` metric
- Tests validate column existence, non-negative values, logical constraints, and calculability
- Total test count: 166 → 170+ tests

### Technical Details

- Metric calculated using NOT EXISTS subquery to find notes opened by user but not closed by same
  user
- Includes notes closed by others and notes still open
- Relationship:
  `history_whole_open = notes_resolved_count + notes_opened_but_not_closed_by_user + notes_still_open_count`

### Documentation

- Added complete metric definition in `docs/Metric_Definitions.md`:
  - Section 8.4: `notes_opened_but_not_closed_by_user` with business definition, formula,
    interpretation, and use cases

---

## [2025-12-14] - High Priority Metrics Implementation

### Added

- **Application Usage Trends**: New metrics to track application usage patterns over time
  - `application_usage_trends` (JSON): Application usage trends by year for countries and users
  - `version_adoption_rates` (JSON): Version adoption rates by year for countries and users
- **Community Health Metrics** (Countries):
  - `notes_health_score` (DECIMAL): Overall notes health score (0-100) based on resolution rate,
    backlog size, and recent activity
  - `new_vs_resolved_ratio` (DECIMAL): Ratio of new notes created vs resolved notes (last 30 days)
- **User Behavior Metrics** (Users):
  - `user_response_time` (DECIMAL): Average time in days from note open to first comment by user
  - `days_since_last_action` (INTEGER): Days since user last performed any action
  - `collaboration_patterns` (JSON): Collaboration metrics including mentions given/received,
    replies count, and collaboration score

### Changed

- Updated `datamartCountries` table: Added 4 new columns (77+ total metrics)
- Updated `datamartUsers` table: Added 5 new columns (77+ total metrics)
- Updated datamart procedures to calculate new metrics automatically
- Updated documentation: `docs/Dashboard_Analysis.md`, `docs/Metric_Definitions.md`, `README.md`
- Updated metric counts: 70+ → 77+ metrics per user/country

### Testing

- Added comprehensive test suite: `tests/unit/bash/datamart_high_priority_metrics.test.bats`
- 23 new tests covering all new metrics
- Tests validate column existence, data types, ranges, and JSON structure
- Total test count: 168+ → 191+ tests

### Technical Details

- All new metrics are calculated during datamart update procedures
- JSON metrics (`application_usage_trends`, `version_adoption_rates`, `collaboration_patterns`) use
  PostgreSQL JSON aggregation
- Health score uses weighted formula: resolution_rate (40%) + backlog_ratio (30%) + recent_activity
  (30%)
- New metrics are automatically exported to JSON (schemas have `additionalProperties: true`)
- Schema hash detection will automatically detect changes for versioning

### Documentation

- Added complete metric definitions in `docs/Metric_Definitions.md`:
  - Section 3.5: `application_usage_trends`
  - Section 3.6: `version_adoption_rates`
  - Section 7.6: `notes_health_score`
  - Section 7.7: `new_vs_resolved_ratio`
  - Section 8: User Behavior Metrics (3 new metrics)
- Updated `docs/Dashboard_Analysis.md` with implementation status
- Updated `README.md` with new metric counts

### Files Modified

- `sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql`
- `sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`
- `sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql`
- `sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`
- `tests/unit/bash/datamart_high_priority_metrics.test.bats` (new)
- `docs/Dashboard_Analysis.md`
- `docs/Metric_Definitions.md`
- `README.md`

## [2025-12-13] - Hybrid Strategy Improvements and Bug Fixes

### Fixed

- Fixed FDW setup logic to only configure Foreign Data Wrappers when Ingestion and Analytics
  databases are different
- Improved error handling when databases are the same (skips FDW setup to avoid conflicts)
- Enhanced database comparison logic in ETL incremental processing

### Changed

- Updated `sql/dwh/ETL_60_setupFDW.sql` version to 2025-12-13
- Improved logging in ETL process to show database configuration before FDW setup
- Enhanced `bin/dwh/copyBaseTables.sh` and `bin/dwh/dropCopiedBaseTables.sh` with better error
  handling and code formatting
- Updated test suite `tests/unit/bash/hybrid_strategy_copy_fdw.test.bats` with improved robustness
  and error handling

### Technical Details

- ETL now compares `DBNAME_INGESTION` and `DBNAME_DWH` before attempting FDW setup
- When databases are the same, FDW setup is skipped to prevent SQL errors
- Added explicit logging for database configuration to aid debugging

## [2025-10-27] - Hybrid Strategy: Database Separation with Table Copying and Remote Access

### Added

- Hybrid strategy for separating Ingestion and Analytics databases
- `bin/dwh/copyBaseTables.sh`: Script to copy base tables from Ingestion DB to Analytics DB for
  initial load
- `bin/dwh/dropCopiedBaseTables.sh`: Script to drop copied tables after DWH population
- `sql/dwh/ETL_60_setupFDW.sql`: SQL script to configure Foreign Data Wrappers (FDW) for incremental
  processing
- Support for separate database configuration:
  - `DBNAME_INGESTION` and `DBNAME_DWH` variables for separate databases
  - `DB_USER_INGESTION` and `DB_USER_DWH` variables for different database users
  - `FDW_INGESTION_*` variables for Foreign Data Wrappers configuration (host, dbname, port, user,
    password)
- Automatic detection of first execution vs incremental execution in ETL process
- Foreign Data Wrappers (postgres_fdw) support for remote table access
- Foreign tables for: `notes`, `note_comments`, `note_comments_text`, `users`, `countries`
- Performance optimization: Copy tables locally for initial load (avoids millions of cross-database
  queries)
- Row count verification after table copying
- Automatic index recreation on copied tables
- Comprehensive test suite: `tests/unit/bash/hybrid_strategy_copy_fdw.test.bats`

### Changed

- ETL process now supports hybrid execution mode:
  - Initial load: Copies base tables locally, processes without FDW overhead
  - Incremental execution: Uses Foreign Data Wrappers for accessing new data from remote database
- Improved ETL performance for initial loads by using local table copies instead of remote queries
- ETL automatically detects first execution and triggers table copying workflow
- ETL automatically detects incremental execution and configures FDW if needed

### Technical Details

- Copy method uses PostgreSQL COPY with piping for maximum performance (estimated 10-40 minutes for
  all tables)
- Tables copied in dependency order: `countries`, `users`, `notes`, `note_comments`,
  `note_comments_text`
- Foreign Data Wrappers configured with `fetch_size='10000'` and `use_remote_estimate='true'` for
  optimization
- Backward compatibility: Falls back to single database mode if separate databases are not
  configured
- Supports peer authentication when database users are not explicitly provided

### Documentation

- Added `docs/Hybrid_Strategy_Copy_FDW.md`: Complete guide for hybrid strategy implementation
- Added `docs/Hybrid_ETL_Execution_Guide.md`: Guide for testing hybrid ETL execution
- Updated `docs/README.md` with references to hybrid strategy documentation

### Testing

- Added unit tests for hybrid strategy: `tests/unit/bash/hybrid_strategy_copy_fdw.test.bats`
- Tests cover table copying, FDW setup, and incremental processing scenarios
- Tests validate row count verification and error handling
