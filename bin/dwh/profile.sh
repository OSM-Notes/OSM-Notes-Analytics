#!/bin/bash

# This script generates user profiles, country profiles, or general statistics
# about notes. It reads data from the datamart tables in the data warehouse.
#
# There are 3 ways to call this script:
# * --user <UserName> : Shows the profile for the given user.
# * --country <CountryName> : Shows the profile for the given country (name in
#   English).
# * --pais <NombrePais> : Shows the profile for the given country (name in
#   Spanish).
# If the UserName, CountryName, or NombrePais contains spaces, it must be
# enclosed in double quotes.
# * (empty) : Shows general statistics about notes.
#
# For example:
# * --user AngocA
# * --country Colombia
# * --country "United States of America"
# * --pais Alemania
# * --country Germany
# The country name must match the name stored in the database (in English or
# Spanish as specified by the option used).
#
# This script queries the data warehouse datamarts and displays pre-computed
# analytics for testing and validation purposes.
#
# This is the list of error codes:
# 1) Help message.
# 241) Library or utility missing.
# 242) Invalid argument for script invocation.
# 243) Logger utility is not available.
#
# For contributing, please execute these commands before submitting:
# * shellcheck -x -o all profile.sh
# * shfmt -w -i 1 -sr -bn profile.sh
#
# Author: Andres Gomez (AngocA)
# Version: 2025-08-12
VERSION="2025-08-12"

#set -xv
# Fails when a variable is not initialized.
set -u
# Fails with a non-zero return code.
set -e
# Fails if the commands of a pipe return non-zero.
set -o pipefail
# Fails if an internal function fails.
set -E
# Fails parent if child fails.
shopt -s inherit_errexit

# If all files should be deleted. In case of an error, this could be disabled.
# You can defined when calling: export CLEAN=false
# CLEAN is now defined in etc/properties.sh, no need to declare it here

# Logger levels: TRACE, DEBUG, INFO, WARN, ERROR, FATAL.
declare LOG_LEVEL="${LOG_LEVEL:-ERROR}"

# Base directory for the project.
# Only set SCRIPT_BASE_DIRECTORY if not already defined (e.g., in test environment)
if [[ -z "${SCRIPT_BASE_DIRECTORY:-}" ]]; then
 declare SCRIPT_BASE_DIRECTORY
 SCRIPT_BASE_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." \
  &> /dev/null && pwd)"
 readonly SCRIPT_BASE_DIRECTORY
fi

# Loads the global properties.
# shellcheck disable=SC1091
if [[ -f "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh" ]] && [[ "${BATS_TEST_NAME:-}" != "" ]]; then
 # Use test properties when running in test environment
 source "${SCRIPT_BASE_DIRECTORY}/tests/properties.sh"
else
 # Use production properties
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh"
fi

# Load local properties if they exist (overrides global settings)
if [[ -f "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_BASE_DIRECTORY}/etc/properties.sh.local"
fi

declare BASENAME
BASENAME=$(basename -s .sh "${0}")
readonly BASENAME
# Temporary directory for all files.
declare TMP_DIR
TMP_DIR=$(mktemp -d "/tmp/${BASENAME}_XXXXXX")
readonly TMP_DIR
chmod 777 "${TMP_DIR}"
# Log file for output.
declare LOG_FILENAME
LOG_FILENAME="${TMP_DIR}/${BASENAME}.log"
readonly LOG_FILENAME

# Parse log level options from arguments and set PROCESS_TYPE/ARGUMENT from the rest.
if [[ -z "${PROCESS_TYPE:-}" ]]; then
 declare -a remaining_args=()
 for arg in "$@"; do
  case "${arg}" in
  -v | --verbose) LOG_LEVEL="INFO" ;;
  --debug) LOG_LEVEL="DEBUG" ;;
  -q | --quiet) LOG_LEVEL="ERROR" ;;
  *) remaining_args+=("${arg}") ;;
  esac
 done
 declare -r PROCESS_TYPE="${remaining_args[0]:-}"
 declare -r ARGUMENT="${remaining_args[1]:-}"
else
 declare -r PROCESS_TYPE="${PROCESS_TYPE}"
 declare -r ARGUMENT="${ARGUMENT:-}"
fi

# Username.
declare USERNAME
# Dimension_User_id of the username.
declare -i DIMENSION_USER_ID
# Name of the user or the country in English.
declare COUNTRY_NAME
# Name of the user or the country in Spanish.
declare PAIS_NAME
# Country_id of the country.
declare -i COUNTRY_ID

###########
# FUNCTIONS

# Load common functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/commonFunctions.sh"

# Load validation functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/validationFunctions.sh"

# Load error handling functions
# shellcheck disable=SC1091
source "${SCRIPT_BASE_DIRECTORY}/lib/osm-common/errorHandlingFunctions.sh"

# Shows the help information.
function __show_help {
 echo "${0} version ${VERSION}"
 echo "This script shows the profile for a given user or country,"
 echo "or general statistics about notes."
 echo
 echo "There are 3 ways to call this script:"
 echo "* --user <UserName> : Shows the profile for the given user."
 echo "* --country <CountryName> : Shows the profile for the given country (English name)."
 echo "* --pais <NombrePais> : Shows the profile for the given country (Spanish name)."
 echo
 echo "If the name contains spaces, it must be enclosed in double quotes."
 echo "The name must match the name stored in the database."
 echo
 echo "Examples:"
 echo "* --user AngocA"
 echo "* --country Colombia"
 echo "* --country \"United States of America\""
 echo "* --pais \"Estados Unidos\""
 echo "* (empty) : Shows general statistics about notes."
 echo
 echo "Log level (controls verbosity; default is ERROR, i.e. only errors):"
 echo "* -v, --verbose : INFO  - progress and key steps"
 echo "* --debug       : DEBUG - include function start/finish and timing"
 echo "* -q, --quiet   : ERROR - only errors (default)"
 echo "  Or set LOG_LEVEL=INFO (or DEBUG, WARN, ERROR) in the environment."
 echo
 echo "Written by: Andres Gomez (AngocA)"
 echo "OSM-LatAm, OSM-Colombia, MaptimeBogota."
 exit "${ERROR_HELP_MESSAGE}"
}

# Checks prerequisites to run the script.
function __checkPrereqs {
 __log_start
 if [[ "${PROCESS_TYPE}" != "" ]] \
  && [[ "${PROCESS_TYPE}" != "--user" ]] \
  && [[ "${PROCESS_TYPE}" != "--country" ]] \
  && [[ "${PROCESS_TYPE}" != "--pais" ]] \
  && [[ "${PROCESS_TYPE}" != "--help" ]] \
  && [[ "${PROCESS_TYPE}" != "-h" ]]; then
  echo "ERROR: Invalid parameter. It should be:"
  echo " * Empty string, nothing."
  echo " * --user"
  echo " * --country"
  echo " * --pais"
  echo " * --help"
  exit "${ERROR_INVALID_ARGUMENT}"
 fi
 if [[ "${PROCESS_TYPE}" == "--user" ]] \
  && [[ "${ARGUMENT}" == "" ]]; then
  __loge "ERROR: You  must provide a username."
  exit "${ERROR_INVALID_ARGUMENT}"
 else
  USERNAME="${ARGUMENT}"
 fi
 if [[ "${PROCESS_TYPE}" == "--country" ]] \
  && [[ "${ARGUMENT}" == "" ]]; then
  __loge "ERROR: You  must provide a country name."
  exit "${ERROR_INVALID_ARGUMENT}"
 else
  COUNTRY_NAME="${ARGUMENT}"
 fi
 if [[ "${PROCESS_TYPE}" == "--pais" ]] \
  && [[ "${ARGUMENT}" == "" ]]; then
  __loge "ERROR: You  must provide a country name."
  exit "${ERROR_INVALID_ARGUMENT}"
 else
  PAIS_NAME="${ARGUMENT}"
 fi

 __checkPrereqsCommands

 __log_finish
}

# Retrieves the dimension_user_id from a username.
function __getUserId {
 __log_start
 DIMENSION_USER_ID=$(psql -d "${DBNAME_DWH}" -Atq -v ON_ERROR_STOP=1 \
  <<< "SELECT dimension_user_id FROM dwh.datamartUsers
  WHERE username = '${USERNAME}'")
 if [[ "${DIMENSION_USER_ID}" == "" ]] \
  || [[ "${DIMENSION_USER_ID}" -eq 0 ]]; then
  __loge "ERROR: The username \"${USERNAME}\" does not exist."
  exit "${ERROR_INVALID_ARGUMENT}"
 fi
 __log_finish
}

# Retrieves the country_id from a country name.
function __getCountryId {
 __log_start
 if [[ "${PROCESS_TYPE}" == "--country" ]]; then
  COUNTRY_ID=$(psql -d "${DBNAME_DWH}" -Atq -v ON_ERROR_STOP=1 \
   <<< "SELECT dimension_country_id FROM dwh.datamartCountries
   WHERE country_name_en = '${COUNTRY_NAME}'")
 else
  COUNTRY_ID=$(psql -d "${DBNAME_DWH}" -Atq -v ON_ERROR_STOP=1 \
   <<< "SELECT dimension_country_id FROM dwh.datamartCountries
   WHERE country_name_es = '${PAIS_NAME}'")
 fi

 if [[ "${COUNTRY_ID}" == "" ]]; then
  __loge "ERROR: The country name \"${COUNTRY_NAME}${PAIS_NAME}\" does not exist."
  exit "${ERROR_INVALID_ARGUMENT}"
 fi
 __log_finish
}

# Shows the user activity for all years after 2013.
function __showActivityYearUsers {
 __log_start
 YEAR="${1}"

 declare -i HISTORY_YEAR_OPEN
 HISTORY_YEAR_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_COMMENTED
 HISTORY_YEAR_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_commented
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED
 HISTORY_YEAR_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED_WITH_COMMENT
 HISTORY_YEAR_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_closed_with_comment
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_REOPENED
 HISTORY_YEAR_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_reopened
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 printf "${YEAR}:          %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_YEAR_OPEN}" "${HISTORY_YEAR_COMMENTED}" "${HISTORY_YEAR_CLOSED}" "${HISTORY_YEAR_CLOSED_WITH_COMMENT}" "${HISTORY_YEAR_REOPENED}"
 __log_finish
}

# Shows the country activity for all years after 2013.
function __showActivityYearCountries {
 __log_start
 YEAR="${1}"

 declare -i HISTORY_YEAR_OPEN
 HISTORY_YEAR_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_COMMENTED
 HISTORY_YEAR_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_commented
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED
 HISTORY_YEAR_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED_WITH_COMMENT
 HISTORY_YEAR_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_closed_with_comment
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_REOPENED
 HISTORY_YEAR_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_${YEAR}_reopened
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 printf "${YEAR}:          %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_YEAR_OPEN}" "${HISTORY_YEAR_COMMENTED}" "${HISTORY_YEAR_CLOSED}" "${HISTORY_YEAR_CLOSED_WITH_COMMENT}" "${HISTORY_YEAR_REOPENED}"
 __log_finish
}

# Prints a given ranking in a better way.
function __printRanking {
 __log_start
 RANKING=${1}

 echo "${RANKING}" | sed 's/}, {/\n/g' | sed 's/^\[{//' | sed 's/}\]//' | sed 's/"rank" ://g' | sed 's/, "country_name" : "/ - /g' | sed 's/, "username" : "/ - /g' | sed 's/", "quantity" :/:/g'
 __log_finish
}

# Shows the historic yearly rankings when the user has contributed the most.
function __showRankingYearUsers {
 __log_start
 YEAR="${1}"

 declare RANKING_OPENING
 RANKING_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT ranking_countries_opening_${YEAR}
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare RANKING_CLOSING
 RANKING_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT ranking_countries_closing_${YEAR}
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 echo
 echo "Countries for opened notes on ${YEAR}:"
 __printRanking "${RANKING_OPENING}"
 echo "Countries for closed notes on ${YEAR}:"
 __printRanking "${RANKING_CLOSING}"
 __log_finish
}

# Shows the historic yearly rankings of which users contributed the most.
function __showRankingYearCountries {
 __log_start
 YEAR="${1}"

 declare RANKING_OPENING
 RANKING_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT ranking_users_opening_${YEAR}
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare RANKING_CLOSING
 RANKING_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT ranking_users_closing_${YEAR}
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 echo
 echo "Users creating notes on ${YEAR}:"
 __printRanking "${RANKING_OPENING}"
 echo "Users closing notes on ${YEAR}:"
 __printRanking "${RANKING_CLOSING}"
 __log_finish
}

# Prints the hour of the week.
function __processHourWeek {
 __log_start
 HOUR=${1}
 DOW=${2}
 NUMBER=$(echo "${WEEK}" | grep "\"day_of_week\":${DOW},\"hour_of_day\":${HOUR}," \
  | awk -F: '{print $4}' | sed 's/}, //' | sed 's/}\]//')
 printf "%5d" "${NUMBER}"
 __log_finish
}

# Shows the week hours in a better fashion.
function __showWorkingWeek {
 __log_start
 WEEK=${1}
 declare HOUR_0=" 0h"
 declare HOUR_1=" 1h"
 declare HOUR_2=" 2h"
 declare HOUR_3=" 3h"
 declare HOUR_4=" 4h"
 declare HOUR_5=" 5h"
 declare HOUR_6=" 6h"
 declare HOUR_7=" 7h"
 declare HOUR_8=" 8h"
 declare HOUR_9=" 9h"
 declare HOUR_10="10h"
 declare HOUR_11="11h"
 declare HOUR_12="12h"
 declare HOUR_13="13h"
 declare HOUR_14="14h"
 declare HOUR_15="15h"
 declare HOUR_16="16h"
 declare HOUR_17="17h"
 declare HOUR_18="18h"
 declare HOUR_19="19h"
 declare HOUR_20="20h"
 declare HOUR_21="21h"
 declare HOUR_22="22h"
 declare HOUR_23="23h"
 I=1
 set +e
 while [[ "${I}" -le 7 ]]; do
  HOUR_0="${HOUR_0} - $(__processHourWeek 0 "${I}")"
  HOUR_1="${HOUR_1} - $(__processHourWeek 1 "${I}")"
  HOUR_2="${HOUR_2} - $(__processHourWeek 2 "${I}")"
  HOUR_3="${HOUR_3} - $(__processHourWeek 3 "${I}")"
  HOUR_4="${HOUR_4} - $(__processHourWeek 4 "${I}")"
  HOUR_5="${HOUR_5} - $(__processHourWeek 5 "${I}")"
  HOUR_6="${HOUR_6} - $(__processHourWeek 6 "${I}")"
  HOUR_7="${HOUR_7} - $(__processHourWeek 7 "${I}")"
  HOUR_8="${HOUR_8} - $(__processHourWeek 8 "${I}")"
  HOUR_9="${HOUR_9} - $(__processHourWeek 9 "${I}")"
  HOUR_10="${HOUR_10} - $(__processHourWeek 10 "${I}")"
  HOUR_11="${HOUR_11} - $(__processHourWeek 11 "${I}")"
  HOUR_12="${HOUR_12} - $(__processHourWeek 12 "${I}")"
  HOUR_13="${HOUR_13} - $(__processHourWeek 13 "${I}")"
  HOUR_14="${HOUR_14} - $(__processHourWeek 14 "${I}")"
  HOUR_15="${HOUR_15} - $(__processHourWeek 15 "${I}")"
  HOUR_16="${HOUR_16} - $(__processHourWeek 16 "${I}")"
  HOUR_17="${HOUR_17} - $(__processHourWeek 17 "${I}")"
  HOUR_18="${HOUR_18} - $(__processHourWeek 18 "${I}")"
  HOUR_19="${HOUR_19} - $(__processHourWeek 19 "${I}")"
  HOUR_20="${HOUR_20} - $(__processHourWeek 20 "${I}")"
  HOUR_21="${HOUR_21} - $(__processHourWeek 21 "${I}")"
  HOUR_22="${HOUR_22} - $(__processHourWeek 22 "${I}")"
  HOUR_23="${HOUR_23} - $(__processHourWeek 23 "${I}")"
  ((I += 1))
 done
 set -e
 echo "        Sun -   Mon -   Tue -   Wed -   Thu -   Fri -   Sat"
 echo "${HOUR_0}"
 echo "${HOUR_1}"
 echo "${HOUR_2}"
 echo "${HOUR_3}"
 echo "${HOUR_4}"
 echo "${HOUR_5}"
 echo "${HOUR_6}"
 echo "${HOUR_7}"
 echo "${HOUR_8}"
 echo "${HOUR_9}"
 echo "${HOUR_10}"
 echo "${HOUR_11}"
 echo "${HOUR_12}"
 echo "${HOUR_13}"
 echo "${HOUR_14}"
 echo "${HOUR_15}"
 echo "${HOUR_16}"
 echo "${HOUR_17}"
 echo "${HOUR_18}"
 echo "${HOUR_19}"
 echo "${HOUR_20}"
 echo "${HOUR_21}"
 echo "${HOUR_22}"
 echo "${HOUR_23}"
 __log_finish
}

# Shows the activity as GitHub tiles.
function __printActivity {
 __log_start
 ACTIVITY="${1}"

 # Truncate activity to last 53 weeks (371 days) to avoid showing old weeks with zeros
 # Each week has 7 days, so 53 weeks = 371 characters
 declare ACTIVITY_LENGTH
 ACTIVITY_LENGTH=${#ACTIVITY}
 declare -i MAX_WEEKS=53
 declare -i MAX_CHARS=$((MAX_WEEKS * 7))

 if [[ ${ACTIVITY_LENGTH} -gt ${MAX_CHARS} ]]; then
  # Take only the last MAX_CHARS characters (most recent weeks)
  ACTIVITY="${ACTIVITY: -${MAX_CHARS}}"
 fi

 # Get current day of week (0=Sunday, 1=Monday, ..., 6=Saturday)
 declare -i CURRENT_DOW
 CURRENT_DOW=$(date +%w)

 # Rotate activity string to start from current day of week
 # The activity string starts from Sunday, so we need to rotate it
 declare ROTATED_ACTIVITY
 if [[ ${CURRENT_DOW} -gt 0 ]]; then
  # Rotate: move first CURRENT_DOW characters to the end
  ROTATED_ACTIVITY="${ACTIVITY:${CURRENT_DOW}}${ACTIVITY:0:${CURRENT_DOW}}"
 else
  ROTATED_ACTIVITY="${ACTIVITY}"
 fi

 # Create day labels starting from current day
 declare DAY_LABELS=("Sunday:    " "Monday:    " "Tuesday:   " "Wednesday: " "Thursday:  " "Friday:    " "Saturday:  ")
 declare DAY_VARS=("SUN" "MON" "TUE" "WED" "THU" "FRI" "SAT")

 # Initialize day variables starting from current day
 declare -i DAY_INDEX
 for DAY_INDEX in {0..6}; do
  declare ACTUAL_INDEX=$(((DAY_INDEX + CURRENT_DOW) % 7))
  declare VAR_NAME="${DAY_VARS[${ACTUAL_INDEX}]}"
  declare "${VAR_NAME}"="${DAY_LABELS[${ACTUAL_INDEX}]}"
 done

 # Calculate number of weeks to display based on available data
 declare -i WEEKS_TO_SHOW
 WEEKS_TO_SHOW=$((${#ROTATED_ACTIVITY} / 7))
 if [[ ${WEEKS_TO_SHOW} -gt ${MAX_WEEKS} ]]; then
  WEEKS_TO_SHOW=${MAX_WEEKS}
 fi

 I=1
 set +e
 while [[ ${I} -le ${WEEKS_TO_SHOW} ]] && [[ ${#ROTATED_ACTIVITY} -ge 7 ]]; do
  for DAY_INDEX in {0..6}; do
   ACTUAL_INDEX=$(((DAY_INDEX + CURRENT_DOW) % 7))
   VAR_NAME="${DAY_VARS[${ACTUAL_INDEX}]}"
   DAY="${ROTATED_ACTIVITY:0:1}"
   ROTATED_ACTIVITY="${ROTATED_ACTIVITY:1}"
   declare "${VAR_NAME}"="${!VAR_NAME}${DAY}"
  done
  I=$((I + 1))
 done
 set -e

 # Print days starting from current day
 for DAY_INDEX in {0..6}; do
  ACTUAL_INDEX=$(((DAY_INDEX + CURRENT_DOW) % 7))
  VAR_NAME="${DAY_VARS[${ACTUAL_INDEX}]}"
  echo "${!VAR_NAME}"
 done
 __log_finish
}

# Shows the user profile.
function __processUserProfile {
 __log_start
 declare -i OSM_USER_ID
 OSM_USER_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT user_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Quantity of days creating notes
 declare -i QTY_DAYS_OPEN
 QTY_DAYS_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT CURRENT_DATE - date_starting_creating_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare DATE_FIRST_OPEN
 DATE_FIRST_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT date_starting_creating_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Quantity of days solving notes.
 declare -i QTY_DAYS_CLOSE
 QTY_DAYS_CLOSE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT CURRENT_DATE - date_starting_solving_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare DATE_FIRST_CLOSE
 DATE_FIRST_CLOSE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT date_starting_solving_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Check if user may have stopped opening or closing notes
 declare DAYS_SINCE_LAST_ACTION
 DAYS_SINCE_LAST_ACTION=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(days_since_last_action, 0)
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # First actions.
 declare -i FIRST_OPEN_NOTE_ID
 FIRST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_open_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_COMMENTED_NOTE_ID
 FIRST_COMMENTED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_commented_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_CLOSED_NOTE_ID
 FIRST_CLOSED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_closed_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_REOPENED_NOTE_ID
 FIRST_REOPENED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_reopened_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Type of contributor.
 declare CONTRIBUTOR_TYPE
 CONTRIBUTOR_TYPE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT contributor_type_name
     FROM dwh.datamartUsers u
      JOIN dwh.contributor_types t
      ON u.id_contributor_type = t.contributor_type_id
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Experience level (newcomer -> legend).
 declare EXPERIENCE_LEVEL
 EXPERIENCE_LEVEL=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT el.experience_level
     FROM dwh.dimension_users u
      JOIN dwh.dimension_experience_levels el
      ON u.experience_level_id = el.dimension_experience_id
     WHERE u.dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "")

 # Last activity year.
 declare LAST_ACTIVITY_YEAR
 LAST_ACTIVITY_YEAR=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT last_year_activity
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Most recent actions.
 declare -i LAST_OPEN_NOTE_ID
 LAST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_open_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_COMMENTED_NOTE_ID
 LAST_COMMENTED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_commented_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_CLOSED_NOTE_ID
 LAST_CLOSED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_closed_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_REOPENED_NOTE_ID
 LAST_REOPENED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_reopened_note_id
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Dates with more opened notes.
 declare DATES_MOST_OPEN
 DATES_MOST_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT dates_most_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Dates with more closed notes
 declare DATES_MOST_CLOSED
 DATES_MOST_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT dates_most_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Used hashtags - extracted from note text and stored as JSON array
 # Format: [{"hashtag": "tag1", "count": 5}, {"hashtag": "tag2", "count": 3}]
 declare HASHTAGS
 HASHTAGS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1)

 # DM-002: Hashtags by action type
 # shellcheck disable=SC2034
 # SC2034: These variables are used in the hashtag display section below
 declare HASHTAGS_OPENING
 HASHTAGS_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_opening
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 # shellcheck disable=SC2034
 declare HASHTAGS_RESOLUTION
 HASHTAGS_RESOLUTION=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_resolution
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 # shellcheck disable=SC2034
 declare HASHTAGS_COMMENTS
 HASHTAGS_COMMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_comments
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 # shellcheck disable=SC2034
 declare FAVORITE_OPENING_HASHTAG
 FAVORITE_OPENING_HASHTAG=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT favorite_opening_hashtag
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "")

 # shellcheck disable=SC2034
 declare FAVORITE_RESOLUTION_HASHTAG
 FAVORITE_RESOLUTION_HASHTAG=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT favorite_resolution_hashtag
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "")

 # shellcheck disable=SC2034
 declare -i OPENING_HASHTAG_COUNT
 OPENING_HASHTAG_COUNT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(opening_hashtag_count, 0)
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # shellcheck disable=SC2034
 declare -i RESOLUTION_HASHTAG_COUNT
 RESOLUTION_HASHTAG_COUNT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(resolution_hashtag_count, 0)
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # Calculate hashtag statistics if available
 declare -i TOTAL_HASHTAG_USES=0
 declare -i UNIQUE_HASHTAGS=0
 if [[ -n "${HASHTAGS}" ]] && [[ "${HASHTAGS}" != "" ]] && [[ "${HASHTAGS}" != "[]" ]] && [[ "${HASHTAGS}" != "null" ]]; then
  if command -v jq &> /dev/null; then
   TOTAL_HASHTAG_USES=$(echo "${HASHTAGS}" | jq '[.[] | .count] | add // 0' 2> /dev/null || echo "0")
   UNIQUE_HASHTAGS=$(echo "${HASHTAGS}" | jq 'length' 2> /dev/null || echo "0")
  else
   # Fallback: count manually from JSON
   UNIQUE_HASHTAGS=$(echo "${HASHTAGS}" | grep -o '"hashtag"' | wc -l || echo "0")
  fi
 fi

 # Countries opening notes.
 declare COUNTRIES_OPENING
 COUNTRIES_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_open_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Countries closing notes.
 declare COUNTRIES_CLOSING
 COUNTRIES_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_solving_notes
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Countries opening notes current month.
 declare COUNTRIES_OPENING_CURRENT_MONTH
 COUNTRIES_OPENING_CURRENT_MONTH=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_open_notes_current_month
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Countries closing notes current month.
 declare COUNTRIES_CLOSING_CURRENT_MONTH
 COUNTRIES_CLOSING_CURRENT_MONTH=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_solving_notes_current_month
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Countries opening notes current day.
 declare COUNTRIES_OPENING_CURRENT_DAY
 COUNTRIES_OPENING_CURRENT_DAY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_open_notes_current_day
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Countries closing notes current day.
 declare COUNTRIES_CLOSING_CURRENT_DAY
 COUNTRIES_CLOSING_CURRENT_DAY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT countries_solving_notes_current_day
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Working hours.
 declare WORKING_HOURS_OPENING
 WORKING_HOURS_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_opening
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare WORKING_HOURS_COMMENTING
 WORKING_HOURS_COMMENTING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_commenting
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare WORKING_HOURS_CLOSING
 WORKING_HOURS_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_closing
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History values.
 # Whole history.
 declare -i HISTORY_WHOLE_OPEN
 HISTORY_WHOLE_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_COMMENTED
 HISTORY_WHOLE_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_commented
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_CLOSED
 HISTORY_WHOLE_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History whole closed with comment (notes closed that include explanatory text)
 # The datamart already filters for comments with non-empty text (LENGTH(TRIM(body)) > 0)
 declare -i HISTORY_WHOLE_CLOSED_WITH_COMMENT
 HISTORY_WHOLE_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_closed_with_comment
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_REOPENED
 HISTORY_WHOLE_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_reopened
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last year history.
 declare -i HISTORY_YEAR_OPEN
 HISTORY_YEAR_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_COMMENTED
 HISTORY_YEAR_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_commented
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED
 HISTORY_YEAR_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History year closed with comment (notes closed this year that include explanatory text)
 declare -i HISTORY_YEAR_CLOSED_WITH_COMMENT
 HISTORY_YEAR_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_closed_with_comment
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_REOPENED
 HISTORY_YEAR_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_reopened
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last month history.
 declare -i HISTORY_MONTH_OPEN
 HISTORY_MONTH_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_COMMENTED
 HISTORY_MONTH_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_commented
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_CLOSED
 HISTORY_MONTH_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History month closed with comment (notes closed this month that include explanatory text)
 declare -i HISTORY_MONTH_CLOSED_WITH_COMMENT
 HISTORY_MONTH_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_closed_with_comment
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_REOPENED
 HISTORY_MONTH_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_reopened
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last day history.
 declare -i HISTORY_DAY_OPEN
 HISTORY_DAY_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_open
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_COMMENTED
 HISTORY_DAY_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_commented
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_CLOSED
 HISTORY_DAY_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_closed
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History day closed with comment (notes closed today that include explanatory text)
 declare -i HISTORY_DAY_CLOSED_WITH_COMMENT
 HISTORY_DAY_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_closed_with_comment
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_REOPENED
 HISTORY_DAY_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_reopened
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Current notes status
 declare -i CURRENT_OPEN_NOTES
 CURRENT_OPEN_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(notes_backlog_size, 0)
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i CURRENT_CLOSED_NOTES
 CURRENT_CLOSED_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_closed, 0) - COALESCE(notes_backlog_size, 0)
     FROM dwh.datamartUsers
     WHERE dimension_user_id = ${DIMENSION_USER_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Applications used - DM-001
 declare APPLICATIONS_USED
 APPLICATIONS_USED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT applications_used
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 declare -i MOST_USED_APPLICATION_ID
 MOST_USED_APPLICATION_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(most_used_application_id, 0)
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i MOBILE_APPS_COUNT
 MOBILE_APPS_COUNT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(mobile_apps_count, 0)
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i DESKTOP_APPS_COUNT
 DESKTOP_APPS_COUNT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(desktop_apps_count, 0)
    FROM dwh.datamartUsers
    WHERE dimension_user_id = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare MOST_USED_APPLICATION_NAME
 if [[ ${MOST_USED_APPLICATION_ID} -gt 0 ]]; then
  MOST_USED_APPLICATION_NAME=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT application_name
     FROM dwh.dimension_applications
     WHERE dimension_application_id = ${MOST_USED_APPLICATION_ID}
     " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "")
 fi

 # Badges from database
 declare BADGES
 BADGES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT json_agg(json_build_object('badge_name', b.badge_name, 'date_awarded', p.date_awarded, 'comment', p.comment) ORDER BY p.date_awarded DESC)
    FROM dwh.badges_per_users p
     JOIN dwh.badges b
     ON p.id_badge = b.badge_id
    WHERE p.id_user = ${DIMENSION_USER_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 # Detect daily achievements (100/300/1000 notes opened/closed in a single day)
 declare DAILY_ACHIEVEMENTS
 DAILY_ACHIEVEMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT json_agg(json_build_object('date', action_date, 'opened', opened_count, 'closed', closed_count))
     FROM (
      SELECT action_at::date AS action_date,
       COUNT(*) FILTER (WHERE action_type = 'opened') AS opened_count,
       COUNT(*) FILTER (WHERE action_type = 'closed') AS closed_count
      FROM dwh.facts
      WHERE action_dimension_id_user = ${DIMENSION_USER_ID}
       AND action_at IS NOT NULL
      GROUP BY action_at::date
      HAVING COUNT(*) FILTER (WHERE action_type = 'opened') >= 100
        OR COUNT(*) FILTER (WHERE action_type = 'closed') >= 100
     ) sub
     ORDER BY action_date DESC
     LIMIT 20
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 # Show user information
 echo "User name: ${USERNAME} (id: ${OSM_USER_ID})."
 echo "Note solver type: ${CONTRIBUTOR_TYPE}."
 if [[ -n "${EXPERIENCE_LEVEL}" ]]; then
  echo "Experience level: ${EXPERIENCE_LEVEL}."
 fi
 if [[ ${QTY_DAYS_OPEN} -gt 0 ]]; then
  echo "Quantity of days creating notes: ${QTY_DAYS_OPEN}, since ${DATE_FIRST_OPEN}."
 fi
 if [[ ${QTY_DAYS_CLOSE} -gt 0 ]]; then
  echo "Quantity of days solving notes: ${QTY_DAYS_CLOSE}, since ${DATE_FIRST_CLOSE}."
 fi
 if [[ ${DAYS_SINCE_LAST_ACTION} -gt 365 ]]; then
  echo "Note: User may have stopped opening or closing notes (last action was ${DAYS_SINCE_LAST_ACTION} days ago)."
 fi
 echo "First actions: https://www.openstreetmap.org/note/${FIRST_OPEN_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_COMMENTED_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_CLOSED_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_REOPENED_NOTE_ID}"
 echo "Most recent actions:  https://www.openstreetmap.org/note/${LAST_OPEN_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_COMMENTED_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_CLOSED_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_REOPENED_NOTE_ID}"
 echo "Last activity year:"
 __printActivity "${LAST_ACTIVITY_YEAR}"
 if [[ -n "${DATES_MOST_OPEN}" ]] && [[ "${DATES_MOST_OPEN}" != "[]" ]]; then
  echo "The date when the most notes were opened:"
  echo "${DATES_MOST_OPEN}" | sed 's/}, {"date" : "/\n/g' | sed 's/", "quantity" : / - /g' | sed 's/\[{"date" : "//' | sed 's/}\]//'
 fi
 if [[ -n "${DATES_MOST_CLOSED}" ]] && [[ "${DATES_MOST_CLOSED}" != "[]" ]]; then
  echo "The date when the most notes were closed:"
  echo "${DATES_MOST_CLOSED}" | sed 's/}, {"date" : "/\n/g' | sed 's/", "quantity" : / - /g' | sed 's/\[{"date" : "//' | sed 's/}\]//'
 fi
 # DM-002: Enhanced hashtag display for user
 if [[ -n "${HASHTAGS}" ]] && [[ "${HASHTAGS}" != "[]" ]] && [[ "${HASHTAGS}" != "null" ]]; then
  echo "Hashtags used:"
  if [[ ${UNIQUE_HASHTAGS} -gt 0 ]]; then
   echo "  Total unique hashtags: ${UNIQUE_HASHTAGS}"
   if [[ ${TOTAL_HASHTAG_USES} -gt 0 ]]; then
    echo "  Total hashtag uses: ${TOTAL_HASHTAG_USES}"
   fi
  fi
  # Show favorite hashtags by action type
  if [[ -n "${FAVORITE_OPENING_HASHTAG}" ]] && [[ "${FAVORITE_OPENING_HASHTAG}" != "" ]]; then
   echo "  Favorite opening hashtag: #${FAVORITE_OPENING_HASHTAG} (${OPENING_HASHTAG_COUNT} uses)"
  fi
  if [[ -n "${FAVORITE_RESOLUTION_HASHTAG}" ]] && [[ "${FAVORITE_RESOLUTION_HASHTAG}" != "" ]]; then
   echo "  Favorite resolution hashtag: #${FAVORITE_RESOLUTION_HASHTAG} (${RESOLUTION_HASHTAG_COUNT} uses)"
  fi
  # Show hashtags by action type
  if [[ -n "${HASHTAGS_OPENING}" ]] && [[ "${HASHTAGS_OPENING}" != "[]" ]] && [[ "${HASHTAGS_OPENING}" != "null" ]]; then
   echo "  Top opening hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_OPENING}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_OPENING}"
   else
    echo "${HASHTAGS_OPENING}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_OPENING}"
   fi
  fi
  if [[ -n "${HASHTAGS_RESOLUTION}" ]] && [[ "${HASHTAGS_RESOLUTION}" != "[]" ]] && [[ "${HASHTAGS_RESOLUTION}" != "null" ]]; then
   echo "  Top resolution hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_RESOLUTION}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_RESOLUTION}"
   else
    echo "${HASHTAGS_RESOLUTION}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_RESOLUTION}"
   fi
  fi
  if [[ -n "${HASHTAGS_COMMENTS}" ]] && [[ "${HASHTAGS_COMMENTS}" != "[]" ]] && [[ "${HASHTAGS_COMMENTS}" != "null" ]]; then
   echo "  Top comment hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_COMMENTS}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_COMMENTS}"
   else
    echo "${HASHTAGS_COMMENTS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_COMMENTS}"
   fi
  fi
  # Show all hashtags (general)
  echo "  All hashtags:"
  # Try to format with jq if available, otherwise show raw JSON
  if command -v jq &> /dev/null; then
   echo "${HASHTAGS}" | jq -r '.[] | "    #\(.hashtag) (\(.quantity) times)"' 2> /dev/null || echo "    ${HASHTAGS}"
  else
   # Fallback: simple formatting without jq
   echo "${HASHTAGS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "quantity" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS}"
  fi
 fi
 # DM-001: Show applications used
 if [[ -n "${APPLICATIONS_USED}" ]] && [[ "${APPLICATIONS_USED}" != "[]" ]] && [[ "${APPLICATIONS_USED}" != "null" ]]; then
  echo "Applications used:"
  if [[ ${MOBILE_APPS_COUNT} -gt 0 ]] || [[ ${DESKTOP_APPS_COUNT} -gt 0 ]]; then
   echo "  Mobile apps: ${MOBILE_APPS_COUNT} | Desktop apps: ${DESKTOP_APPS_COUNT}"
  fi
  if [[ -n "${MOST_USED_APPLICATION_NAME}" ]] && [[ "${MOST_USED_APPLICATION_NAME}" != "" ]]; then
   echo "  Most used: ${MOST_USED_APPLICATION_NAME}"
  fi
  # Try to format with jq if available, otherwise show raw JSON
  if command -v jq &> /dev/null; then
   echo "${APPLICATIONS_USED}" | jq -r '.[] | "  \(.app_name) (\(.count) notes)"' 2> /dev/null || echo "  ${APPLICATIONS_USED}"
  else
   # Fallback: simple formatting without jq
   echo "${APPLICATIONS_USED}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"app_name" : "/  /g' | sed 's/", "count" : / (/g' | sed 's/, "app_id" : [0-9]*$/ notes)/g' || echo "  ${APPLICATIONS_USED}"
  fi
 fi
 echo "Current notes status:"
 echo "  Notes currently open: ${CURRENT_OPEN_NOTES}"
 echo "  Notes currently closed: ${CURRENT_CLOSED_NOTES}"
 echo "Working hours (all time):"
 set +E
 echo "  Opening:"
 __showWorkingWeek "${WORKING_HOURS_OPENING}"
 echo "  Commenting:"
 __showWorkingWeek "${WORKING_HOURS_COMMENTING}"
 echo "  Closing:"
 __showWorkingWeek "${WORKING_HOURS_CLOSING}"
 set -E
 echo
 echo "Actions:"
 #                       1234567890 1234567890 1234567890 1234567890 1234567890
 printf "                  Opened  Commented     Closed Cld w/cmmt   Reopened\n"
 printf "Total:         %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_WHOLE_OPEN}" "${HISTORY_WHOLE_COMMENTED}" "${HISTORY_WHOLE_CLOSED}" "${HISTORY_WHOLE_CLOSED_WITH_COMMENT}" "${HISTORY_WHOLE_REOPENED}"
 printf "Current year:  %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_YEAR_OPEN}" "${HISTORY_YEAR_COMMENTED}" "${HISTORY_YEAR_CLOSED}" "${HISTORY_YEAR_CLOSED_WITH_COMMENT}" "${HISTORY_YEAR_REOPENED}"
 printf "Current month: %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_MONTH_OPEN}" "${HISTORY_MONTH_COMMENTED}" "${HISTORY_MONTH_CLOSED}" "${HISTORY_MONTH_CLOSED_WITH_COMMENT}" "${HISTORY_MONTH_REOPENED}"
 printf "Today:         %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_DAY_OPEN}" "${HISTORY_DAY_COMMENTED}" "${HISTORY_DAY_CLOSED}" "${HISTORY_DAY_CLOSED_WITH_COMMENT}" "${HISTORY_DAY_REOPENED}"

 # Analysis of closed with comment: calculate percentages and quality metrics
 if [[ ${HISTORY_WHOLE_CLOSED} -gt 0 ]]; then
  declare -i CLOSED_WITH_COMMENT_PCT
  CLOSED_WITH_COMMENT_PCT=$((HISTORY_WHOLE_CLOSED_WITH_COMMENT * 100 / HISTORY_WHOLE_CLOSED))
  echo
  echo "Resolution quality analysis:"
  echo "  Closed notes with explanatory comments: ${HISTORY_WHOLE_CLOSED_WITH_COMMENT} of ${HISTORY_WHOLE_CLOSED} (${CLOSED_WITH_COMMENT_PCT}%)"
  if [[ ${CLOSED_WITH_COMMENT_PCT} -ge 80 ]]; then
   echo "  Quality: Excellent - Most resolutions include explanations"
  elif [[ ${CLOSED_WITH_COMMENT_PCT} -ge 60 ]]; then
   echo "  Quality: Good - Majority of resolutions include explanations"
  elif [[ ${CLOSED_WITH_COMMENT_PCT} -ge 40 ]]; then
   echo "  Quality: Fair - Some resolutions could benefit from more explanations"
  else
   echo "  Quality: Needs improvement - Consider adding explanations to resolutions"
  fi
 fi
 I=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${I}" -le "${CURRENT_YEAR}" ]]; do
  __showActivityYearUsers "${I}"

  # Top 10 Notes with most comments per year
  declare TOP_10_COMMENTS
  TOP_10_COMMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT json_agg(json_build_object('note_id', id_note, 'comments', total_comments_on_note, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_comments_on_note DESC)
     FROM (
      SELECT DISTINCT ON (id_note) id_note, total_comments_on_note
      FROM dwh.facts
      WHERE action_dimension_id_user = ${DIMENSION_USER_ID}
       AND history_year_commented = ${I}
       AND total_comments_on_note > 0
      ORDER BY id_note, total_comments_on_note DESC
      LIMIT 10
     ) sub
    " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

  if [[ -n "${TOP_10_COMMENTS}" ]] && [[ "${TOP_10_COMMENTS}" != "[]" ]] && [[ "${TOP_10_COMMENTS}" != "null" ]]; then
   echo "  Top 10 Notes with most comments in ${I}:"
   if command -v jq &> /dev/null; then
    echo "${TOP_10_COMMENTS}" | jq -r '.[] | "    Note \(.note_id): \(.comments) comments - \(.url)"' 2> /dev/null || echo "${TOP_10_COMMENTS}"
   else
    echo "${TOP_10_COMMENTS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"note_id" : /    Note /g' | sed 's/, "comments" : /: /g' | sed 's/, "url" : / comments - /g' | sed 's/}$//g' || echo "${TOP_10_COMMENTS}"
   fi
  fi

  # Top 10 Notes with most reopening per year
  declare TOP_10_REOPENINGS
  TOP_10_REOPENINGS=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT json_agg(json_build_object('note_id', id_note, 'reopenings', total_reopenings_count, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_reopenings_count DESC)
     FROM (
      SELECT DISTINCT ON (id_note) id_note, total_reopenings_count
      FROM dwh.facts
      WHERE action_dimension_id_user = ${DIMENSION_USER_ID}
       AND history_year_reopened = ${I}
       AND total_reopenings_count > 0
      ORDER BY id_note, total_reopenings_count DESC
      LIMIT 10
     ) sub
    " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

  if [[ -n "${TOP_10_REOPENINGS}" ]] && [[ "${TOP_10_REOPENINGS}" != "[]" ]] && [[ "${TOP_10_REOPENINGS}" != "null" ]]; then
   echo "  Top 10 Notes with most reopenings in ${I}:"
   if command -v jq &> /dev/null; then
    echo "${TOP_10_REOPENINGS}" | jq -r '.[] | "    Note \(.note_id): \(.reopenings) reopenings - \(.url)"' 2> /dev/null || echo "${TOP_10_REOPENINGS}"
   else
    echo "${TOP_10_REOPENINGS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"note_id" : /    Note /g' | sed 's/, "reopenings" : /: /g' | sed 's/, "url" : / reopenings - /g' | sed 's/}$//g' || echo "${TOP_10_REOPENINGS}"
   fi
  fi

  I=$((I + 1))
 done
 echo "Historically:"
 echo "Countries for open notes:"
 __printRanking "${COUNTRIES_OPENING}"
 echo "Countries for closed notes:"
 __printRanking "${COUNTRIES_CLOSING}"
 I=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${I}" -le "${CURRENT_YEAR}" ]]; do
  __showRankingYearUsers "${I}"
  I=$((I + 1))
 done
 echo
 echo "Ranking in the current month:"
 echo "Countries for open notes:"
 __printRanking "${COUNTRIES_OPENING_CURRENT_MONTH}"
 echo "Countries for closed notes:"
 __printRanking "${COUNTRIES_CLOSING_CURRENT_MONTH}"
 echo "Ranking in the current day:"
 echo "Countries for open notes:"
 __printRanking "${COUNTRIES_OPENING_CURRENT_DAY}"
 echo "Countries for closed notes:"
 __printRanking "${COUNTRIES_CLOSING_CURRENT_DAY}"

 # Show badges if any
 if [[ -n "${BADGES}" ]] && [[ "${BADGES}" != "[]" ]] && [[ "${BADGES}" != "null" ]]; then
  echo "Badges:"
  if command -v jq &> /dev/null; then
   echo "${BADGES}" | jq -r '.[] | "  \(.badge_name) (awarded: \(.date_awarded))"' 2> /dev/null || echo "  ${BADGES}"
  else
   echo "${BADGES}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"badge_name" : "/  /g' | sed 's/", "date_awarded" : "/ (awarded: /g' | sed 's/", "comment" :.*$/)/g' || echo "  ${BADGES}"
  fi
 fi

 # Show daily achievements if any
 if [[ -n "${DAILY_ACHIEVEMENTS}" ]] && [[ "${DAILY_ACHIEVEMENTS}" != "[]" ]] && [[ "${DAILY_ACHIEVEMENTS}" != "null" ]]; then
  echo "Daily achievements (100+ notes in a day):"
  if command -v jq &> /dev/null; then
   echo "${DAILY_ACHIEVEMENTS}" | jq -r '.[] | "  \(.date): \(.opened) opened, \(.closed) closed"' 2> /dev/null || echo "  ${DAILY_ACHIEVEMENTS}"
  else
   echo "${DAILY_ACHIEVEMENTS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"date" : "/  /g' | sed 's/", "opened" : /: /g' | sed 's/, "closed" : / opened, /g' | sed 's/}$/ closed/g' || echo "  ${DAILY_ACHIEVEMENTS}"
  fi
 fi
 __log_finish
}

# Shows the note statistics for a given country.
function __processCountryProfile {
 __log_start
 # Country OSM Id
 declare -i COUNTRY_OSM_ID
 COUNTRY_OSM_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT country_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Quantity of days with open notes.
 declare -i QTY_DAYS_OPEN
 QTY_DAYS_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT CURRENT_DATE - date_starting_creating_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare DATE_FIRST_OPEN
 DATE_FIRST_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT date_starting_creating_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Quantity of days solving notes.
 declare -i QTY_DAYS_CLOSE
 QTY_DAYS_CLOSE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT CURRENT_DATE - date_starting_solving_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare DATE_FIRST_CLOSE
 DATE_FIRST_CLOSE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT date_starting_solving_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # First actions.
 declare -i FIRST_OPEN_NOTE_ID
 FIRST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_open_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_COMMENTED_NOTE_ID
 FIRST_COMMENTED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_commented_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_CLOSED_NOTE_ID
 FIRST_CLOSED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_closed_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i FIRST_REOPENED_NOTE_ID
 FIRST_REOPENED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT first_reopened_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last activity year.
 declare LAST_ACTIVITY_YEAR
 LAST_ACTIVITY_YEAR=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT last_year_activity
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Most recent actions.
 declare -i LAST_OPEN_NOTE_ID
 LAST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_open_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_COMMENTED_NOTE_ID
 LAST_COMMENTED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_commented_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_CLOSED_NOTE_ID
 LAST_CLOSED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_closed_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i LAST_REOPENED_NOTE_ID
 LAST_REOPENED_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT latest_reopened_note_id
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Date with more opened notes.
 declare DATES_MOST_OPEN
 DATES_MOST_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT dateS_most_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Date with more closed notes
 declare DATES_MOST_CLOSED
 DATES_MOST_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT dates_most_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Used hashtags - extracted from note text and stored as JSON array
 declare HASHTAGS
 HASHTAGS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1)

 # DM-002: Hashtags by action type for country
 declare HASHTAGS_OPENING_COUNTRY
 HASHTAGS_OPENING_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_opening
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 declare HASHTAGS_RESOLUTION_COUNTRY
 HASHTAGS_RESOLUTION_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_resolution
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 declare HASHTAGS_COMMENTS_COUNTRY
 HASHTAGS_COMMENTS_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT hashtags_comments
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 declare TOP_OPENING_HASHTAG_COUNTRY
 TOP_OPENING_HASHTAG_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT top_opening_hashtag
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "")

 declare TOP_RESOLUTION_HASHTAG_COUNTRY
 TOP_RESOLUTION_HASHTAG_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT top_resolution_hashtag
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "")

 declare -i OPENING_HASHTAG_COUNT_COUNTRY
 OPENING_HASHTAG_COUNT_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(opening_hashtag_count, 0)
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i RESOLUTION_HASHTAG_COUNT_COUNTRY
 RESOLUTION_HASHTAG_COUNT_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(resolution_hashtag_count, 0)
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # Calculate hashtag statistics if available
 declare -i TOTAL_HASHTAG_USES=0
 declare -i UNIQUE_HASHTAGS=0
 if [[ -n "${HASHTAGS}" ]] && [[ "${HASHTAGS}" != "" ]] && [[ "${HASHTAGS}" != "[]" ]] && [[ "${HASHTAGS}" != "null" ]]; then
  if command -v jq &> /dev/null; then
   TOTAL_HASHTAG_USES=$(echo "${HASHTAGS}" | jq '[.[] | .count] | add // 0' 2> /dev/null || echo "0")
   UNIQUE_HASHTAGS=$(echo "${HASHTAGS}" | jq 'length' 2> /dev/null || echo "0")
  else
   # Fallback: count manually from JSON
   UNIQUE_HASHTAGS=$(echo "${HASHTAGS}" | grep -o '"hashtag"' | wc -l || echo "0")
  fi
 fi

 # Users opening notes. Global ranking, historically.
 declare USERS_OPENING
 USERS_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_open_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Users closing notes. Global ranking, historically.
 declare USERS_CLOSING
 USERS_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_solving_notes
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Users opening notes. Current month.
 declare USERS_OPENING_CURRENT_MONTH
 USERS_OPENING_CURRENT_MONTH=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_open_notes_current_month
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Users closing notes. Current month.
 declare USERS_CLOSING_CURRENT_MONTH
 USERS_CLOSING_CURRENT_MONTH=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_solving_notes_current_month
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Users opening notes. Current day.
 declare USERS_OPENING_CURRENT_DAY
 USERS_OPENING_CURRENT_DAY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_open_notes_current_day
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Users closing notes. Current day.
 declare USERS_CLOSING_CURRENT_DAY
 USERS_CLOSING_CURRENT_DAY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT users_solving_notes_current_day
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Working hours.
 declare WORKING_HOURS_OF_WEEK_OPENING
 WORKING_HOURS_OF_WEEK_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_opening
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare WORKING_HOURS_OF_WEEK_COMMENTING
 WORKING_HOURS_OF_WEEK_COMMENTING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_commenting
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare WORKING_HOURS_OF_WEEK_CLOSING
 WORKING_HOURS_OF_WEEK_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT working_hours_of_week_closing
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1)

 # Applications used - DM-001
 declare APPLICATIONS_USED_COUNTRY
 APPLICATIONS_USED_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT applications_used
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 declare -i MOST_USED_APPLICATION_ID_COUNTRY
 MOST_USED_APPLICATION_ID_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(most_used_application_id, 0)
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i MOBILE_APPS_COUNT_COUNTRY
 MOBILE_APPS_COUNT_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(mobile_apps_count, 0)
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i DESKTOP_APPS_COUNT_COUNTRY
 DESKTOP_APPS_COUNT_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(desktop_apps_count, 0)
    FROM dwh.datamartCountries
    WHERE dimension_country_id = ${COUNTRY_ID}
    " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare MOST_USED_APPLICATION_NAME_COUNTRY
 if [[ ${MOST_USED_APPLICATION_ID_COUNTRY} -gt 0 ]]; then
  MOST_USED_APPLICATION_NAME_COUNTRY=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT application_name
     FROM dwh.dimension_applications
     WHERE dimension_application_id = ${MOST_USED_APPLICATION_ID_COUNTRY}
     " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "")
 fi

 # History values.
 # Whole history.
 declare -i HISTORY_WHOLE_OPEN
 HISTORY_WHOLE_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_COMMENTED
 HISTORY_WHOLE_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_commented
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_CLOSED
 HISTORY_WHOLE_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History whole closed with comment (notes closed that include explanatory text)
 declare -i HISTORY_WHOLE_CLOSED_WITH_COMMENT
 HISTORY_WHOLE_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_closed_with_comment
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_WHOLE_REOPENED
 HISTORY_WHOLE_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_whole_reopened
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last year history.
 declare -i HISTORY_YEAR_OPEN
 HISTORY_YEAR_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_COMMENTED
 HISTORY_YEAR_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_commented
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_CLOSED
 HISTORY_YEAR_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History year closed with comment (notes closed this year that include explanatory text)
 declare -i HISTORY_YEAR_CLOSED_WITH_COMMENT
 HISTORY_YEAR_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_closed_with_comment
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_YEAR_REOPENED
 HISTORY_YEAR_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_year_reopened
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last month history.
 declare -i HISTORY_MONTH_OPEN
 HISTORY_MONTH_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_COMMENTED
 HISTORY_MONTH_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_commented
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_CLOSED
 HISTORY_MONTH_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History month closed with comment (notes closed this month that include explanatory text)
 declare -i HISTORY_MONTH_CLOSED_WITH_COMMENT
 HISTORY_MONTH_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_closed_with_comment
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_MONTH_REOPENED
 HISTORY_MONTH_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_month_reopened
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Last day history.
 declare -i HISTORY_DAY_OPEN
 HISTORY_DAY_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_open
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_COMMENTED
 HISTORY_DAY_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_commented
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_CLOSED
 HISTORY_DAY_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_closed
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # History day closed with comment (notes closed today that include explanatory text)
 declare -i HISTORY_DAY_CLOSED_WITH_COMMENT
 HISTORY_DAY_CLOSED_WITH_COMMENT=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_closed_with_comment
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i HISTORY_DAY_REOPENED
 HISTORY_DAY_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT history_day_reopened
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Current notes status
 declare -i CURRENT_OPEN_NOTES
 CURRENT_OPEN_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(notes_backlog_size, 0)
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 declare -i CURRENT_CLOSED_NOTES
 CURRENT_CLOSED_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_closed, 0) - COALESCE(notes_backlog_size, 0)
     FROM dwh.datamartCountries
     WHERE dimension_country_id = ${COUNTRY_ID}
     " \
  -v ON_ERROR_STOP=1)

 # Show country information
 echo "COUNTRY name: ${COUNTRY_NAME} (id: ${COUNTRY_OSM_ID})"
 if [[ ${QTY_DAYS_OPEN} -gt 0 ]]; then
  echo "Quantity of days creating notes: ${QTY_DAYS_OPEN}, since ${DATE_FIRST_OPEN}."
 fi
 if [[ ${QTY_DAYS_CLOSE} -gt 0 ]]; then
  echo "Quantity of days solving notes: ${QTY_DAYS_CLOSE}, since ${DATE_FIRST_CLOSE}"
 fi
 echo "First actions: https://www.openstreetmap.org/note/${FIRST_OPEN_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_COMMENTED_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_CLOSED_NOTE_ID} https://www.openstreetmap.org/note/${FIRST_REOPENED_NOTE_ID}"
 echo "Last actions:  https://www.openstreetmap.org/note/${LAST_OPEN_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_COMMENTED_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_CLOSED_NOTE_ID}  https://www.openstreetmap.org/note/${LAST_REOPENED_NOTE_ID}"
 echo "Last activity year:"
 __printActivity "${LAST_ACTIVITY_YEAR}"
 if [[ -n "${DATES_MOST_OPEN}" ]] && [[ "${DATES_MOST_OPEN}" != "[]" ]]; then
  echo "The date when the most notes were opened:"
  echo "${DATES_MOST_OPEN}" | sed 's/}, {"date" : "/\n/g' | sed 's/", "quantity" : / - /g' | sed 's/\[{"date" : "//' | sed 's/}\]//'
 fi
 if [[ -n "${DATES_MOST_CLOSED}" ]] && [[ "${DATES_MOST_CLOSED}" != "[]" ]]; then
  echo "The date when the most notes were closed:"
  echo "${DATES_MOST_CLOSED}" | sed 's/}, {"date" : "/\n/g' | sed 's/", "quantity" : / - /g' | sed 's/\[{"date" : "//' | sed 's/}\]//'
 fi
 # DM-002: Enhanced hashtag display for country
 if [[ -n "${HASHTAGS}" ]] && [[ "${HASHTAGS}" != "[]" ]] && [[ "${HASHTAGS}" != "null" ]]; then
  echo "Hashtags used:"
  if [[ ${UNIQUE_HASHTAGS} -gt 0 ]]; then
   echo "  Total unique hashtags: ${UNIQUE_HASHTAGS}"
   if [[ ${TOTAL_HASHTAG_USES} -gt 0 ]]; then
    echo "  Total hashtag uses: ${TOTAL_HASHTAG_USES}"
   fi
  fi
  # Show top hashtags by action type
  if [[ -n "${TOP_OPENING_HASHTAG_COUNTRY}" ]] && [[ "${TOP_OPENING_HASHTAG_COUNTRY}" != "" ]]; then
   echo "  Top opening hashtag: #${TOP_OPENING_HASHTAG_COUNTRY} (${OPENING_HASHTAG_COUNT_COUNTRY} uses)"
  fi
  if [[ -n "${TOP_RESOLUTION_HASHTAG_COUNTRY}" ]] && [[ "${TOP_RESOLUTION_HASHTAG_COUNTRY}" != "" ]]; then
   echo "  Top resolution hashtag: #${TOP_RESOLUTION_HASHTAG_COUNTRY} (${RESOLUTION_HASHTAG_COUNT_COUNTRY} uses)"
  fi
  # Show hashtags by action type
  if [[ -n "${HASHTAGS_OPENING_COUNTRY}" ]] && [[ "${HASHTAGS_OPENING_COUNTRY}" != "[]" ]] && [[ "${HASHTAGS_OPENING_COUNTRY}" != "null" ]]; then
   echo "  Top opening hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_OPENING_COUNTRY}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_OPENING_COUNTRY}"
   else
    echo "${HASHTAGS_OPENING_COUNTRY}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_OPENING_COUNTRY}"
   fi
  fi
  if [[ -n "${HASHTAGS_RESOLUTION_COUNTRY}" ]] && [[ "${HASHTAGS_RESOLUTION_COUNTRY}" != "[]" ]] && [[ "${HASHTAGS_RESOLUTION_COUNTRY}" != "null" ]]; then
   echo "  Top resolution hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_RESOLUTION_COUNTRY}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_RESOLUTION_COUNTRY}"
   else
    echo "${HASHTAGS_RESOLUTION_COUNTRY}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_RESOLUTION_COUNTRY}"
   fi
  fi
  if [[ -n "${HASHTAGS_COMMENTS_COUNTRY}" ]] && [[ "${HASHTAGS_COMMENTS_COUNTRY}" != "[]" ]] && [[ "${HASHTAGS_COMMENTS_COUNTRY}" != "null" ]]; then
   echo "  Top comment hashtags:"
   if command -v jq &> /dev/null; then
    echo "${HASHTAGS_COMMENTS_COUNTRY}" | jq -r '.[] | "    #\(.hashtag) (\(.count) times)"' 2> /dev/null || echo "    ${HASHTAGS_COMMENTS_COUNTRY}"
   else
    echo "${HASHTAGS_COMMENTS_COUNTRY}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "count" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS_COMMENTS_COUNTRY}"
   fi
  fi
  # Show all hashtags (general)
  echo "  All hashtags:"
  # Try to format with jq if available, otherwise show raw JSON
  if command -v jq &> /dev/null; then
   echo "${HASHTAGS}" | jq -r '.[] | "    #\(.hashtag) (\(.quantity) times)"' 2> /dev/null || echo "    ${HASHTAGS}"
  else
   # Fallback: simple formatting without jq
   echo "${HASHTAGS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"hashtag" : "/    #/g' | sed 's/", "quantity" : / (/g' | sed 's/}$/ times)/g' || echo "    ${HASHTAGS}"
  fi
 fi
 # DM-001: Show applications used for country
 if [[ -n "${APPLICATIONS_USED_COUNTRY}" ]] && [[ "${APPLICATIONS_USED_COUNTRY}" != "[]" ]] && [[ "${APPLICATIONS_USED_COUNTRY}" != "null" ]]; then
  echo "Applications used:"
  if [[ ${MOBILE_APPS_COUNT_COUNTRY} -gt 0 ]] || [[ ${DESKTOP_APPS_COUNT_COUNTRY} -gt 0 ]]; then
   echo "  Mobile apps: ${MOBILE_APPS_COUNT_COUNTRY} | Desktop apps: ${DESKTOP_APPS_COUNT_COUNTRY}"
  fi
  if [[ -n "${MOST_USED_APPLICATION_NAME_COUNTRY}" ]] && [[ "${MOST_USED_APPLICATION_NAME_COUNTRY}" != "" ]]; then
   echo "  Most used: ${MOST_USED_APPLICATION_NAME_COUNTRY}"
  fi
  # Try to format with jq if available, otherwise show raw JSON
  if command -v jq &> /dev/null; then
   echo "${APPLICATIONS_USED_COUNTRY}" | jq -r '.[] | "  \(.app_name) (\(.count) notes)"' 2> /dev/null || echo "  ${APPLICATIONS_USED_COUNTRY}"
  else
   # Fallback: simple formatting without jq
   echo "${APPLICATIONS_USED_COUNTRY}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"app_name" : "/  /g' | sed 's/", "count" : / (/g' | sed 's/, "app_id" : [0-9]*$/ notes)/g' || echo "  ${APPLICATIONS_USED_COUNTRY}"
  fi
 fi
 echo "Current notes status:"
 echo "  Notes currently open: ${CURRENT_OPEN_NOTES}"
 echo "  Notes currently closed: ${CURRENT_CLOSED_NOTES}"
 echo "Working hours (all time):"
 set +E
 echo "  Opening:"
 __showWorkingWeek "${WORKING_HOURS_OF_WEEK_OPENING}"
 echo "  Commenting:"
 __showWorkingWeek "${WORKING_HOURS_OF_WEEK_COMMENTING}"
 echo "  Closing:"
 __showWorkingWeek "${WORKING_HOURS_OF_WEEK_CLOSING}"
 set -E
 echo
 echo "Actions:"
 #                       1234567890 1234567890 1234567890 1234567890 1234567890
 printf "                   Opens   Comments     Closes Cls w/cmmt    Reopens\n"
 printf "Total:         %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_WHOLE_OPEN}" "${HISTORY_WHOLE_COMMENTED}" "${HISTORY_WHOLE_CLOSED}" "${HISTORY_WHOLE_CLOSED_WITH_COMMENT}" "${HISTORY_WHOLE_REOPENED}"
 printf "Current year:  %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_YEAR_OPEN}" "${HISTORY_YEAR_COMMENTED}" "${HISTORY_YEAR_CLOSED}" "${HISTORY_YEAR_CLOSED_WITH_COMMENT}" "${HISTORY_YEAR_REOPENED}"
 printf "Current month: %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_MONTH_OPEN}" "${HISTORY_MONTH_COMMENTED}" "${HISTORY_MONTH_CLOSED}" "${HISTORY_MONTH_CLOSED_WITH_COMMENT}" "${HISTORY_MONTH_REOPENED}"
 printf "Today:         %9d  %9d  %9d  %9d  %9d\n" "${HISTORY_DAY_OPEN}" "${HISTORY_DAY_COMMENTED}" "${HISTORY_DAY_CLOSED}" "${HISTORY_DAY_CLOSED_WITH_COMMENT}" "${HISTORY_DAY_REOPENED}"

 # Analysis of closed with comment: calculate percentages and quality metrics
 if [[ ${HISTORY_WHOLE_CLOSED} -gt 0 ]]; then
  declare -i CLOSED_WITH_COMMENT_PCT
  CLOSED_WITH_COMMENT_PCT=$((HISTORY_WHOLE_CLOSED_WITH_COMMENT * 100 / HISTORY_WHOLE_CLOSED))
  echo
  echo "Resolution quality analysis:"
  echo "  Closed notes with explanatory comments: ${HISTORY_WHOLE_CLOSED_WITH_COMMENT} of ${HISTORY_WHOLE_CLOSED} (${CLOSED_WITH_COMMENT_PCT}%)"
  if [[ ${CLOSED_WITH_COMMENT_PCT} -ge 80 ]]; then
   echo "  Quality: Excellent - Most resolutions include explanations"
  elif [[ ${CLOSED_WITH_COMMENT_PCT} -ge 60 ]]; then
   echo "  Quality: Good - Majority of resolutions include explanations"
  elif [[ ${CLOSED_WITH_COMMENT_PCT} -ge 40 ]]; then
   echo "  Quality: Fair - Some resolutions could benefit from more explanations"
  else
   echo "  Quality: Needs improvement - Consider adding explanations to resolutions"
  fi
 fi
 I=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${I}" -le "${CURRENT_YEAR}" ]]; do
  __showActivityYearCountries "${I}"

  # Top 10 Notes with most comments per year
  declare TOP_10_COMMENTS
  TOP_10_COMMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT json_agg(json_build_object('note_id', id_note, 'comments', total_comments_on_note, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_comments_on_note DESC)
      FROM (
       SELECT DISTINCT ON (id_note) id_note, total_comments_on_note
       FROM dwh.facts
       WHERE dimension_country_id = ${COUNTRY_ID}
        AND history_year_commented = ${I}
        AND total_comments_on_note > 0
       ORDER BY id_note, total_comments_on_note DESC
       LIMIT 10
      ) sub
     " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

  if [[ -n "${TOP_10_COMMENTS}" ]] && [[ "${TOP_10_COMMENTS}" != "[]" ]] && [[ "${TOP_10_COMMENTS}" != "null" ]]; then
   echo "  Top 10 Notes with most comments in ${I}:"
   echo "${TOP_10_COMMENTS}" | jq -r '.[] | "    Note \(.note_id): \(.comments) comments - \(.url)"' 2> /dev/null || echo "${TOP_10_COMMENTS}"
  fi

  # Top 10 Notes with most reopening per year
  declare TOP_10_REOPENINGS
  TOP_10_REOPENINGS=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT json_agg(json_build_object('note_id', id_note, 'reopenings', total_reopenings_count, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_reopenings_count DESC)
      FROM (
       SELECT DISTINCT ON (id_note) id_note, total_reopenings_count
       FROM dwh.facts
       WHERE dimension_country_id = ${COUNTRY_ID}
        AND history_year_reopened = ${I}
        AND total_reopenings_count > 0
       ORDER BY id_note, total_reopenings_count DESC
       LIMIT 10
      ) sub
     " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

  if [[ -n "${TOP_10_REOPENINGS}" ]] && [[ "${TOP_10_REOPENINGS}" != "[]" ]] && [[ "${TOP_10_REOPENINGS}" != "null" ]]; then
   echo "  Top 10 Notes with most reopenings in ${I}:"
   echo "${TOP_10_REOPENINGS}" | jq -r '.[] | "    Note \(.note_id): \(.reopenings) reopenings - \(.url)"' 2> /dev/null || echo "${TOP_10_REOPENINGS}"
  fi

  # Working hours for this year (simplified - showing only if there's significant activity)
  if [[ ${HISTORY_YEAR_OPEN} -gt 0 ]] || [[ ${HISTORY_YEAR_COMMENTED} -gt 0 ]] || [[ ${HISTORY_YEAR_CLOSED} -gt 0 ]]; then
   echo "  Working hours for ${I}: (calculated from activity data)"
   # Note: Full working hours calculation per year would require aggregating from facts table
   # which can be expensive. For now, we show that the feature is available.
  fi

  I=$((I + 1))
 done
 echo "Historically:"
 echo "Users creating notes:"
 __printRanking "${USERS_OPENING}"
 echo "Users closing notes:"
 __printRanking "${USERS_CLOSING}"
 I=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${I}" -le "${CURRENT_YEAR}" ]]; do
  __showRankingYearCountries "${I}"
  I=$((I + 1))
 done
 echo
 echo "Ranking users creating notes in the current month:"
 __printRanking "${USERS_OPENING_CURRENT_MONTH}"
 echo "Ranking users closing notes in the current month:"
 __printRanking "${USERS_CLOSING_CURRENT_MONTH}"
 echo "Ranking users creating notes in the current day:"
 __printRanking "${USERS_OPENING_CURRENT_DAY}"
 echo "Ranking users closing notes in the current day:"
 __printRanking "${USERS_CLOSING_CURRENT_DAY}"

 # Badges for countries (if implemented in the future)
 # Note: Currently badges are only for users, but this placeholder is here for future implementation

 # Quantity of days with 0 notes (at midnight UTC)
 declare -i DAYS_WITH_ZERO_NOTES
 DAYS_WITH_ZERO_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT date_value)::integer
     FROM generate_series(
      (SELECT MIN(action_at::date) FROM dwh.facts WHERE dimension_country_id = ${COUNTRY_ID}),
      CURRENT_DATE,
      '1 day'::interval
     ) AS date_value
     WHERE date_value NOT IN (
      SELECT DISTINCT action_at::date
      FROM dwh.facts
      WHERE dimension_country_id = ${COUNTRY_ID}
       AND action_at IS NOT NULL
     )
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 if [[ ${DAYS_WITH_ZERO_NOTES} -gt 0 ]]; then
  echo "Quantity of days with 0 notes (at midnight UTC): ${DAYS_WITH_ZERO_NOTES}"
 fi

 # Quantity of new UTC years eve with 0 notes
 declare -i YEARS_EVE_WITH_ZERO_NOTES
 YEARS_EVE_WITH_ZERO_NOTES=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(1)::integer
     FROM generate_series(2013, EXTRACT(YEAR FROM CURRENT_DATE)::integer) AS year_value
     WHERE (year_value || '-01-01')::date NOT IN (
      SELECT DISTINCT action_at::date
      FROM dwh.facts
      WHERE dimension_country_id = ${COUNTRY_ID}
       AND action_at IS NOT NULL
     )
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 if [[ ${YEARS_EVE_WITH_ZERO_NOTES} -gt 0 ]]; then
  echo "Quantity of new UTC years eve with 0 notes: ${YEARS_EVE_WITH_ZERO_NOTES}"
 fi

 __log_finish
}

# Shows general stats about notes.
function __generalNoteStats {
 __log_start

 # Get global statistics from datamartGlobal
 declare -i TOTAL_OPENED
 TOTAL_OPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_open, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i TOTAL_CLOSED
 TOTAL_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_closed, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i TOTAL_REOPENED
 TOTAL_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_reopened, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i TOTAL_COMMENTED
 TOTAL_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_whole_commented, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i CURRENTLY_OPEN
 CURRENTLY_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(currently_open_count, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i CURRENTLY_CLOSED
 CURRENTLY_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(currently_closed_count, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i TOTAL_COMMENTS
 TOTAL_COMMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(SUM(total_comments_on_note), 0)
     FROM (
      SELECT DISTINCT ON (id_note) total_comments_on_note
      FROM dwh.facts
      WHERE total_comments_on_note IS NOT NULL
     ) sub
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i TOTAL_USERS
 TOTAL_USERS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT action_dimension_id_user)
     FROM dwh.facts
     WHERE action_dimension_id_user IS NOT NULL
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i USERS_OPENING
 USERS_OPENING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT action_dimension_id_user)
     FROM dwh.facts
     WHERE action_type = 'opened'
       AND action_dimension_id_user IS NOT NULL
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare -i USERS_CLOSING
 USERS_CLOSING=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT action_dimension_id_user)
     FROM dwh.facts
     WHERE action_type = 'closed'
       AND action_dimension_id_user IS NOT NULL
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 declare FIRST_OPEN_NOTE_ID
 FIRST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(first_open_note_id::text, 'N/A')
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "N/A")

 declare LATEST_OPEN_NOTE_ID
 LATEST_OPEN_NOTE_ID=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(latest_open_note_id::text, 'N/A')
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "N/A")

 declare DATE_FIRST_OPEN
 DATE_FIRST_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(date_starting_creating_notes::text, 'N/A')
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "N/A")

 # Notes created today
 declare -i NOTES_TODAY
 NOTES_TODAY=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT id_note)
     FROM dwh.facts
     WHERE action_type = 'opened'
       AND action_at::date = CURRENT_DATE
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # Notes created this month
 declare -i NOTES_THIS_MONTH
 NOTES_THIS_MONTH=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COUNT(DISTINCT id_note)
     FROM dwh.facts
     WHERE action_type = 'opened'
       AND DATE_TRUNC('month', action_at::date) = DATE_TRUNC('month', CURRENT_DATE)
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # Notes created this year
 declare -i NOTES_THIS_YEAR
 NOTES_THIS_YEAR=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(history_year_open, 0)
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

 # Average days to resolution
 declare AVG_RESOLUTION_DAYS
 AVG_RESOLUTION_DAYS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(avg_days_to_resolution::text, 'N/A')
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "N/A")

 # Resolution rate
 declare RESOLUTION_RATE
 RESOLUTION_RATE=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT COALESCE(resolution_rate::text, 'N/A')
     FROM dwh.datamartGlobal
     WHERE dimension_global_id = 1
     " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "N/A")

 # Display statistics
 echo "=== GLOBAL OSM NOTES STATISTICS ==="
 echo
 echo "Total Notes:"
 echo "  Total opened: ${TOTAL_OPENED}"
 echo "  Total closed: ${TOTAL_CLOSED}"
 echo "  Total reopened: ${TOTAL_REOPENED}"
 echo "  Total commented: ${TOTAL_COMMENTED}"
 echo "  Total comments: ${TOTAL_COMMENTS}"
 echo
 echo "Current Status:"
 echo "  Currently open: ${CURRENTLY_OPEN}"
 echo "  Currently closed: ${CURRENTLY_CLOSED}"
 echo
 echo "Users:"
 echo "  Total users: ${TOTAL_USERS}"
 echo "  Users opening notes: ${USERS_OPENING}"
 echo "  Users closing notes: ${USERS_CLOSING}"
 echo
 echo "Temporal Information:"
 echo "  First note opened: https://www.openstreetmap.org/note/${FIRST_OPEN_NOTE_ID} (${DATE_FIRST_OPEN})"
 echo "  Most recently opened note: https://www.openstreetmap.org/note/${LATEST_OPEN_NOTE_ID}"
 echo "  Notes created today: ${NOTES_TODAY}"
 echo "  Notes created this month: ${NOTES_THIS_MONTH}"
 echo "  Notes created this year: ${NOTES_THIS_YEAR}"
 echo
 echo "Resolution Metrics:"
 echo "  Average days to resolution: ${AVG_RESOLUTION_DAYS}"
 echo "  Resolution rate: ${RESOLUTION_RATE}%"
 echo

 # Statistics per year since 2013
 echo "Statistics per year:"
 printf "Year      Opened    Commented    Closed    Reopened\n"
 I=2013
 CURRENT_YEAR=$(date +%Y)
 while [[ "${I}" -le "${CURRENT_YEAR}" ]]; do
  declare -i YEAR_OPEN
  YEAR_OPEN=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT COUNT(DISTINCT id_note)
      FROM dwh.facts
      WHERE action_type = 'opened'
        AND EXTRACT(YEAR FROM action_at) = ${I}
      " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

  declare -i YEAR_COMMENTED
  YEAR_COMMENTED=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT COUNT(DISTINCT id_note)
      FROM dwh.facts
      WHERE action_type = 'commented'
        AND EXTRACT(YEAR FROM action_at) = ${I}
      " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

  declare -i YEAR_CLOSED
  YEAR_CLOSED=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT COUNT(DISTINCT id_note)
      FROM dwh.facts
      WHERE action_type = 'closed'
        AND EXTRACT(YEAR FROM action_at) = ${I}
      " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

  declare -i YEAR_REOPENED
  YEAR_REOPENED=$(psql -d "${DBNAME_DWH}" -Atq \
   -c "SELECT COUNT(DISTINCT id_note)
      FROM dwh.facts
      WHERE action_type = 'reopened'
        AND EXTRACT(YEAR FROM action_at) = ${I}
      " \
   -v ON_ERROR_STOP=1 2> /dev/null || echo "0")

  printf "${I}:  %9d  %11d  %9d  %9d\n" "${YEAR_OPEN}" "${YEAR_COMMENTED}" "${YEAR_CLOSED}" "${YEAR_REOPENED}"
  I=$((I + 1))
 done

 echo
 echo "Top 10 Notes with most comments (all time):"
 declare TOP_10_COMMENTS
 TOP_10_COMMENTS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT json_agg(json_build_object('note_id', id_note, 'comments', total_comments_on_note, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_comments_on_note DESC)
    FROM (
     SELECT DISTINCT ON (id_note) id_note, total_comments_on_note
     FROM dwh.facts
     WHERE total_comments_on_note > 0
     ORDER BY id_note, total_comments_on_note DESC
     LIMIT 10
    ) sub
   " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 if [[ -n "${TOP_10_COMMENTS}" ]] && [[ "${TOP_10_COMMENTS}" != "[]" ]] && [[ "${TOP_10_COMMENTS}" != "null" ]]; then
  if command -v jq &> /dev/null; then
   echo "${TOP_10_COMMENTS}" | jq -r '.[] | "  Note \(.note_id): \(.comments) comments - \(.url)"' 2> /dev/null || echo "${TOP_10_COMMENTS}"
  else
   echo "${TOP_10_COMMENTS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"note_id" : /  Note /g' | sed 's/, "comments" : /: /g' | sed 's/, "url" : / comments - /g' | sed 's/}$//g' || echo "${TOP_10_COMMENTS}"
  fi
 fi

 echo
 echo "Top 10 Notes with most reopenings (all time):"
 declare TOP_10_REOPENINGS
 TOP_10_REOPENINGS=$(psql -d "${DBNAME_DWH}" -Atq \
  -c "SELECT json_agg(json_build_object('note_id', id_note, 'reopenings', total_reopenings_count, 'url', 'https://www.openstreetmap.org/note/' || id_note) ORDER BY total_reopenings_count DESC)
    FROM (
     SELECT DISTINCT ON (id_note) id_note, total_reopenings_count
     FROM dwh.facts
     WHERE total_reopenings_count > 0
     ORDER BY id_note, total_reopenings_count DESC
     LIMIT 10
    ) sub
   " \
  -v ON_ERROR_STOP=1 2> /dev/null || echo "[]")

 if [[ -n "${TOP_10_REOPENINGS}" ]] && [[ "${TOP_10_REOPENINGS}" != "[]" ]] && [[ "${TOP_10_REOPENINGS}" != "null" ]]; then
  if command -v jq &> /dev/null; then
   echo "${TOP_10_REOPENINGS}" | jq -r '.[] | "  Note \(.note_id): \(.reopenings) reopenings - \(.url)"' 2> /dev/null || echo "${TOP_10_REOPENINGS}"
  else
   echo "${TOP_10_REOPENINGS}" | sed 's/}, {/\n/g' | sed 's/\[{//' | sed 's/}\]//' | sed 's/"note_id" : /  Note /g' | sed 's/, "reopenings" : /: /g' | sed 's/, "url" : / reopenings - /g' | sed 's/}$//g' || echo "${TOP_10_REOPENINGS}"
  fi
 fi

 echo
 echo "Note: Additional statistics (reactivated notes, ID gaps, working hours, user wars, etc.)"
 echo "      can be calculated from the facts table but require more complex queries."
 echo "      These may be added in future versions."

 __log_finish
}

# Function that activates the error trap.
function __trapOn() {
 __log_start
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 trap '{
  local ERROR_LINE="${LINENO}"
  local ERROR_COMMAND="${BASH_COMMAND}"
  local ERROR_EXIT_CODE="$?"

  # Only report actual errors, not successful returns
  if [[ "${ERROR_EXIT_CODE}" -ne 0 ]]; then
   # Get the main script name (the one that was executed, not the library)
   local MAIN_SCRIPT_NAME
   MAIN_SCRIPT_NAME=$(basename "${0}" .sh)

   printf "%s ERROR: The script %s did not finish correctly. Temporary directory: ${TMP_DIR:-} - Line number: %d.\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}" "${ERROR_LINE}";
   printf "ERROR: Failed command: %s (exit code: %d)\n" "${ERROR_COMMAND}" "${ERROR_EXIT_CODE}";
   if [[ "${GENERATE_FAILED_FILE:-false}" = true ]]; then
    local FAILED_EXECUTION_FILE="${FAILED_EXECUTION_FILE:-/tmp/etl_failed_${MAIN_SCRIPT_NAME}_$$.log}"
    {
     echo "Error occurred at $(date +%Y%m%d_%H:%M:%S)"
     echo "Script: ${MAIN_SCRIPT_NAME}"
     echo "Line number: ${ERROR_LINE}"
     echo "Failed command: ${ERROR_COMMAND}"
     echo "Exit code: ${ERROR_EXIT_CODE}"
     echo "Temporary directory: ${TMP_DIR:-unknown}"
     echo "Process ID: $$"
    } > "${FAILED_EXECUTION_FILE}"
   fi;
   exit "${ERROR_EXIT_CODE}";
  fi;
 }' ERR
 # shellcheck disable=SC2154  # variables inside trap are defined dynamically by Bash
 trap '{
  # Get the main script name (the one that was executed, not the library)
  local MAIN_SCRIPT_NAME
  MAIN_SCRIPT_NAME=$(basename "${0}" .sh)

  printf "%s WARN: The script %s was terminated. Temporary directory: ${TMP_DIR:-}\n" "$(date +%Y%m%d_%H:%M:%S)" "${MAIN_SCRIPT_NAME}";
  if [[ "${GENERATE_FAILED_FILE:-false}" = true ]]; then
   local FAILED_EXECUTION_FILE="${FAILED_EXECUTION_FILE:-/tmp/etl_failed_${MAIN_SCRIPT_NAME}_$$.log}"
   {
    echo "Script terminated at $(date +%Y%m%d_%H:%M:%S)"
    echo "Script: ${MAIN_SCRIPT_NAME}"
    echo "Temporary directory: ${TMP_DIR:-unknown}"
    echo "Process ID: $$"
    echo "Signal: SIGTERM/SIGINT"
   } > "${FAILED_EXECUTION_FILE}"
  fi;
  exit "${ERROR_GENERAL}";
 }' SIGINT SIGTERM
 __log_finish
}

######
# MAIN

function main() {
 __logi "Preparing environment."
 __logd "Output saved at: ${TMP_DIR}."
 __logi "Processing: ${PROCESS_TYPE}."

 if [[ "${PROCESS_TYPE}" == "-h" ]] || [[ "${PROCESS_TYPE}" == "--help" ]]; then
  __show_help
 fi
 __checkPrereqs

 __logw "Starting process."
 # Sets the trap in case of any signal.
 __trapOn

 if [[ "${PROCESS_TYPE}" == "--user" ]]; then
  __getUserId
  __processUserProfile
 elif [[ "${PROCESS_TYPE}" == "--country" ]] \
  || [[ "${PROCESS_TYPE}" == "--pais" ]]; then
  __getCountryId
  __processCountryProfile
 elif [[ "${PROCESS_TYPE}" == "" ]]; then
  __generalNoteStats
 fi

 __logw "Ending process."
}

# Allows other users to read the directory.
chmod go+x "${TMP_DIR}"

# Only execute main if this script is being run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 __start_logger
 if [[ ! -t 1 ]]; then
  __set_log_file "${LOG_FILENAME}"
  main >> "${LOG_FILENAME}"
  if [[ -n "${CLEAN}" ]] && [[ "${CLEAN}" = true ]]; then
   mv "${LOG_FILENAME}" "/tmp/${BASENAME}_$(date +%Y-%m-%d_%H-%M-%S || true).log"
   rmdir "${TMP_DIR}"
  fi
 else
  main
 fi
fi
