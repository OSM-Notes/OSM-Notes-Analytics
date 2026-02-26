#!/bin/bash
#
# Analyzes recent datamartUsers execution times from ETL and datamartUsers logs.
# Use to check if MAX_USERS_PER_CYCLE (e.g. 4000) fits within the cron window (e.g. 15 min).
#
# Run on the server where ETL runs (e.g. via SSH):
#   ssh angoca@192.168.0.7 'bash -s' < bin/dwh/scripts/analyze_datamart_users_duration.sh
# Or copy and run directly on the server:
#   ./bin/dwh/scripts/analyze_datamart_users_duration.sh
#
# Author: Andres Gomez (AngocA)

set -euo pipefail

CRON_WINDOW_MINUTES="${CRON_WINDOW_MINUTES:-15}"
CRON_WINDOW_SECONDS=$((CRON_WINDOW_MINUTES * 60))

echo "=============================================="
echo "datamartUsers execution time analysis"
echo "Cron window: ${CRON_WINDOW_MINUTES} minutes (${CRON_WINDOW_SECONDS} seconds)"
echo "=============================================="
echo ""

# 1) From ETL logs: "datamartUsers took N seconds" (if present) or ETL_*.log files
echo "--- From ETL logs (/tmp/ETL_*.log or /tmp/ETL_*/ETL.log) ---"
found_etl=0
for log in /tmp/ETL_*.log; do
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
  done < <(grep "datamartUsers took" "${log}" 2> /dev/null)
 fi
done
for dir in /tmp/ETL_*/; do
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
  done < <(grep "datamartUsers took" "${log}" 2> /dev/null)
 fi
done
[[ ${found_etl} -eq 0 ]] && echo "  (No 'datamartUsers took' lines found in ETL logs)"
echo ""

# 2) From datamartUsers logs: "Took: 0h:Xm:Ys" (main duration) and optionally "Processed N users"
echo "--- From datamartUsers logs (/tmp/datamartUsers_*.log or .../datamartUsers.log) ---"
found_dm=0
# Show last 25 log files (most recent first)
for log in $(ls -1t /tmp/datamartUsers_*.log 2> /dev/null | head -25); do
 [[ -f "${log}" ]] || continue
 # Penultimate "Took: 0h:Xm:Ys" is __processNotesUser duration (parallel processing)
 took=$(grep "Took: 0h:" "${log}" 2> /dev/null | tail -2 | head -1 | sed -n 's/.*Took: 0h:\([0-9]*\)m:\([0-9]*\)s.*/\1 \2/p')
 if [[ -n "${took}" ]]; then
  m=$(echo "${took}" | cut -d' ' -f1)
  s=$(echo "${took}" | cut -d' ' -f2)
  total=$((m * 60 + s))
  ok=""
  [[ ${total} -le ${CRON_WINDOW_SECONDS} ]] && ok=" [OK]" || ok=" [OVER ${CRON_WINDOW_MINUTES} min]"
  echo "  $(basename "${log}"): ${m}m ${s}s (${total}s)${ok}"
  found_dm=1
 fi
done
for dir in /tmp/datamartUsers_*/; do
 [[ -d "${dir}" ]] || continue
 log="${dir}datamartUsers.log"
 if [[ -f "${log}" ]]; then
  took=$(grep "Took: 0h:" "${log}" 2> /dev/null | tail -2 | head -1 | sed -n 's/.*Took: 0h:\([0-9]*\)m:\([0-9]*\)s.*/\1 \2/p')
  if [[ -n "${took}" ]]; then
   m=$(echo "${took}" | cut -d' ' -f1)
   s=$(echo "${took}" | cut -d' ' -f2)
   total=$((m * 60 + s))
   ok=""
   [[ ${total} -le ${CRON_WINDOW_SECONDS} ]] && ok=" [OK]" || ok=" [OVER]"
   echo "  ${dir}: ${m}m ${s}s (${total}s)${ok}"
   found_dm=1
  fi
 fi
done
[[ ${found_dm} -eq 0 ]] && echo "  (No Took lines found in datamartUsers logs)"
echo ""

echo "--- Summary ---"
echo "If times are consistently under ${CRON_WINDOW_MINUTES} minutes, 4000 users/cycle is fine."
echo "If often over, consider lowering MAX_USERS_PER_CYCLE (e.g. 2000–3000) or increasing cron interval."
