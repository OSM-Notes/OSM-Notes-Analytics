#!/bin/bash

# Data warehouse (DWH) schema compatibility expectations for external consumers.
# SemVer in public.schema_version where component = 'dwh' is managed by
# OSM-Notes-Analytics (see docs/Schema_Versioning_DWH.md, sql/dwh/ensure_dwh_schema_version.sql).
#
# For ingestion "core" contract, see OSM-Notes-Ingestion etc/schema_compatibility.sh.
# This file is not in lib/osm-common; OSM-Notes-API (or others) can vendor it from this repository.
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-22

# Compares two semantic versions (MAJOR.MINOR.PATCH).
# Returns (stdout):
#   0 if equal, 1 if first > second, -1 if first < second
function __compare_semver() {
 local VERSION_A="${1}"
 local VERSION_B="${2}"
 local IFS='.'
 local -a A B
 read -r -a A <<< "${VERSION_A}"
 read -r -a B <<< "${VERSION_B}"
 local I
 for I in 0 1 2; do
  local AV="${A[${I}]:-0}"
  local BV="${B[${I}]:-0}"
  if ((AV > BV)); then
   echo 1
   return 0
  fi
  if ((AV < BV)); then
   echo -1
   return 0
  fi
 done
 echo 0
 return 0
}

# shellcheck disable=SC2034
# Exports: SCHEMA_DWH_COMPONENT, EXPECTED_DWH_SCHEMA_MIN, EXPECTED_DWH_SCHEMA_MAX
#
# Parameters:
#  $1: optional consumer id (api, wms, analytics, monitoring) — all share the same DWH range today;
#      default api.
function __set_dwh_schema_contract_range() {
 local CONSUMER="${1:-api}"

 case "${CONSUMER}" in
 api | wms | analytics | monitoring | ingestion)
  export SCHEMA_DWH_COMPONENT="${SCHEMA_DWH_COMPONENT:-dwh}"
  export EXPECTED_DWH_SCHEMA_MIN="${EXPECTED_DWH_SCHEMA_MIN:-1.0.0}"
  export EXPECTED_DWH_SCHEMA_MAX="${EXPECTED_DWH_SCHEMA_MAX:-1.0.x}"
  ;;
 *)
  export SCHEMA_DWH_COMPONENT="${SCHEMA_DWH_COMPONENT:-dwh}"
  export EXPECTED_DWH_SCHEMA_MIN="${EXPECTED_DWH_SCHEMA_MIN:-1.0.0}"
  export EXPECTED_DWH_SCHEMA_MAX="${EXPECTED_DWH_SCHEMA_MAX:-1.0.x}"
  ;;
 esac
}

# Returns 0 if S is a safe public.schema_version.component value for SQL string literals
# (alphanumeric, underscore, hyphen; 1..64 chars). Rejects quotes, semicolons, and whitespace.
function __dwh_schema_component_id_valid() {
 local S="${1:-}"
 [[ -n "${S}" ]] && [[ "${S}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]
}

# Asserts the DWH database public.schema_version row for component 'dwh' is within the expected
# SemVer range. Mirrors OSM-Notes-Ingestion __assert_schema_compatible for the 'core' component.
#
# Environment:
#   DBNAME_DWH   — target database (default: notes_dwh)
#   PSQL_CMD     — psql executable (default: psql)
#   SCHEMA_DWH_CONSUMER — optional, passed to __set_dwh_schema_contract_range (default: api)
#   Override range with EXPECTED_DWH_SCHEMA_MIN / EXPECTED_DWH_SCHEMA_MAX / SCHEMA_DWH_COMPONENT
#
# Returns: 0 if compatible, 1 otherwise
function __assert_dwh_schema_compatible() {
 local DB
 DB="${DBNAME_DWH:-notes_dwh}"
 local PSQL="${PSQL_CMD:-psql}"
 local CONS="${SCHEMA_DWH_CONSUMER:-api}"
 local CMP_MIN
 local CMP_MAX
 local DB_VERSION
 local MIN_VERSION
 local MAX_VERSION
 local COMPONENT
 local EFFECTIVE_MAX
 local MAX_EXCLUSIVE=false

 __set_dwh_schema_contract_range "${CONS}"
 COMPONENT="${SCHEMA_DWH_COMPONENT:-dwh}"
 MIN_VERSION="${EXPECTED_DWH_SCHEMA_MIN:-1.0.0}"
 MAX_VERSION="${EXPECTED_DWH_SCHEMA_MAX:-}"

 if ! __dwh_schema_component_id_valid "${COMPONENT}"; then
  echo "ERROR: Invalid SCHEMA_DWH_COMPONENT (alphanumeric, underscore, hyphen; 1-64 chars): ${COMPONENT}" >&2
  return 1
 fi

 DB_VERSION=$("${PSQL}" -d "${DB}" -Atq -c \
  "SELECT version FROM public.schema_version WHERE component='${COMPONENT}';" 2> /dev/null | head -1 || true)

 if [[ -z "${DB_VERSION}" ]]; then
  echo "ERROR: Missing schema version for component=${COMPONENT} in ${DB}" >&2
  return 1
 fi

 CMP_MIN=$(__compare_semver "${DB_VERSION}" "${MIN_VERSION}")
 if [[ "${CMP_MIN}" == "-1" ]]; then
  echo "ERROR: Incompatible DWH schema ${DB_VERSION} < ${MIN_VERSION}" >&2
  return 1
 fi

 if [[ -n "${MAX_VERSION}" ]]; then
  EFFECTIVE_MAX="${MAX_VERSION}"
  if [[ "${MAX_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.[xX]$ ]]; then
   EFFECTIVE_MAX="${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0"
   MAX_EXCLUSIVE=true
  fi
  CMP_MAX=$(__compare_semver "${DB_VERSION}" "${EFFECTIVE_MAX}")
  if [[ "${MAX_EXCLUSIVE}" == "true" ]] && [[ "${CMP_MAX}" != "-1" ]]; then
   echo "ERROR: Incompatible DWH schema ${DB_VERSION} is not < ${MAX_VERSION}" >&2
   return 1
  fi
  if [[ "${MAX_EXCLUSIVE}" != "true" ]] && [[ "${CMP_MAX}" == "1" ]]; then
   echo "ERROR: Incompatible DWH schema ${DB_VERSION} > ${MAX_VERSION}" >&2
   return 1
  fi
 fi
 return 0
}
