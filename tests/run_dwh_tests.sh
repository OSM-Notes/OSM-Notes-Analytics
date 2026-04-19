#!/bin/bash

# Run DWH and ETL tests for OSM-Notes-Analytics
# Author: Andres Gomez (AngocA)
# Version: 2025-10-14

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
 echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
 echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
 echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
 echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Export project root for tests
export SCRIPT_BASE_DIRECTORY="${PROJECT_ROOT}"

# Load test properties
if [[ -f "${SCRIPT_DIR}/properties.sh" ]]; then
 # shellcheck source=tests/properties.sh
 source "${SCRIPT_DIR}/properties.sh"
else
 log_error "Test properties not found"
 exit 1
fi

# Ensure critical variables have defaults after loading properties
# Only set defaults if we're in CI/CD environment (TEST_DBHOST is set)
# For local environment, don't set TEST_DBHOST to allow peer authentication
export TEST_DBNAME="${TEST_DBNAME:-osm_notes_analytics_test}"
if [[ -n "${TEST_DBHOST:-}" ]] || [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
 # CI/CD environment - set defaults for host/port/user
 export TEST_DBHOST="${TEST_DBHOST:-localhost}"
 export TEST_DBPORT="${TEST_DBPORT:-5432}"
 export TEST_DBUSER="${TEST_DBUSER:-postgres}"
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-postgres}"
else
 # Local environment - don't set TEST_DBHOST to use peer authentication
 # TEST_DBNAME is already set above
 export TEST_DBPORT="${TEST_DBPORT:-}"
 export TEST_DBUSER="${TEST_DBUSER:-}"
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-}"
fi

# Single test database: ETL must read ingestion + DWH from TEST_DBNAME in CI/local test runs.
export DBNAME_INGESTION="${DBNAME_INGESTION:-${TEST_DBNAME}}"
export DBNAME_DWH="${DBNAME_DWH:-${TEST_DBNAME}}"

# ETL always checks public.properties.base_load_complete on DBNAME_INGESTION.
log_info "Applying test ingestion marker base_load_complete on database ${TEST_DBNAME}..."
if [[ -n "${TEST_DBHOST:-}" ]]; then
 PGPASSWORD="${TEST_DBPASSWORD:-postgres}" psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT:-5432}" \
  -U "${TEST_DBUSER:-postgres}" -d "${TEST_DBNAME}" -v ON_ERROR_STOP=1 \
  -f "${PROJECT_ROOT}/tests/sql/ensure_test_ingestion_base_load_complete.sql"
else
 psql -d "${TEST_DBNAME}" -v ON_ERROR_STOP=1 \
  -f "${PROJECT_ROOT}/tests/sql/ensure_test_ingestion_base_load_complete.sql"
fi

# Check if BATS is installed
if ! command -v bats &> /dev/null; then
 log_error "BATS is not installed. Please install it first:"
 echo "  # Ubuntu/Debian:"
 echo "  sudo apt-get install bats"
 echo ""
 echo "  # macOS:"
 echo "  brew install bats-core"
 echo ""
 echo "  # Manual installation:"
 echo "  git clone https://github.com/bats-core/bats-core.git"
 echo "  cd bats-core"
 echo "  sudo ./install.sh /usr/local"
 exit 1
fi

log_info "Starting DWH and ETL tests..."
echo "======================================"
echo "Test Execution Environment"
echo "======================================"
echo "Project Root: ${PROJECT_ROOT}"
echo "Script Directory: ${SCRIPT_DIR}"
echo "Test Database: ${TEST_DBNAME:-not set}"
if [[ -n "${TEST_DBHOST:-}" ]]; then
 echo "Test DB Host: ${TEST_DBHOST}"
 echo "Test DB Port: ${TEST_DBPORT:-5432}"
 echo "Test DB User: ${TEST_DBUSER:-postgres}"
 echo "Test DB Password: ${TEST_DBPASSWORD:+***set***}"
else
 echo "Test DB Host: (local - peer authentication)"
 echo "Test DB Port: (local socket)"
 echo "Test DB User: (current user: $(whoami))"
fi
echo "BATS Version: $(bats --version 2> /dev/null || echo 'unknown')"
echo "BATS Location: $(command -v bats)"
echo "CI Environment: ${CI:-false}"
echo "GitHub Actions: ${GITHUB_ACTIONS:-false}"
echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "======================================"
echo ""

# Counter for test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TEST_FILES=()

# Function to run a test suite
run_test_suite() {
 local test_file="$1"
 local test_name
 test_name="$(basename "${test_file}")"
 local start_time
 start_time=$(date +%s)

 log_info "Running ${test_name}..."
 log_info "  Test file: ${test_file}"

 # Temporarily disable exit on error to allow test failures to be captured
 set +e
 # Capture both stdout and stderr, preserving colors if possible
 local bats_output_file
 bats_output_file=$(mktemp 2> /dev/null)
 local mktemp_exit_code=$?

 # Verify mktemp succeeded
 if [[ ${mktemp_exit_code} -ne 0 ]] || [[ -z "${bats_output_file}" ]] || [[ ! -f "${bats_output_file}" ]]; then
  log_error "Failed to create temporary file for test output (mktemp exit code: ${mktemp_exit_code})"
  log_error "This may indicate /tmp is full or permissions issue"
  # Fallback: use a file in the project's output directory or current directory
  bats_output_file="${SCRIPT_DIR}/.bats_output_$$.tmp"
  if ! touch "${bats_output_file}" 2> /dev/null; then
   log_error "Failed to create fallback output file: ${bats_output_file}"
   log_error "Running tests without output capture - failure details may be limited"
   bats_output_file=""
  fi
 fi

 # Run bats with verbose output for better debugging
 if [[ -n "${bats_output_file}" ]] && [[ -f "${bats_output_file}" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
   # In CI, use tap format for better parsing, but also show verbose output
   bats --tap --show-output-of-passing-tests "${test_file}" 2>&1 | tee "${bats_output_file}"
  else
   # Local execution - use default format
   bats --show-output-of-passing-tests "${test_file}" 2>&1 | tee "${bats_output_file}"
  fi
 else
  # No output file available - run without capture
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
   bats --tap --show-output-of-passing-tests "${test_file}"
  else
   bats --show-output-of-passing-tests "${test_file}"
  fi
 fi
 local bats_exit_code=${PIPESTATUS[0]}
 set -e

 local end_time
 end_time=$(date +%s)
 local duration=$((end_time - start_time))

 if [[ ${bats_exit_code} -eq 0 ]]; then
  log_success "${test_name} passed (${duration}s)"
  PASSED_TESTS=$((PASSED_TESTS + 1))
 else
  log_error "${test_name} failed (exit code: ${bats_exit_code}, duration: ${duration}s)"
  FAILED_TESTS=$((FAILED_TESTS + 1))
  FAILED_TEST_FILES+=("${test_name}")

  # Show detailed failure information
  log_error "=== Detailed failure information for ${test_name} ==="
  log_error "Exit code: ${bats_exit_code}"
  log_error "Test file: ${test_file}"

  # Only extract detailed information if output file exists and is readable
  if [[ -n "${bats_output_file}" ]] && [[ -f "${bats_output_file}" ]] && [[ -r "${bats_output_file}" ]]; then
   # Extract failed test names from BATS output
   # Check for TAP format (not ok) or BATS format (✗ or failing)
   if grep -qE "(not ok|✗|failing)" "${bats_output_file}" 2> /dev/null; then
    log_error "Failed tests in ${test_name}:"
    # Extract TAP format failures
    grep -E "not ok" "${bats_output_file}" 2> /dev/null | sed 's/^/  [TAP] /' | while IFS= read -r line || [[ -n "${line}" ]]; do
     log_error "${line}"
    done
    # Extract BATS format failures (lines with ✗ or "failing")
    grep -E "(✗|failing)" "${bats_output_file}" 2> /dev/null | head -n 10 | sed 's/^/  [BATS] /' | while IFS= read -r line || [[ -n "${line}" ]]; do
     log_error "${line}"
    done
   fi

   # Show error messages from the output
   if grep -qE "(ERROR|FAIL|Error|error)" "${bats_output_file}" 2> /dev/null; then
    log_error "Error messages found in output:"
    grep -E "(ERROR|FAIL|Error|error)" "${bats_output_file}" 2> /dev/null | head -n 15 | sed 's/^/  /' | while IFS= read -r line || [[ -n "${line}" ]]; do
     log_error "${line}"
    done
   fi

   # Show last 30 lines of output for context (increased from 20)
   log_error "Last 30 lines of test output:"
   tail -n 30 "${bats_output_file}" 2> /dev/null | sed 's/^/  /' | while IFS= read -r line || [[ -n "${line}" ]]; do
    log_error "${line}"
   done
  else
   log_error "Test output file not available - detailed failure information cannot be extracted"
   log_error "This may indicate a problem creating temporary files (e.g., /tmp is full)"
  fi

  log_error "=== End of failure information for ${test_name} ==="
 fi

 # Clean up temp file (only if it exists and is valid)
 if [[ -n "${bats_output_file}" ]] && [[ -f "${bats_output_file}" ]]; then
  rm -f "${bats_output_file}" 2> /dev/null || true
 fi

 TOTAL_TESTS=$((TOTAL_TESTS + 1))
 echo ""
}

# Setup: Generate mock data and populate DWH
log_info "Setting up test environment..."
echo "===================="

# Run mock ETL to populate test database
if [[ -f "${SCRIPT_DIR}/run_mock_etl.sh" ]]; then
 log_info "Populating test database with mock data..."
 log_info "Database connection info:"
 log_info "  TEST_DBNAME=${TEST_DBNAME:-}"
 log_info "  TEST_DBHOST=${TEST_DBHOST:-}"
 log_info "  TEST_DBPORT=${TEST_DBPORT:-}"
 log_info "  TEST_DBUSER=${TEST_DBUSER:-}"
 log_info "  TEST_DBPASSWORD=${TEST_DBPASSWORD:+***set***}"

 # Ensure all required variables are set for CI/CD environment
 if [[ -n "${TEST_DBHOST:-}" ]]; then
  if [[ -z "${TEST_DBNAME:-}" ]]; then
   log_error "TEST_DBNAME is required but not set"
   exit 1
  fi
  if [[ -z "${TEST_DBUSER:-}" ]]; then
   log_error "TEST_DBUSER is required but not set"
   exit 1
  fi
  # Export variables to ensure they're available to subprocesses
  export TEST_DBNAME TEST_DBHOST TEST_DBPORT TEST_DBUSER TEST_DBPASSWORD
  export PGHOST="${TEST_DBHOST}"
  export PGPORT="${TEST_DBPORT:-5432}"
  export PGUSER="${TEST_DBUSER}"
  export PGPASSWORD="${TEST_DBPASSWORD:-postgres}"
  export PGDATABASE="${TEST_DBNAME}"
 fi

 # Verify database connection before running mock ETL
 # Use appropriate connection method based on environment
 if [[ -n "${TEST_DBHOST:-}" ]]; then
  # CI/CD environment - use host/port/user
  log_info "Verifying database connection (CI/CD mode)..."
  set +e
  CONNECTION_OUTPUT=$(PGPASSWORD="${TEST_DBPASSWORD:-postgres}" psql -h "${TEST_DBHOST}" -p "${TEST_DBPORT:-5432}" -U "${TEST_DBUSER:-postgres}" -d "${TEST_DBNAME}" -c "SELECT 1;" 2>&1)
  CONNECTION_EXIT_CODE=$?
  set -e
  if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
   log_warning "Cannot connect to database before running mock ETL"
   log_warning "Connection attempt failed with exit code: ${CONNECTION_EXIT_CODE}"
   log_warning "Connection details:"
   log_warning "  Host: ${TEST_DBHOST}"
   log_warning "  Port: ${TEST_DBPORT:-5432}"
   log_warning "  User: ${TEST_DBUSER:-postgres}"
   log_warning "  Database: ${TEST_DBNAME}"
   log_warning "  Password: ${TEST_DBPASSWORD:+***set***}"
   log_warning "Error output:"
   if [[ -n "${CONNECTION_OUTPUT}" ]]; then
    echo "${CONNECTION_OUTPUT}" | sed 's/^/  /' | while IFS= read -r line || [[ -n "${line}" ]]; do
     log_warning "${line}"
    done
   else
    log_warning "  (No error output captured)"
   fi
   log_warning "Continuing with tests - individual tests will skip if database is unavailable"
   export DB_CONNECTION_FAILED=1
  else
   log_success "Database connection verified"
  fi
 else
  # Local environment - use peer authentication
  log_info "Verifying database connection (local mode)..."
  set +e
  CONNECTION_OUTPUT=$(psql -d "${TEST_DBNAME}" -c "SELECT 1;" 2>&1)
  CONNECTION_EXIT_CODE=$?
  set -e
  if [[ ${CONNECTION_EXIT_CODE} -ne 0 ]]; then
   log_warning "Cannot connect to database before running mock ETL"
   log_warning "Connection attempt failed with exit code: ${CONNECTION_EXIT_CODE}"
   log_warning "Database: ${TEST_DBNAME}"
   log_warning "Error output:"
   if [[ -n "${CONNECTION_OUTPUT}" ]]; then
    echo "${CONNECTION_OUTPUT}" | sed 's/^/  /' | while IFS= read -r line || [[ -n "${line}" ]]; do
     log_warning "${line}"
    done
   else
    log_warning "  (No error output captured)"
   fi
   log_warning "Continuing with tests - individual tests will skip if database is unavailable"
   export DB_CONNECTION_FAILED=1
  else
   log_success "Database connection verified"
  fi
 fi

 if [[ "${DB_CONNECTION_FAILED:-0}" -eq 0 ]]; then
  log_info "Running mock ETL script..."
  # Ensure all environment variables are exported for the child script
  export TEST_DBNAME TEST_DBHOST TEST_DBPORT TEST_DBUSER TEST_DBPASSWORD
  export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
  if bash "${SCRIPT_DIR}/run_mock_etl.sh" 2>&1; then
   log_success "Test database populated"
  else
   EXIT_CODE=$?
   log_warning "Failed to populate test database with mock data"
   log_warning "Exit code: ${EXIT_CODE}"
   log_warning "Check the output above for detailed error messages"
   log_warning "Continuing with tests - individual tests will skip if database is unavailable"
   export DB_CONNECTION_FAILED=1
  fi
 else
  log_warning "Skipping mock ETL script due to database connection failure"
 fi
else
 log_warning "Mock ETL script not found, skipping data setup"
fi

echo ""

# Run unit tests
log_info "Running unit tests..."
echo "======================================"
log_info "Unit tests directory: ${SCRIPT_DIR}/unit/bash"

# Count test files before running
unit_test_count=0
if [[ -d "${SCRIPT_DIR}/unit/bash" ]]; then
 for test_file in "${SCRIPT_DIR}"/unit/bash/*.bats; do
  if [[ -f "${test_file}" ]]; then
   unit_test_count=$((unit_test_count + 1))
  fi
 done
 log_info "Found ${unit_test_count} unit test file(s)"
else
 log_warning "Unit tests directory not found: ${SCRIPT_DIR}/unit/bash"
fi
echo ""

if [[ -d "${SCRIPT_DIR}/unit/bash" ]] && [[ ${unit_test_count} -gt 0 ]]; then
 test_num=0
 for test_file in "${SCRIPT_DIR}"/unit/bash/*.bats; do
  if [[ -f "${test_file}" ]]; then
   test_num=$((test_num + 1))
   log_info "[${test_num}/${unit_test_count}] Processing unit test file..."
   run_test_suite "${test_file}"
  fi
 done
else
 log_warning "No unit bash tests found or directory doesn't exist"
fi

# Run integration tests
log_info "Running integration tests..."
echo "======================================"
log_info "Integration tests directory: ${SCRIPT_DIR}/integration"

# Count test files before running
integration_test_count=0
if [[ -d "${SCRIPT_DIR}/integration" ]]; then
 for test_file in "${SCRIPT_DIR}"/integration/*.bats; do
  if [[ -f "${test_file}" ]]; then
   integration_test_count=$((integration_test_count + 1))
  fi
 done
 log_info "Found ${integration_test_count} integration test file(s)"
else
 log_warning "Integration tests directory not found: ${SCRIPT_DIR}/integration"
fi
echo ""

if [[ -d "${SCRIPT_DIR}/integration" ]] && [[ ${integration_test_count} -gt 0 ]]; then
 test_num=0
 for test_file in "${SCRIPT_DIR}"/integration/*.bats; do
  if [[ -f "${test_file}" ]]; then
   test_num=$((test_num + 1))
   log_info "[${test_num}/${integration_test_count}] Processing integration test file..."
   run_test_suite "${test_file}"
  fi
 done
else
 log_warning "No integration tests found or directory doesn't exist"
fi

# Show summary
echo ""
echo "======================================"
log_info "Test Execution Summary"
echo "======================================"
echo "Total Test Suites: ${TOTAL_TESTS}"
echo "Passed: ${PASSED_TESTS} ✅"
echo "Failed: ${FAILED_TESTS} ❌"
echo "End Time: $(date '+%Y-%m-%d %H:%M:%S')"

if [[ ${FAILED_TESTS} -gt 0 ]]; then
 echo ""
 log_error "Failed Test Files:"
 for failed_file in "${FAILED_TEST_FILES[@]}"; do
  log_error "  - ${failed_file}"
 done
fi

# Calculate success rate
success_rate=0
if [[ ${TOTAL_TESTS} -gt 0 ]]; then
 success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
fi
echo "Success Rate: ${success_rate}%"
echo "======================================"

# Save detailed summary to file for CI/CD
{
 echo "======================================"
 echo "DWH Tests Summary"
 echo "======================================"
 echo "Total Test Suites: ${TOTAL_TESTS}"
 echo "Passed: ${PASSED_TESTS}"
 echo "Failed: ${FAILED_TESTS}"
 echo "Success Rate: ${success_rate}%"
 echo ""
 if [[ ${FAILED_TESTS} -gt 0 ]]; then
  echo "Failed Test Files:"
  for failed_file in "${FAILED_TEST_FILES[@]}"; do
   echo "  - ${failed_file}"
  done
  echo ""
 fi
 echo "Test completed at: $(date '+%Y-%m-%d %H:%M:%S')"
 echo "Environment:"
 echo "  TEST_DBNAME: ${TEST_DBNAME:-not set}"
 echo "  TEST_DBHOST: ${TEST_DBHOST:-not set}"
 echo "  TEST_DBUSER: ${TEST_DBUSER:-not set}"
 echo "  CI: ${CI:-false}"
 echo "  GITHUB_ACTIONS: ${GITHUB_ACTIONS:-false}"
} > /tmp/all_tests_output.txt 2>&1 || true

if [[ ${FAILED_TESTS} -eq 0 ]]; then
 log_success "All tests passed! ✅"
 exit 0
else
 log_error "${FAILED_TESTS} test suite(s) failed ❌"
 log_error "Review the detailed failure information above for each failed test"
 exit 1
fi
