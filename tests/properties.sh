#!/bin/bash

# Test Properties for OSM-Notes-Analytics
# Independent test configuration - separate from production properties
#
# Author: Andres Gomez (AngocA)
# Version: 2025-10-14

# Database configuration for tests
# Detect if running in CI/CD environment

# First, check if variables are already set (e.g., by GitHub Actions)
# Only use CI/CD mode if TEST_DBHOST is explicitly set or we're in a CI environment
if [[ -n "${TEST_DBHOST:-}" ]] || { [[ -n "${TEST_DBNAME:-}" ]] && [[ -n "${TEST_DBUSER:-}" ]] && { [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }; }; then
 # Variables already set by external environment (e.g., GitHub Actions)
 if [[ "${TEST_DEBUG:-}" == "true" ]]; then
  echo "DEBUG: Using environment-provided database configuration" >&2
  echo "DEBUG: TEST_DBNAME=${TEST_DBNAME:-}" >&2
  echo "DEBUG: TEST_DBUSER=${TEST_DBUSER:-}" >&2
  echo "DEBUG: TEST_DBHOST=${TEST_DBHOST:-}" >&2
 fi
 # Ensure all variables are exported
 export TEST_DBNAME="${TEST_DBNAME:-osm_notes_analytics_test}"
 export TEST_DBUSER="${TEST_DBUSER:-postgres}"
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-postgres}"
 export TEST_DBHOST="${TEST_DBHOST:-localhost}"
 export TEST_DBPORT="${TEST_DBPORT:-5432}"
elif [[ -f "/app/bin/dwh/ETL.sh" ]]; then
 # Running in Docker container
 if [[ "${TEST_DEBUG:-}" == "true" ]]; then
  echo "DEBUG: Detected Docker environment" >&2
 fi
 export TEST_DBNAME="osm_notes_analytics_test"
 export TEST_DBUSER="testuser"
 export TEST_DBPASSWORD="testpass"
 export TEST_DBHOST="postgres"
 export TEST_DBPORT="5432"
elif [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
 # Running in GitHub Actions CI without explicit variables
 if [[ "${TEST_DEBUG:-}" == "true" ]]; then
  echo "DEBUG: Detected CI environment without explicit DB config" >&2
 fi
 export TEST_DBNAME="${TEST_DBNAME:-dwh}"
 export TEST_DBUSER="${TEST_DBUSER:-postgres}"
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-postgres}"
 export TEST_DBHOST="${TEST_DBHOST:-localhost}"
 export TEST_DBPORT="${TEST_DBPORT:-5432}"
else
 # Running on host - use local PostgreSQL with peer authentication
 if [[ "${TEST_DEBUG:-}" == "true" ]]; then
  echo "DEBUG: Detected host environment" >&2
 fi
 # Set TEST_DBNAME to osm_notes_analytics_test for local testing
 # This is the standard test database name for this repository
 export TEST_DBNAME="${TEST_DBNAME:-osm_notes_analytics_test}"
 export TEST_DBUSER="${TEST_DBUSER:-$(whoami)}"
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-}"
 export TEST_DBHOST="${TEST_DBHOST:-}"
 export TEST_DBPORT="${TEST_DBPORT:-}"

 # Ensure host and port are empty for local connection
 unset TEST_DBHOST TEST_DBPORT

 # Ensure user is current user for local connection
 unset TEST_DBUSER

 # For peer authentication, ensure these variables are not set
 unset PGPASSWORD 2> /dev/null || true
 unset DB_HOST 2> /dev/null || true
 unset DB_PORT 2> /dev/null || true
 unset DB_USER 2> /dev/null || true
 unset DB_PASSWORD 2> /dev/null || true
fi

# Variables are already set above in the if/elif/else block
# Only set defaults here if they weren't set (for CI environments)
# This allows tests to skip when no DB is configured
# Note: For local peer authentication, TEST_DBUSER should remain unset
if [[ -z "${TEST_DBUSER:-}" ]] && { [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }; then
 export TEST_DBUSER="${TEST_DBUSER:-postgres}"
fi
# Only set TEST_DBPASSWORD for CI/CD environments, not for local peer authentication
if [[ -z "${TEST_DBPASSWORD:-}" ]] && { [[ -n "${TEST_DBHOST:-}" ]] || [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; }; then
 export TEST_DBPASSWORD="${TEST_DBPASSWORD:-postgres}"
fi

# Test application configuration
export LOG_LEVEL="INFO"
export MAX_THREADS="2"

# Test timeout and retry configuration
export TEST_TIMEOUT="300" # 5 minutes for general tests
export TEST_RETRIES="3"   # Standard retry count
export MAX_RETRIES="30"   # Maximum retries for service startup
export RETRY_INTERVAL="2" # Seconds between retries

# Test performance configuration
export TEST_PERFORMANCE_TIMEOUT="60" # 1 minute for performance tests
export MEMORY_LIMIT_MB="100"         # Memory limit for tests

# Test CI/CD specific configuration
export CI_TIMEOUT="600"    # 10 minutes for CI/CD tests
export CI_MAX_RETRIES="20" # More retries for CI environment
export CI_MAX_THREADS="2"  # Conservative threading for CI

# Test Docker configuration
export DOCKER_TIMEOUT="300"    # 5 minutes for Docker operations
export DOCKER_MAX_RETRIES="10" # Docker-specific retries

# Test parallel processing configuration
export PARALLEL_ENABLED="false" # Default to sequential for stability
export PARALLEL_THREADS="2"     # Conservative parallel processing

# Test validation configuration
export VALIDATION_TIMEOUT="60" # 1 minute for validation tests
export VALIDATION_RETRIES="3"  # Standard validation retries

# ETL test configuration
export ETL_BATCH_SIZE="100"           # Smaller batch size for tests
export ETL_PARALLEL_ENABLED="false"   # Disable parallel processing in tests
export ETL_MAX_PARALLEL_JOBS="2"      # Conservative parallel jobs
export ETL_VALIDATE_INTEGRITY="true"  # Always validate integrity in tests
export ETL_VALIDATE_DIMENSIONS="true" # Validate dimensions in tests
export ETL_VALIDATE_FACTS="true"      # Validate facts in tests

# DWH test configuration
export DWH_SCHEMA="dwh"         # DWH schema name
export STAGING_SCHEMA="staging" # Staging schema name
