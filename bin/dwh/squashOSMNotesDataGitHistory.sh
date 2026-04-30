#!/bin/bash

# Collapse OSM-Notes-Data Git history to a single commit (orphan branch),
# keeping only the current working tree. Intended for data repos where past
# revisions of large JSON files do not matter but .git object growth does.
#
# WARNING: This runs `git push --force-with-lease origin <branch>`.
# Everyone with a clone must reset (e.g. git fetch origin && git reset --hard origin/main).
# Branch protection rules on GitHub may block the push.
#
# Usage:
#   ./bin/dwh/squashOSMNotesDataGitHistory.sh --dry-run
#   ./bin/dwh/squashOSMNotesDataGitHistory.sh --yes
#
# Cron: see cron examples next to OSM_NOTES_DATA_SQUASH_AFTER_EXPORT in
# bin/dwh/Environment_Variables.md
#
# Environment:
#   DATA_REPO_BRANCH: branch to replace (default: main)
#
# Author: Andres Gomez (AngocA)
# Version: 2026-04-30

set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." &> /dev/null && pwd)"
readonly SCRIPT_DIR

if [[ -f "${SCRIPT_DIR}/etc/properties.sh" ]]; then
 # shellcheck disable=SC1091
 source "${SCRIPT_DIR}/etc/properties.sh"
fi

if [[ -d "${HOME}/OSM-Notes-Data" ]]; then
 DATA_REPO_DIR="${HOME}/OSM-Notes-Data"
elif [[ -d "${HOME}/github/OSM-Notes-Data" ]]; then
 DATA_REPO_DIR="${HOME}/github/OSM-Notes-Data"
else
 DATA_REPO_DIR="${HOME}/OSM-Notes-Data"
fi
readonly DATA_REPO_DIR

DATA_REPO_BRANCH="${DATA_REPO_BRANCH:-main}"
readonly DATA_REPO_BRANCH

DRY_RUN=false
CONFIRMED=false
for arg in "${@}"; do
 case "${arg}" in
 --dry-run)
  DRY_RUN=true
  ;;
 --yes)
  CONFIRMED=true
  ;;
 *)
  echo "Unknown option: ${arg}" >&2
  echo "Usage: $0 [--dry-run | --yes]" >&2
  exit 1
  ;;
 esac
done

if [[ "${DRY_RUN}" == "true" ]] && [[ "${CONFIRMED}" == "true" ]]; then
 echo "Use either --dry-run or --yes, not both." >&2
 exit 1
fi

if [[ "${DRY_RUN}" == "false" ]] && [[ "${CONFIRMED}" == "false" ]]; then
 echo "Refusing to rewrite history without --yes (or pass --dry-run to preview)." >&2
 exit 1
fi

if [[ ! -d "${DATA_REPO_DIR}/.git" ]]; then
 echo "DATA repo not found or not a git clone: ${DATA_REPO_DIR}" >&2
 exit 1
fi

squash_repo() {
 local tmp_branch="_orphan_osm_notes_data_squash_"
 cd "${DATA_REPO_DIR}"

 if ! git rev-parse --abbrev-ref HEAD &> /dev/null; then
  echo "Not a usable git repository: ${DATA_REPO_DIR}" >&2
  return 1
 fi

 git fetch origin "${DATA_REPO_BRANCH}" 2> /dev/null || true

 git checkout "${DATA_REPO_BRANCH}" 2> /dev/null || {
  echo "Cannot checkout branch ${DATA_REPO_BRANCH}." >&2
  return 1
 }

 if [[ -f "${DATA_REPO_DIR}/.git/MERGE_HEAD" ]]; then
  echo "Merge in progress; resolve or abort before squashing." >&2
  return 1
 fi

 if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] Branch: ${DATA_REPO_BRANCH}"
  echo "[dry-run] Would create an orphan branch, git add -A, single commit,"
  echo "[dry-run] replace local ${DATA_REPO_BRANCH}, git push --force-with-lease origin ${DATA_REPO_BRANCH}."
  echo "[dry-run] Current .git on-disk size:"
  du -sh .git 2> /dev/null || echo "(unable to measure)"
  return 0
 fi

 # Orphan branch: drop all parent commits; keep filesystem as-is then re-record.
 git branch -D "${tmp_branch}" 2> /dev/null || true
 git checkout --orphan "${tmp_branch}"

 git add -A

 if git diff --cached --quiet && [[ -z "$(git ls-files)" ]]; then
  echo "Nothing to commit; aborting." >&2
  git checkout "${DATA_REPO_BRANCH}" 2> /dev/null || true
  git branch -D "${tmp_branch}" 2> /dev/null || true
  return 1
 fi

 local squash_ts squash_msg
 squash_ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
 squash_msg="Squash snapshot: single commit for current data/schema tree (${squash_ts})"

 git commit -m "${squash_msg}"

 git branch -D "${DATA_REPO_BRANCH}" 2> /dev/null || true
 git branch -m "${DATA_REPO_BRANCH}"

 if ! git push --force-with-lease origin "${DATA_REPO_BRANCH}"; then
  echo "Force-push failed (branch protection, auth, or remote moved). Recover with git reflog." >&2
  return 1
 fi

 echo "History squashed on origin/${DATA_REPO_BRANCH}. Inform all clone owners to reset to origin."
 return 0
}

squash_repo
