# Lib Directory

This directory contains shared libraries and common functions used across all scripts in the
OSM-Notes-Analytics project.

## Overview

The `lib/` directory provides reusable Bash functions and utilities that promote code consistency,
reduce duplication, and improve maintainability across the project.

## Directory Structure

```text
lib/
└── osm-common/                          # Common OSM utilities
    ├── bash_logger.sh                   # Logging framework
    ├── commonFunctions.sh               # Common utility functions
    ├── consolidatedValidationFunctions.sh  # Consolidated validation utilities
    ├── errorHandlingFunctions.sh        # Error handling and trapping
    ├── validationFunctions.sh           # Validation and checking functions
    ├── CONTRIBUTING.md                  # Contribution guidelines for libraries
    ├── LICENSE                          # Library license
    └── README.md                        # Library documentation
```

## Library Files

### 1. bash_logger.sh

**Purpose:** Comprehensive logging framework for all Bash scripts.

**Features:**

- Multiple log levels (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
- Configurable output (console, file, both)
- Timestamp and script name in log entries
- Function call stack tracking
- Colored output for terminals
- Log rotation support

**Usage:**

```bash
# Source the logger
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/bash_logger.sh"

# Initialize logger
__start_logger

# Set log level (default: ERROR)
export LOG_LEVEL="INFO"

# Log messages
__logt "This is a trace message"    # Very detailed debugging
__logd "This is a debug message"    # Debugging information
__logi "This is an info message"    # General information
__logw "This is a warning message"  # Warning conditions
__loge "This is an error message"   # Error conditions
__logf "This is a fatal message"    # Fatal errors

# Log function entry/exit
__log_start  # Call at start of function
__log_finish # Call at end of function

# Set log file
__set_log_file "/path/to/logfile.log"
```

**Log Levels:**

| Level | When to Use             | Example                                 |
| ----- | ----------------------- | --------------------------------------- |
| TRACE | Very detailed debugging | Variable values, loop iterations        |
| DEBUG | Detailed debugging      | Function calls, intermediate results    |
| INFO  | General information     | Progress updates, milestones            |
| WARN  | Warning conditions      | Deprecated usage, potential issues      |
| ERROR | Error conditions        | Recoverable errors, validation failures |
| FATAL | Fatal errors            | Unrecoverable errors requiring exit     |

**Example Output:**

```text
2025-10-14 10:30:15 [INFO] ETL.sh: Starting ETL process
2025-10-14 10:30:16 [DEBUG] ETL.sh: Loading configuration from etc/properties.sh
2025-10-14 10:30:20 [INFO] ETL.sh: Connected to database: notes_dwh
2025-10-14 10:30:25 [WARN] ETL.sh: Large dataset detected, parallel processing recommended
2025-10-14 10:45:32 [ERROR] ETL.sh: Failed to load staging table for year 2015
2025-10-14 10:45:33 [INFO] ETL.sh: Retrying operation (attempt 2/3)
```

**Configuration:**

```bash
# Log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
export LOG_LEVEL="INFO"

# Log to file
__set_log_file "/tmp/mylog.log"

# Log function calls
export LOG_FUNCTION_CALLS=true
```

### 2. commonFunctions.sh

**Purpose:** Common utility functions used across multiple scripts.

**Functions:**

#### \_\_checkPrereqsCommands

Checks if required commands are available.

```bash
# Usage
__checkPrereqsCommands

# Checks for:
# - psql (PostgreSQL client)
# - bash (version 4.0+)
# - date, awk, sed, grep
```

#### \_\_waitForJobs

Manages parallel job execution by waiting for jobs to complete.

```bash
# Usage
__waitForJobs

# Features:
# - Respects MAX_THREADS setting
# - Monitors system resources
# - Prevents CPU monopolization
```

#### \_\_start_logger

Initializes the logging system.

```bash
# Usage
__start_logger

# Sets up:
# - Log level
# - Output destinations
# - Log formatting
```

**Usage Example:**

```bash
#!/bin/bash

# Source common functions
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

# Initialize logger
__start_logger

# Check prerequisites
__checkPrereqsCommands

# Run parallel jobs
for year in 2020 2021 2022; do
  __waitForJobs  # Wait if too many jobs
  process_year $year &
done

wait  # Wait for all jobs to complete
```

### 3. validationFunctions.sh

**Purpose:** Validation functions for files, configuration, and data.

**Functions:**

#### \_\_validate_sql_structure

Validates SQL file structure and syntax.

```bash
# Usage
if __validate_sql_structure "path/to/file.sql"; then
  echo "SQL file is valid"
else
  echo "SQL file has errors"
fi

# Checks:
# - File exists and is readable
# - Basic SQL syntax
# - Required keywords present
# - No obvious syntax errors
```

#### \_\_validate_config_file

Validates configuration file format and content.

```bash
# Usage
if __validate_config_file "etc/properties.sh"; then
  echo "Configuration is valid"
else
  echo "Configuration has errors"
fi

# Validates:
# - File syntax (shell script)
# - Required variables defined
# - Valid values for settings
# - No dangerous commands
```

#### \_\_validate_database_connection

Tests database connectivity.

```bash
# Usage
if __validate_database_connection; then
  echo "Database connection OK"
else
  echo "Cannot connect to database"
fi

# Tests:
# - psql can connect
# - Database exists
# - Required extensions (PostGIS)
# - Schema access
```

**Usage Example:**

```bash
#!/bin/bash

source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"

# Validate SQL files
for sql_file in sql/dwh/*.sql; do
  if ! __validate_sql_structure "$sql_file"; then
    echo "ERROR: Invalid SQL file: $sql_file"
    exit 1
  fi
done

# Validate configuration
if ! __validate_config_file "etc/properties.sh"; then
  echo "ERROR: Invalid configuration"
  exit 1
fi

# Test database
if ! __validate_database_connection; then
  echo "ERROR: Cannot connect to database"
  exit 1
fi
```

### 4. errorHandlingFunctions.sh

**Purpose:** Centralized error handling and trap management.

**Functions:**

#### \_\_trapOn

Sets up error traps for catching failures.

```bash
# Usage
__trapOn

# Sets up traps for:
# - ERR (command failures)
# - EXIT (script exit)
# - INT (Ctrl+C)
# - TERM (kill signal)
```

#### \_\_handle_error

Handles errors consistently.

```bash
# Usage (automatic via trap)
# Provides:
# - Error line number
# - Failed command
# - Exit code
# - Stack trace
```

#### \_\_cleanup

Cleanup function called on exit.

```bash
# Usage (automatic via trap)
# Performs:
# - Temporary file removal
# - Lock file cleanup
# - Database disconnection
# - Log finalization
```

**Usage Example:**

```bash
#!/bin/bash

source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"

# Set strict error handling
set -euo pipefail

# Set up error traps
__trapOn

# Your script logic here
# Errors will be caught and handled automatically

function main() {
  # Do work
  risky_operation

  # If this fails, __handle_error is called automatically
}

main
```

### 5. consolidatedValidationFunctions.sh

**Purpose:** Consolidated set of validation functions for comprehensive checking.

**Features:**

- Combines validation from multiple sources
- Provides unified validation interface
- Supports batch validation
- Generates validation reports

**Functions:**

- All functions from `validationFunctions.sh`
- Additional specialized validators
- Batch validation utilities

**Usage:**

```bash
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/consolidatedValidationFunctions.sh"

# Validate entire project
__validate_project_structure
__validate_all_sql_files
__validate_all_config_files
__validate_all_scripts
```

## Common Usage Patterns

### Standard Script Header

```bash
#!/bin/bash

# Script description
# Author: Your Name
# Version: 2025-10-14

# Strict error handling
set -euo pipefail

# Base directory
SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly SCRIPT_BASE_DIRECTORY

# Load configuration
source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"

# Load libraries
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"

# Initialize logger
__start_logger

# Set up error handling
__trapOn

# Log level
declare LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Your script logic...
```

### Error Handling Pattern

```bash
# Set up error handling
__trapOn

function risky_operation() {
  __log_start

  # This will be caught if it fails
  some_command_that_might_fail

  __log_finish
}

# Automatic error handling - no try/catch needed
risky_operation
```

### Validation Pattern

```bash
# Validate prerequisites
__checkPrereqsCommands

# Validate SQL files
for sql_file in sql/dwh/*.sql; do
  if ! __validate_sql_structure "$sql_file"; then
    __loge "Invalid SQL: $sql_file"
    exit 1
  fi
done

# Validate database connection
if ! __validate_database_connection; then
  __loge "Database connection failed"
  exit 1
fi
```

### Parallel Processing Pattern

```bash
# Process items in parallel
for item in "${items[@]}"; do
  __waitForJobs  # Respect MAX_THREADS

  (
    __logi "Processing $item"
    process_item "$item"
  ) &
done

# Wait for all background jobs
wait
```

## Error Codes

Standard error codes used across the project:

| Code | Meaning            | Usage                                 |
| ---- | ------------------ | ------------------------------------- |
| 0    | Success            | Normal exit                           |
| 1    | Help message       | User requested help                   |
| 241  | Missing library    | Required library/utility not found    |
| 242  | Invalid argument   | Script called with invalid parameters |
| 243  | Logger unavailable | Logging system initialization failed  |

**Usage in scripts:**

```bash
# Define at top of script
declare -r ERROR_HELP_MESSAGE=1
declare -r ERROR_MISSING_LIBRARY=241
declare -r ERROR_INVALID_ARGUMENT=242
declare -r ERROR_LOGGER_UNAVAILABLE=243

# Use in code
if [[ $# -eq 0 ]]; then
  show_help
  exit "${ERROR_HELP_MESSAGE}"
fi
```

## Library Development

### Adding New Functions

1. **Choose appropriate library file:**
   - Logging → `bash_logger.sh`
   - Utilities → `commonFunctions.sh`
   - Validation → `validationFunctions.sh`
   - Error handling → `errorHandlingFunctions.sh`

2. **Function naming convention:**
   - Prefix with double underscore: `__function_name`
   - Use lowercase with underscores
   - Descriptive names

3. **Function template:**

```bash
# Description of what the function does
# Usage: __my_function "arg1" "arg2"
# Returns: 0 on success, 1 on failure
function __my_function() {
  __log_start

  local arg1="${1}"
  local arg2="${2}"

  # Validation
  if [[ -z "${arg1}" ]]; then
    __loge "arg1 is required"
    __log_finish
    return 1
  fi

  # Function logic
  # ...

  __log_finish
  return 0
}
```

4. **Add documentation:**
   - Add function to this README
   - Include usage examples
   - Document parameters and return values

5. **Test the function:**

```bash
# Create test script
#!/bin/bash
source lib/osm-common/commonFunctions.sh

# Test new function
if __my_function "test" "args"; then
  echo "Success"
else
  echo "Failed"
fi
```

### Testing Libraries

```bash
# Test logger
source lib/osm-common/bash_logger.sh
__start_logger
export LOG_LEVEL="DEBUG"
__logd "Test message"

# Test validation
source lib/osm-common/validationFunctions.sh
__validate_sql_structure "sql/dwh/ETL_20_createDWHTables.sql"

# Test error handling
source lib/osm-common/errorHandlingFunctions.sh
__trapOn
false  # Should trigger error handler
```

## Best Practices

1. **Always source from SCRIPT_BASE_DIRECTORY:**

```bash
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"
```

2. **Initialize logger early:**

```bash
__start_logger
```

3. **Set up error handling:**

```bash
__trapOn
```

4. **Use **log_start/**log_finish in functions:**

```bash
function my_function() {
  __log_start
  # ... code ...
  __log_finish
}
```

5. **Check prerequisites before execution:**

```bash
__checkPrereqsCommands
```

6. **Validate inputs:**

```bash
if [[ -z "${REQUIRED_VAR}" ]]; then
  __loge "REQUIRED_VAR must be set"
  exit 1
fi
```

## Troubleshooting

### "Function not found" errors

Ensure library is sourced:

```bash
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"
```

Check SCRIPT_BASE_DIRECTORY is set:

```bash
echo "${SCRIPT_BASE_DIRECTORY}"
```

### Logging not working

Initialize logger:

```bash
__start_logger
```

Set log level:

```bash
export LOG_LEVEL="DEBUG"
```

### Validation failures

Check with verbose output:

```bash
set -x  # Enable debug output
__validate_sql_structure "file.sql"
set +x  # Disable debug output
```

## Integration with OSM-Notes-Common

These libraries are maintained in the
**[OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common)** repository:

- **Repository**: [OSM-Notes-Common](https://github.com/OSM-Notes/OSM-Notes-Common)
- **Location**: `lib/osm-common/` (Git submodule)
- **Shared with**: OSM-Notes-Ingestion, OSM-Notes-Analytics (and potentially OSM-Notes-Viewer)
- **Versioning**: Independent versioning
- **Compatibility**: Changes should be backward compatible
- **Testing**: Test in all projects before committing changes

**Update submodule:**

```bash
cd lib/osm-common
git pull origin main
cd ../..
git add lib/osm-common
git commit -m "Update OSM-Notes-Common submodule"
```

**Initialize submodule (if missing):**

```bash
git submodule update --init --recursive
```

## Related Documentation

### Project Documentation

- **[Main README](../README.md)** - Project overview
- **[Contributing Guide](../CONTRIBUTING.md)** - Development standards and library usage
- **[bin/README.md](../bin/README.md)** - Script usage examples
- **[docs/Rationale.md](../docs/Rationale.md)** - Project context and design decisions

### Library Documentation

- **[OSM-Notes-Common Repository](https://github.com/OSM-Notes/OSM-Notes-Common)** - Source
  repository
- **[lib/osm-common/README.md](osm-common/README.md)** - Detailed library documentation

### External References

- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)

## References

- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)

## Support

For library-related issues:

1. Check library documentation: `lib/osm-common/README.md`
2. Test library functions in isolation
3. Review error messages and stack traces
4. Create an issue with minimal reproduction case
