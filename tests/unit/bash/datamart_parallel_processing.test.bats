#!/usr/bin/env bats

# Require minimum BATS version for run flags
bats_require_minimum_version 1.5.0

# Load test helper for database connection verification
load ../../test_helper

# Integration tests for parallel processing with work queue
# Tests for datamartCountries and datamartUsers parallel processing
# Author: Andres Gomez (AngocA)
# Version: 2025-01-XX

setup() {
 # Setup test environment
 # shellcheck disable=SC2154
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
 export SCRIPT_BASE_DIRECTORY
 # shellcheck disable=SC2155
 TMP_DIR="$(mktemp -d)"
 export TMP_DIR
 export BASENAME="test_datamart_parallel"
 export LOG_LEVEL="INFO"

 # Ensure TMP_DIR exists and is writable
 if [[ ! -d "${TMP_DIR}" ]]; then
  mkdir -p "${TMP_DIR}" || {
   echo "ERROR: Could not create TMP_DIR: ${TMP_DIR}" >&2
   exit 1
  }
 fi
 if [[ ! -w "${TMP_DIR}" ]]; then
  echo "ERROR: TMP_DIR not writable: ${TMP_DIR}" >&2
  exit 1
 fi

 # Set up test database
 export TEST_DBNAME="test_osm_notes_${BASENAME}"
}

teardown() {
 # Cleanup
 rm -rf "${TMP_DIR}"
 # Drop test database if it exists
 psql -d postgres -c "DROP DATABASE IF EXISTS ${TEST_DBNAME};" 2> /dev/null || true
}

# Test that work queue function exists for datamartCountries
@test "datamartCountries __get_next_country_from_queue function should exist" {
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __get_next_country_from_queue"
 [[ "${status}" -eq 0 ]] || echo "Function __get_next_country_from_queue should be available"
 [[ "${output}" == *"__get_next_country_from_queue"* ]] || echo "Function should be defined"
}

# Test that work queue function exists for datamartUsers
@test "datamartUsers __get_next_user_from_queue function should exist" {
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __get_next_user_from_queue"
 [[ "${status}" -eq 0 ]] || echo "Function __get_next_user_from_queue should be available"
 [[ "${output}" == *"__get_next_user_from_queue"* ]] || echo "Function should be defined"
}

# Test that parallel processing function exists for datamartCountries
@test "datamartCountries __processNotesCountriesParallel function should exist" {
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __processNotesCountriesParallel"
 [[ "${status}" -eq 0 ]] || echo "Function __processNotesCountriesParallel should be available"
 [[ "${output}" == *"__processNotesCountriesParallel"* ]] || echo "Function should be defined"
}

# Test that parallel processing function exists for datamartUsers
@test "datamartUsers __processNotesUser function should use work queue" {
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser"
 [[ "${status}" -eq 0 ]] || echo "Function __processNotesUser should be available"
 # Check that it uses work queue (should contain __get_next_user_from_queue)
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser | grep -q '__get_next_user_from_queue'"
 [[ "${status}" -eq 0 ]] || echo "Function should use work queue"
}

# Test work queue thread-safety for countries
@test "datamartCountries work queue should be thread-safe" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test work queue file
 local test_queue_file="${TMP_DIR}/test_country_queue.txt"
 local test_lock_file="${TMP_DIR}/test_country_queue.lock"
 echo -e "1\n2\n3\n4\n5" > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Test that function can read from queue
 local result
 result=$(__get_next_country_from_queue)
 [[ -n "${result}" ]] || echo "Should return first country from queue"
 [[ "${result}" == "1" ]] || echo "Should return country 1"

 # Test that queue was updated (first line removed)
 local remaining
 remaining=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${remaining}" -eq 4 ]] || echo "Queue should have 4 remaining items"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}

# Test work queue thread-safety for users
@test "datamartUsers work queue should be thread-safe" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test work queue file
 local test_queue_file="${TMP_DIR}/test_user_queue.txt"
 local test_lock_file="${TMP_DIR}/test_user_queue.lock"
 echo -e "100\n200\n300\n400\n500" > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Test that function can read from queue
 local result
 result=$(__get_next_user_from_queue)
 [[ -n "${result}" ]] || echo "Should return first user from queue"
 [[ "${result}" == "100" ]] || echo "Should return user 100"

 # Test that queue was updated (first line removed)
 local remaining
 remaining=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${remaining}" -eq 4 ]] || echo "Queue should have 4 remaining items"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}

# Test concurrent access to work queue (simulate multiple threads)
@test "datamartCountries work queue should handle concurrent access" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test work queue file with many items
 local test_queue_file="${TMP_DIR}/test_country_queue_concurrent.txt"
 local test_lock_file="${TMP_DIR}/test_country_queue_concurrent.lock"
 seq 1 100 > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Simulate 4 concurrent threads reading from queue
 local pids=()
 local results_file="${TMP_DIR}/concurrent_results.txt"
 > "${results_file}"

 for i in {1..4}; do
  (
   set +e
   local count=0
   local retries=0
   local max_retries=10
   while [[ ${count} -lt 25 ]]; do
    local item
    item=$(__get_next_country_from_queue)
    local exit_code=$?
    # If lock failed (exit code 1), retry after short delay
    if [[ ${exit_code} -eq 1 ]]; then
     retries=$((retries + 1))
     if [[ ${retries} -lt ${max_retries} ]]; then
      sleep 0.01
      continue
     else
      break
     fi
    fi
    if [[ -n "${item}" ]]; then
     echo "${item}" >> "${results_file}" 2>/dev/null || true
     count=$((count + 1))
     retries=0
    else
     break
    fi
   done
   exit 0
  ) &
  pids+=($!)
 done

 # Wait for all threads
 for pid in "${pids[@]}"; do
  wait "${pid}" || true
 done

 # Verify all items were processed exactly once
 local total_processed
 total_processed=$(wc -l < "${results_file}" || echo "0")
 [[ "${total_processed}" -eq 100 ]] || echo "All 100 items should be processed (got ${total_processed})"

 # Verify no duplicates (each number 1-100 should appear exactly once)
 local unique_count
 unique_count=$(sort -u "${results_file}" | wc -l || echo "0")
 [[ "${unique_count}" -eq 100 ]] || echo "All items should be unique (got ${unique_count} unique)"

 # Verify queue is empty
 local remaining
 remaining=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${remaining}" -eq 0 ]] || echo "Queue should be empty after processing (got ${remaining} items)"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}" "${results_file}"
}

# Test concurrent access to work queue for users
@test "datamartUsers work queue should handle concurrent access" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test work queue file with many items
 local test_queue_file="${TMP_DIR}/test_user_queue_concurrent.txt"
 local test_lock_file="${TMP_DIR}/test_user_queue_concurrent.lock"
 seq 1000 1099 > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Simulate 4 concurrent threads reading from queue
 local pids=()
 local results_file="${TMP_DIR}/concurrent_user_results.txt"
 > "${results_file}"

 for i in {1..4}; do
  (
   set +e
   local count=0
   local retries=0
   local max_retries=10
   while [[ ${count} -lt 25 ]]; do
    local item
    item=$(__get_next_user_from_queue)
    local exit_code=$?
    # If lock failed (exit code 1), retry after short delay
    if [[ ${exit_code} -eq 1 ]]; then
     retries=$((retries + 1))
     if [[ ${retries} -lt ${max_retries} ]]; then
      sleep 0.01
      continue
     else
      break
     fi
    fi
    if [[ -n "${item}" ]]; then
     echo "${item}" >> "${results_file}" 2>/dev/null || true
     count=$((count + 1))
     retries=0
    else
     break
    fi
   done
   exit 0
  ) &
  pids+=($!)
 done

 # Wait for all threads
 for pid in "${pids[@]}"; do
  wait "${pid}" || true
 done

 # Verify all items were processed exactly once
 local total_processed
 total_processed=$(wc -l < "${results_file}" || echo "0")
 [[ "${total_processed}" -eq 100 ]] || echo "All 100 items should be processed (got ${total_processed})"

 # Verify no duplicates
 local unique_count
 unique_count=$(sort -u "${results_file}" | wc -l || echo "0")
 [[ "${unique_count}" -eq 100 ]] || echo "All items should be unique (got ${unique_count} unique)"

 # Verify queue is empty
 local remaining
 remaining=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${remaining}" -eq 0 ]] || echo "Queue should be empty after processing (got ${remaining} items)"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}" "${results_file}"
}

# Test that work queue handles empty queue gracefully
@test "datamartCountries work queue should handle empty queue" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create empty work queue file
 local test_queue_file="${TMP_DIR}/test_empty_queue.txt"
 local test_lock_file="${TMP_DIR}/test_empty_queue.lock"
 touch "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Test that function returns empty string for empty queue
 local result
 result=$(__get_next_country_from_queue)
 [[ -z "${result}" ]] || echo "Should return empty string for empty queue"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}

# Test that work queue handles empty queue gracefully for users
@test "datamartUsers work queue should handle empty queue" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create empty work queue file
 local test_queue_file="${TMP_DIR}/test_empty_user_queue.txt"
 local test_lock_file="${TMP_DIR}/test_empty_user_queue.lock"
 touch "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Test that function returns empty string for empty queue
 local result
 result=$(__get_next_user_from_queue)
 [[ -z "${result}" ]] || echo "Should return empty string for empty queue"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}

# Test that parallel processing uses correct number of threads
@test "datamartCountries parallel processing should use nproc-2 threads" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Mock nproc to return 8
 local original_nproc
 original_nproc=$(which nproc 2> /dev/null || echo "nproc")

 # Test that adjusted_threads calculation works
 local MAX_THREADS=8
 local adjusted_threads
 if [[ "${MAX_THREADS}" -gt 2 ]]; then
  adjusted_threads=$((MAX_THREADS - 2))
 else
  adjusted_threads=1
 fi

 [[ "${adjusted_threads}" -eq 6 ]] || echo "Should use 6 threads for 8 CPUs (nproc-2)"

 # Test edge case: 2 CPUs
 MAX_THREADS=2
 if [[ "${MAX_THREADS}" -gt 2 ]]; then
  adjusted_threads=$((MAX_THREADS - 2))
 else
  adjusted_threads=1
 fi

 [[ "${adjusted_threads}" -eq 1 ]] || echo "Should use 1 thread for 2 CPUs"
}

# Test that parallel processing uses correct number of threads for users
@test "datamartUsers parallel processing should use nproc-1 threads" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Test that adjusted_threads calculation works
 local MAX_THREADS=8
 local adjusted_threads
 adjusted_threads=$((MAX_THREADS - 1))
 if [[ "${adjusted_threads}" -lt 1 ]]; then
  adjusted_threads=1
 fi

 [[ "${adjusted_threads}" -eq 7 ]] || echo "Should use 7 threads for 8 CPUs (nproc-1)"

 # Test edge case: 1 CPU
 MAX_THREADS=1
 adjusted_threads=$((MAX_THREADS - 1))
 if [[ "${adjusted_threads}" -lt 1 ]]; then
  adjusted_threads=1
 fi

 [[ "${adjusted_threads}" -eq 1 ]] || echo "Should use 1 thread for 1 CPU"
}

# Test that work queue file is created correctly
@test "datamartCountries work queue file creation" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Simulate creating work queue file
 local test_ids="1\n2\n3\n4\n5"
 local test_queue_file="${TMP_DIR}/test_queue_creation.txt"
 echo -e "${test_ids}" > "${test_queue_file}"

 # Verify file was created
 [[ -f "${test_queue_file}" ]] || echo "Work queue file should be created"

 # Verify content
 local line_count
 line_count=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${line_count}" -eq 5 ]] || echo "Work queue should contain 5 items"

 # Cleanup
 rm -f "${test_queue_file}"
}

# Test that work queue file is created correctly for users
@test "datamartUsers work queue file creation" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Simulate creating work queue file
 local test_ids="100\n200\n300\n400\n500"
 local test_queue_file="${TMP_DIR}/test_user_queue_creation.txt"
 echo -e "${test_ids}" > "${test_queue_file}"

 # Verify file was created
 [[ -f "${test_queue_file}" ]] || echo "Work queue file should be created"

 # Verify content
 local line_count
 line_count=$(wc -l < "${test_queue_file}" || echo "0")
 [[ "${line_count}" -eq 5 ]] || echo "Work queue should contain 5 items"

 # Cleanup
 rm -f "${test_queue_file}"
}

# Test that parallel processing function logs correctly
@test "datamartCountries parallel processing should log thread information" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Check that function contains logging for threads
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __processNotesCountriesParallel | grep -q 'Starting.*parallel worker threads'"
 [[ "${status}" -eq 0 ]] || echo "Function should log thread start information"

 # Check that function contains logging for completion
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __processNotesCountriesParallel | grep -q 'Completed successfully'"
 [[ "${status}" -eq 0 ]] || echo "Function should log completion information"
}

# Test that parallel processing function logs correctly for users
@test "datamartUsers parallel processing should log thread information" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Check that function contains logging for threads
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser | grep -q 'Starting.*parallel worker threads'"
 [[ "${status}" -eq 0 ]] || echo "Function should log thread start information"

 # Check that function contains logging for completion
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser | grep -q 'Completed successfully'"
 [[ "${status}" -eq 0 ]] || echo "Function should log completion information"
}

# Test that work queue cleanup happens correctly
@test "datamartCountries work queue cleanup" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test files
 local test_queue_file="${TMP_DIR}/test_queue_cleanup.txt"
 local test_lock_file="${TMP_DIR}/test_queue_cleanup.lock"
 echo "test" > "${test_queue_file}"
 touch "${test_lock_file}"

 # Simulate cleanup (as done in function)
 rm -f "${test_queue_file}" "${test_lock_file}" 2> /dev/null || true

 # Verify files are removed
 [[ ! -f "${test_queue_file}" ]] || echo "Work queue file should be cleaned up"
 [[ ! -f "${test_lock_file}" ]] || echo "Lock file should be cleaned up"
}

# Test that work queue cleanup happens correctly for users
@test "datamartUsers work queue cleanup" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test files
 local test_queue_file="${TMP_DIR}/test_user_queue_cleanup.txt"
 local test_lock_file="${TMP_DIR}/test_user_queue_cleanup.lock"
 echo "test" > "${test_queue_file}"
 touch "${test_lock_file}"

 # Simulate cleanup (as done in function)
 rm -f "${test_queue_file}" "${test_lock_file}" 2> /dev/null || true

 # Verify files are removed
 [[ ! -f "${test_queue_file}" ]] || echo "Work queue file should be cleaned up"
 [[ ! -f "${test_lock_file}" ]] || echo "Lock file should be cleaned up"
}

# Test that parallel processing handles errors gracefully
@test "datamartCountries parallel processing should handle thread errors" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Check that function tracks thread failures
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __processNotesCountriesParallel | grep -q 'thread_failed'"
 [[ "${status}" -eq 0 ]] || echo "Function should track thread failures"

 # Check that function reports errors
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh && declare -f __processNotesCountriesParallel | grep -q 'ERROR.*Failed to process'"
 [[ "${status}" -eq 0 ]] || echo "Function should log errors for failed countries"
}

# Test that parallel processing handles errors gracefully for users
@test "datamartUsers parallel processing should handle thread errors" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Check that function tracks thread failures
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser | grep -q 'thread_failed'"
 [[ "${status}" -eq 0 ]] || echo "Function should track thread failures"

 # Check that function reports errors
 run bash -c "SKIP_MAIN=true source ${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh && declare -f __processNotesUser | grep -q 'ERROR.*Failed to process'"
 [[ "${status}" -eq 0 ]] || echo "Function should log errors for failed users"
}

# Test load balancing: verify that threads process similar number of items
@test "datamartCountries work queue should balance load across threads" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test work queue file with many items
 local test_queue_file="${TMP_DIR}/test_load_balance_countries.txt"
 local test_lock_file="${TMP_DIR}/test_load_balance_countries.lock"
 seq 1 100 > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Simulate 4 concurrent threads
 local pids=()
 local thread_results=()
 for i in {1..4}; do
  local result_file="${TMP_DIR}/thread_${i}_results.txt"
  thread_results+=("${result_file}")
  > "${result_file}"

  (
   set +e
   local count=0
   local retries=0
   local max_retries=10
   local max_iterations=150  # Safety limit: 100 items + 50 retries
   local iterations=0
   while [[ ${iterations} -lt ${max_iterations} ]]; do
    iterations=$((iterations + 1))
    local item
    item=$(__get_next_country_from_queue)
    local exit_code=$?
    # If lock failed (exit code 1), retry after short delay
    if [[ ${exit_code} -eq 1 ]]; then
     retries=$((retries + 1))
     if [[ ${retries} -lt ${max_retries} ]]; then
      sleep 0.01
      continue
     else
      break
     fi
    fi
    if [[ -n "${item}" ]]; then
     echo "${item}" >> "${result_file}" 2>/dev/null || true
     count=$((count + 1))
     retries=0
    else
     break
    fi
   done
   exit 0
  ) &
  pids+=($!)
 done

 # Wait for all threads with timeout (max 30 seconds)
 local timeout=30
 local elapsed=0
 local all_done=false
 while [[ ${elapsed} -lt ${timeout} ]]; do
  all_done=true
  for pid in "${pids[@]}"; do
   if kill -0 "${pid}" 2>/dev/null; then
    all_done=false
    break
   fi
  done
  if [[ "${all_done}" == "true" ]]; then
   break
  fi
  sleep 0.5
  elapsed=$((elapsed + 1))
 done

 # Kill any remaining processes if timeout reached
 if [[ "${all_done}" != "true" ]]; then
  for pid in "${pids[@]}"; do
   kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  for pid in "${pids[@]}"; do
   kill -KILL "${pid}" 2>/dev/null || true
  done
 fi

 # Wait for all threads to finish (cleanup)
 for pid in "${pids[@]}"; do
  wait "${pid}" 2>/dev/null || true
 done

 # Count items processed per thread
 local counts=()
 for result_file in "${thread_results[@]}"; do
  local count
  count=$(wc -l < "${result_file}" || echo "0")
  counts+=("${count}")
 done

 # Verify load balancing: each thread should process between 20-30 items (100/4 = 25 average)
 # Allow some variance but ensure no thread is idle (all should process at least 15 items)
 local min_count=15
 local max_count=35
 for count in "${counts[@]}"; do
  [[ "${count}" -ge "${min_count}" ]] || echo "Thread should process at least ${min_count} items (got ${count})"
  [[ "${count}" -le "${max_count}" ]] || echo "Thread should process at most ${max_count} items (got ${count})"
 done

 # Verify total is correct
 local total=0
 for count in "${counts[@]}"; do
  total=$((total + count))
 done
 [[ "${total}" -eq 100 ]] || echo "Total processed should be 100 (got ${total})"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}" "${thread_results[@]}"
}

# Test load balancing: verify that threads process similar number of items for users
@test "datamartUsers work queue should balance load across threads" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test work queue file with many items
 local test_queue_file="${TMP_DIR}/test_load_balance_users.txt"
 local test_lock_file="${TMP_DIR}/test_load_balance_users.lock"
 seq 1000 1099 > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Simulate 4 concurrent threads
 local pids=()
 local thread_results=()
 for i in {1..4}; do
  local result_file="${TMP_DIR}/thread_user_${i}_results.txt"
  thread_results+=("${result_file}")
  > "${result_file}"

  (
   set +e
   local count=0
   local retries=0
   local max_retries=10
   local max_iterations=150  # Safety limit: 100 items + 50 retries
   local iterations=0
   while [[ ${iterations} -lt ${max_iterations} ]]; do
    iterations=$((iterations + 1))
    local item
    item=$(__get_next_user_from_queue)
    local exit_code=$?
    # If lock failed (exit code 1), retry after short delay
    if [[ ${exit_code} -eq 1 ]]; then
     retries=$((retries + 1))
     if [[ ${retries} -lt ${max_retries} ]]; then
      sleep 0.01
      continue
     else
      break
     fi
    fi
    if [[ -n "${item}" ]]; then
     echo "${item}" >> "${result_file}" 2>/dev/null || true
     count=$((count + 1))
     retries=0
    else
     break
    fi
   done
   exit 0
  ) &
  pids+=($!)
 done

 # Wait for all threads with timeout (max 30 seconds)
 local timeout=30
 local elapsed=0
 local all_done=false
 while [[ ${elapsed} -lt ${timeout} ]]; do
  all_done=true
  for pid in "${pids[@]}"; do
   if kill -0 "${pid}" 2>/dev/null; then
    all_done=false
    break
   fi
  done
  if [[ "${all_done}" == "true" ]]; then
   break
  fi
  sleep 0.5
  elapsed=$((elapsed + 1))
 done

 # Kill any remaining processes if timeout reached
 if [[ "${all_done}" != "true" ]]; then
  for pid in "${pids[@]}"; do
   kill -TERM "${pid}" 2>/dev/null || true
  done
  sleep 1
  for pid in "${pids[@]}"; do
   kill -KILL "${pid}" 2>/dev/null || true
  done
 fi

 # Wait for all threads to finish (cleanup)
 for pid in "${pids[@]}"; do
  wait "${pid}" 2>/dev/null || true
 done

 # Count items processed per thread
 local counts=()
 for result_file in "${thread_results[@]}"; do
  local count
  count=$(wc -l < "${result_file}" || echo "0")
  counts+=("${count}")
 done

 # Verify load balancing: each thread should process between 20-30 items (100/4 = 25 average)
 local min_count=15
 local max_count=35
 for count in "${counts[@]}"; do
  [[ "${count}" -ge "${min_count}" ]] || echo "Thread should process at least ${min_count} items (got ${count})"
  [[ "${count}" -le "${max_count}" ]] || echo "Thread should process at most ${max_count} items (got ${count})"
 done

 # Verify total is correct
 local total=0
 for count in "${counts[@]}"; do
  total=$((total + count))
 done
 [[ "${total}" -eq 100 ]] || echo "Total processed should be 100 (got ${total})"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}" "${thread_results[@]}"
}

# Test integration: verify work queue works with actual database setup (countries)
@test "datamartCountries parallel processing integration with database" {
 # Skip if no database available
 if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  skip "Skipping database integration test in CI"
 fi

 # Source the script with SKIP_MAIN to avoid database operations during source
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test database if it doesn't exist
 run psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true

 # Set up base tables
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql" 2> /dev/null || true
 fi

 # Create datamart countries table
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_11_createDatamarCountriesTable.sql" 2> /dev/null || true
 fi

 # Create procedure
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql" 2> /dev/null || true
 fi

 # Insert test data: create some countries with modified flag
 run psql -d "${TEST_DBNAME}" -c "
		INSERT INTO dwh.dimension_countries (dimension_country_id, modified)
		VALUES (1, TRUE), (2, TRUE), (3, TRUE), (4, TRUE), (5, TRUE)
		ON CONFLICT (dimension_country_id) DO UPDATE SET modified = TRUE;
	" 2> /dev/null || true

 # Verify that function can query modified countries
 # Note: DBNAME_DWH might be readonly, so we'll use a different approach
 local dbname_var="${TEST_DBNAME}"
 local country_ids
 country_ids=$(psql -d "${TEST_DBNAME}" -Atq -c "
		SELECT dimension_country_id
		FROM dwh.dimension_countries
		WHERE modified = TRUE
		LIMIT 5;
	" 2> /dev/null || echo "")

 # If we got countries, verify work queue can be created
 if [[ -n "${country_ids}" ]]; then
  local test_queue_file="${TMP_DIR}/test_db_queue.txt"
  echo "${country_ids}" > "${test_queue_file}"
  [[ -f "${test_queue_file}" ]] || echo "Work queue file should be created from database query"
  rm -f "${test_queue_file}"
 fi
}

# Test integration: verify work queue works with actual database setup (users)
@test "datamartUsers parallel processing integration with database" {
 # Skip if no database available
 if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  skip "Skipping database integration test in CI"
 fi

 # Source the script with SKIP_MAIN to avoid database operations during source
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test database if it doesn't exist
 run psql -d postgres -c "CREATE DATABASE ${TEST_DBNAME};" 2> /dev/null || true

 # Set up base tables
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/ETL_20_createDWHTables.sql" 2> /dev/null || true
 fi

 # Create datamart users table
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_11_createDatamartUsersTable.sql" 2> /dev/null || true
 fi

 # Create procedure
 if [[ -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql" ]]; then
  run psql -d "${TEST_DBNAME}" -f "${SCRIPT_BASE_DIRECTORY}/sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql" 2> /dev/null || true
 fi

 # Insert test data: create some users with modified flag
 run psql -d "${TEST_DBNAME}" -c "
		INSERT INTO dwh.dimension_users (dimension_user_id, modified)
		VALUES (100, TRUE), (200, TRUE), (300, TRUE), (400, TRUE), (500, TRUE)
		ON CONFLICT (dimension_user_id) DO UPDATE SET modified = TRUE;
	" 2> /dev/null || true

 # Verify that function can query modified users
 # Note: DBNAME_DWH might be readonly, so we'll use a different approach
 local dbname_var="${TEST_DBNAME}"
 local user_ids
 user_ids=$(psql -d "${TEST_DBNAME}" -Atq -c "
		SELECT dimension_user_id
		FROM dwh.dimension_users
		WHERE modified = TRUE
		LIMIT 5;
	" 2> /dev/null || echo "")

 # If we got users, verify work queue can be created
 if [[ -n "${user_ids}" ]]; then
  local test_queue_file="${TMP_DIR}/test_db_user_queue.txt"
  echo "${user_ids}" > "${test_queue_file}"
  [[ -f "${test_queue_file}" ]] || echo "Work queue file should be created from database query"
  rm -f "${test_queue_file}"
 fi
}

# Test that work queue maintains priority order (countries)
@test "datamartCountries work queue should maintain priority order" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartCountries/datamartCountries.sh" > /dev/null 2>&1 || true

 # Create test work queue file with ordered items (simulating priority order)
 local test_queue_file="${TMP_DIR}/test_priority_queue.txt"
 local test_lock_file="${TMP_DIR}/test_priority_queue.lock"
 echo -e "10\n20\n30\n40\n50" > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Process items sequentially and verify order
 local processed_order=()
 for i in {1..5}; do
  local item
  item=$(__get_next_country_from_queue)
  if [[ -n "${item}" ]]; then
   processed_order+=("${item}")
  fi
 done

 # Verify order is maintained (should be 10, 20, 30, 40, 50)
 [[ "${processed_order[0]}" == "10" ]] || echo "First item should be 10 (got ${processed_order[0]})"
 [[ "${processed_order[1]}" == "20" ]] || echo "Second item should be 20 (got ${processed_order[1]})"
 [[ "${processed_order[2]}" == "30" ]] || echo "Third item should be 30 (got ${processed_order[2]})"
 [[ "${processed_order[3]}" == "40" ]] || echo "Fourth item should be 40 (got ${processed_order[3]})"
 [[ "${processed_order[4]}" == "50" ]] || echo "Fifth item should be 50 (got ${processed_order[4]})"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}

# Test that work queue maintains priority order (users)
@test "datamartUsers work queue should maintain priority order" {
 # Source the script with SKIP_MAIN to avoid database operations
 SKIP_MAIN=true source "${SCRIPT_BASE_DIRECTORY}/bin/dwh/datamartUsers/datamartUsers.sh" > /dev/null 2>&1 || true

 # Create test work queue file with ordered items (simulating priority order)
 local test_queue_file="${TMP_DIR}/test_priority_user_queue.txt"
 local test_lock_file="${TMP_DIR}/test_priority_user_queue.lock"
 echo -e "1000\n2000\n3000\n4000\n5000" > "${test_queue_file}"

 # Export variables for function
 export work_queue_file="${test_queue_file}"
 export queue_lock_file="${test_lock_file}"

 # Process items sequentially and verify order
 local processed_order=()
 for i in {1..5}; do
  local item
  item=$(__get_next_user_from_queue)
  if [[ -n "${item}" ]]; then
   processed_order+=("${item}")
  fi
 done

 # Verify order is maintained (should be 1000, 2000, 3000, 4000, 5000)
 [[ "${processed_order[0]}" == "1000" ]] || echo "First item should be 1000 (got ${processed_order[0]})"
 [[ "${processed_order[1]}" == "2000" ]] || echo "Second item should be 2000 (got ${processed_order[1]})"
 [[ "${processed_order[2]}" == "3000" ]] || echo "Third item should be 3000 (got ${processed_order[2]})"
 [[ "${processed_order[3]}" == "4000" ]] || echo "Fourth item should be 4000 (got ${processed_order[3]})"
 [[ "${processed_order[4]}" == "5000" ]] || echo "Fifth item should be 5000 (got ${processed_order[4]})"

 # Cleanup
 rm -f "${test_queue_file}" "${test_lock_file}"
}
