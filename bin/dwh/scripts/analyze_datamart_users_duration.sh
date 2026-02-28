#!/bin/bash
#
# Analyzes recent datamartUsers execution times from ETL logs only.
# Duration is taken from ETL log line "datamartUsers took N seconds" (written by ETL.sh).
# Does not depend on bash_logger "Took: 0h:Xm:Ys" (that line is only at DEBUG/INFO level).
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

# 2) Recent datamartUsers runs (from log filenames only; duration is from ETL above)
#    Does not depend on logger "Took: 0h:Xm:Ys" (that line is only at DEBUG/INFO level).
echo "--- Recent datamartUsers runs (${LOG_BASE_DIR}/datamartUsers_*.log) ---"
found_dm=0
datamart_logs_sorted() {
 if command -v find >/dev/null 2>&1 && find "${LOG_BASE_DIR}" -maxdepth 1 -name 'datamartUsers_*.log' -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -25 | cut -d' ' -f2-; then
  : # used
 else
  ls -1t "${LOG_BASE_DIR}"/datamartUsers_*.log 2>/dev/null | head -25 || true
 fi
}
while IFS= read -r log; do
 [[ -f "${log}" ]] || continue
 base=$(basename "${log}" .log)
 # Filename is datamartUsers_YYYY-MM-DD_HH-MM-SS.log; end time is in the name
 if [[ "${base}" =~ datamartUsers_([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
  ts="${BASH_REMATCH[1]//_/ }"
  echo "  ${base}.log (finished: ${ts}), $(wc -c < "${log}" | tr -d ' ') bytes"
  found_dm=1
 else
  echo "  ${base}.log, $(wc -c < "${log}" | tr -d ' ') bytes"
  found_dm=1
 fi
done < <(datamart_logs_sorted)
for dir in "${LOG_BASE_DIR}"/datamartUsers_*/; do
 [[ -d "${dir}" ]] || continue
 log="${dir}datamartUsers.log"
 if [[ -f "${log}" ]]; then
  echo "  ${dir}datamartUsers.log (in progress?), $(wc -c < "${log}" | tr -d ' ') bytes"
  found_dm=1
 fi
done
if [[ ${found_dm} -eq 0 ]]; then
 echo "  (No datamartUsers log files found)"
 echo "  Tip: Run as the same user that runs datamartUsers, or set LOG_BASE_DIR if logs are elsewhere."
fi
echo "  (Duration is taken from ETL logs above, not from logger 'Took:' lines.)"
echo ""

echo "--- Summary ---"
if [[ ${found_etl} -eq 0 ]]; then
 echo "No duration data found in ETL logs. Check:"
 echo "  - Run this script as the same user that runs ETL (e.g. notes/angoca)."
 echo "  - If logs are elsewhere: LOG_BASE_DIR=/path/to/logs $0"
 echo "  - List logs: ls -la ${LOG_BASE_DIR}/ETL_* ${LOG_BASE_DIR}/datamartUsers_* 2>/dev/null || true"
 echo ""
fi
echo "If times are consistently under ${CRON_WINDOW_MINUTES} minutes, 4000 users/cycle is fine."
echo "If often over, consider lowering MAX_USERS_PER_CYCLE (e.g. 2000–3000) or increasing cron interval."
