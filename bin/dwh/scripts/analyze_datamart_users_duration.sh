#!/bin/bash
#
# Analyzes recent datamartUsers execution times.
# Duration is read from: ETL log "datamartUsers took N seconds", or from each datamartUsers
# log file ("datamartUsers took N seconds" / "Parallel user processing took N seconds" /
# "TIME: ... took N seconds"). The "Recent datamartUsers runs" section shows duration per cycle.
# Use to check if MAX_USERS_PER_CYCLE (e.g. 4000) fits within the cron window (e.g. 15 min).
#
# Run on the server where ETL runs (e.g. via SSH):
#   ssh angoca@192.168.0.7 'bash -s' < bin/dwh/scripts/analyze_datamart_users_duration.sh
# Or copy and run directly on the server:
#   ./bin/dwh/scripts/analyze_datamart_users_duration.sh
#
# Optional: LOG_BASE_DIR overrides where to look for logs (default: /tmp).
#   LOG_BASE_DIR=/var/log/osm-notes ./bin/dwh/scripts/analyze_datamart_users_duration.sh
# Run as the same user that runs ETL/datamartUsers so log files are readable.
#
# Author: Andres Gomez (AngocA)

set -euo pipefail

CRON_WINDOW_MINUTES="${CRON_WINDOW_MINUTES:-15}"
CRON_WINDOW_SECONDS=$((CRON_WINDOW_MINUTES * 60))
# Base directory for ETL and datamartUsers logs (default /tmp; override if logs are elsewhere)
LOG_BASE_DIR="${LOG_BASE_DIR:-/tmp}"

# Output duration string for a log file: "Ns (Nm Ns) [OK]" or "[OVER]" or empty if not found.
# Looks for: "datamartUsers took N seconds", "Parallel user processing took N seconds", or "TIME: ... took N seconds".
get_duration_from_log() {
 local log="$1"
 local line
 line=$(grep -E "datamartUsers took [0-9]+ seconds|Parallel user processing took [0-9]+ seconds|TIME:.*took [0-9]+ seconds" "${log}" 2> /dev/null | tail -1 || true)
 if [[ -z "${line}" ]]; then
  return 0
 fi
 local secs=""
 if [[ "${line}" =~ datamartUsers\ took\ ([0-9]+)\ seconds ]]; then
  secs="${BASH_REMATCH[1]}"
 elif [[ "${line}" =~ Parallel\ user\ processing\ took\ ([0-9]+)\ seconds ]]; then
  secs="${BASH_REMATCH[1]}"
 elif [[ "${line}" =~ took\ ([0-9]+)\ seconds ]]; then
  secs="${BASH_REMATCH[1]}"
 fi
 if [[ -z "${secs}" ]]; then
  return 0
 fi
 local mins=$((secs / 60))
 local rem=$((secs % 60))
 local ok=""
 [[ ${secs} -le ${CRON_WINDOW_SECONDS} ]] && ok=" [OK <= ${CRON_WINDOW_MINUTES} min]" || ok=" [OVER ${CRON_WINDOW_MINUTES} min]"
 echo "${secs}s (${mins}m ${rem}s)${ok}"
}

echo "=============================================="
echo "datamartUsers execution time analysis"
echo "Cron window: ${CRON_WINDOW_MINUTES} minutes (${CRON_WINDOW_SECONDS} seconds)"
echo "Log search path: ${LOG_BASE_DIR}"
echo "=============================================="
echo ""

# 1) From ETL logs: "datamartUsers took N seconds" (if present) or ETL_*.log files
echo "--- From ETL logs (${LOG_BASE_DIR}/ETL_*.log or ${LOG_BASE_DIR}/ETL_*/ETL.log) ---"
found_etl=0
for log in "${LOG_BASE_DIR}"/ETL_*.log; do
 [[ -f "${log}" ]] || continue
 if grep -q "datamartUsers took" "${log}" 2> /dev/null; then
  found_etl=1
  while IFS= read -r line; do
   if [[ "${line}" =~ datamartUsers\ took\ ([0-9]+)\ seconds ]]; then
    secs="${BASH_REMATCH[1]}"
    mins=$((secs / 60))
    rem=$((secs % 60))
    ok=""
    [[ ${secs} -le ${CRON_WINDOW_SECONDS} ]] && ok=" [OK <= ${CRON_WINDOW_MINUTES} min]" || ok=" [OVER ${CRON_WINDOW_MINUTES} min]"
    echo "  ${log}: datamartUsers took ${secs}s (${mins}m ${rem}s)${ok}"
   fi
  done < <(grep "datamartUsers took" "${log}" 2> /dev/null || true)
 fi
done
for dir in "${LOG_BASE_DIR}"/ETL_*/; do
 [[ -d "${dir}" ]] || continue
 log="${dir}ETL.log"
 if [[ -f "${log}" ]] && grep -q "datamartUsers took" "${log}" 2> /dev/null; then
  found_etl=1
  while IFS= read -r line; do
   if [[ "${line}" =~ datamartUsers\ took\ ([0-9]+)\ seconds ]]; then
    secs="${BASH_REMATCH[1]}"
    mins=$((secs / 60))
    rem=$((secs % 60))
    ok=""
    [[ ${secs} -le ${CRON_WINDOW_SECONDS} ]] && ok=" [OK]" || ok=" [OVER]"
    echo "  ${dir}: ${secs}s (${mins}m ${rem}s)${ok}"
   fi
  done < <(grep "datamartUsers took" "${log}" 2> /dev/null || true)
 fi
done
if [[ ${found_etl} -eq 0 ]]; then
 echo "  (No 'datamartUsers took' lines found in ETL logs)"
 echo "  Tip: Run as the same user that runs ETL, or set LOG_BASE_DIR if logs are elsewhere."
fi
echo ""

# 2) From datamartUsers logs: "datamartUsers took N seconds" or "Parallel user processing took N seconds"
#    (written by datamartUsers.sh; also matches "TIME: ... took N seconds" from __logi)
echo "--- From datamartUsers logs (duration when present) ---"
found_dm_duration=0
for log in "${LOG_BASE_DIR}"/datamartUsers_*.log; do
 [[ -f "${log}" ]] || continue
 duration_str=$(get_duration_from_log "${log}") || true
 if [[ -n "${duration_str}" ]]; then
  echo "  $(basename "${log}"): ${duration_str}"
  found_dm_duration=1
 fi
done
for dir in "${LOG_BASE_DIR}"/datamartUsers_*/; do
 [[ -d "${dir}" ]] || continue
 log="${dir}datamartUsers.log"
 [[ -f "${log}" ]] || continue
 duration_str=$(get_duration_from_log "${log}") || true
 if [[ -n "${duration_str}" ]]; then
  echo "  ${dir}datamartUsers.log: ${duration_str} (in progress?)"
  found_dm_duration=1
 fi
done
if [[ ${found_dm_duration} -eq 0 ]]; then
 echo "  (No 'datamartUsers took' or 'Parallel user processing took' lines in datamartUsers logs)"
fi
echo ""

# 3) Recent datamartUsers runs with duration per cycle (from log filenames + duration inside each log)
echo "--- Recent datamartUsers runs (${LOG_BASE_DIR}/datamartUsers_*.log) ---"
found_dm=0
datamart_logs_sorted() {
 if command -v find > /dev/null 2>&1 && find "${LOG_BASE_DIR}" -maxdepth 1 -name 'datamartUsers_*.log' -type f -printf '%T@ %p\n' 2> /dev/null | sort -rn | head -25 | cut -d' ' -f2-; then
  : # used
 else
  ls -1t "${LOG_BASE_DIR}"/datamartUsers_*.log 2> /dev/null | head -25 || true
 fi
}
while IFS= read -r log; do
 [[ -f "${log}" ]] || continue
 base=$(basename "${log}" .log)
 bytes=$(wc -c < "${log}" | tr -d ' ')
 duration_str=""
 duration_str=$(get_duration_from_log "${log}") || true
 # Filename is datamartUsers_YYYY-MM-DD_HH-MM-SS.log; end time is in the name
 if [[ "${base}" =~ datamartUsers_([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
  ts="${BASH_REMATCH[1]//_/ }"
  if [[ -n "${duration_str}" ]]; then
   echo "  ${base}.log (finished: ${ts}), ${duration_str}, ${bytes} bytes"
  else
   echo "  ${base}.log (finished: ${ts}), ${bytes} bytes (no duration line in log)"
  fi
  found_dm=1
 else
  if [[ -n "${duration_str}" ]]; then
   echo "  ${base}.log, ${duration_str}, ${bytes} bytes"
  else
   echo "  ${base}.log, ${bytes} bytes"
  fi
  found_dm=1
 fi
done < <(datamart_logs_sorted)
for dir in "${LOG_BASE_DIR}"/datamartUsers_*/; do
 [[ -d "${dir}" ]] || continue
 log="${dir}datamartUsers.log"
 if [[ -f "${log}" ]]; then
  bytes=$(wc -c < "${log}" | tr -d ' ')
  duration_str=$(get_duration_from_log "${log}") || true
  if [[ -n "${duration_str}" ]]; then
   echo "  ${dir}datamartUsers.log (in progress?), ${duration_str}, ${bytes} bytes"
  else
   echo "  ${dir}datamartUsers.log (in progress?), ${bytes} bytes"
  fi
  found_dm=1
 fi
done
if [[ ${found_dm} -eq 0 ]]; then
 echo "  (No datamartUsers log files found)"
 echo "  Tip: Run as the same user that runs datamartUsers, or set LOG_BASE_DIR if logs are elsewhere."
fi
echo ""

echo "--- Summary ---"
if [[ ${found_etl} -eq 0 ]] && [[ ${found_dm_duration} -eq 0 ]]; then
 echo "No duration data found in ETL or datamartUsers logs. Check:"
 echo "  - Run this script as the same user that runs ETL (e.g. notes/angoca)."
 echo "  - If logs are elsewhere: LOG_BASE_DIR=/path/to/logs $0"
 echo "  - List logs: ls -la ${LOG_BASE_DIR}/ETL_* ${LOG_BASE_DIR}/datamartUsers_* 2>/dev/null || true"
 echo ""
fi
echo "If times are consistently under ${CRON_WINDOW_MINUTES} minutes, 4000 users/cycle is fine."
echo "If often over, consider lowering MAX_USERS_PER_CYCLE (e.g. 2000–3000) or increasing cron interval."
