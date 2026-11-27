#!/usr/bin/env bash
# Idempotent squad deployment runner: validate brain, profiles, active mission.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REPO_ROOT

log() { printf '[start] %s\n' "$*"; }
fail() { printf '[start] error: %s\n' "$*" >&2; exit 1; }

require_file() {
  local f="$1"
  [[ -f "$f" ]] || fail "missing required file: $f"
}

require_dir() {
  local d="$1"
  [[ -d "$d" ]] || fail "missing required directory: $d"
}

validate_layout() {
  require_dir "${REPO_ROOT}/profiles"
  require_dir "${REPO_ROOT}/brain"
  require_dir "${REPO_ROOT}/missions"
  require_dir "${REPO_ROOT}/scripts"
  for p in command lead recon builder medic-qa comms; do
    require_file "${REPO_ROOT}/profiles/${p}.md"
  done
  require_file "${REPO_ROOT}/brain/doctrine.md"
  require_file "${REPO_ROOT}/brain/index.md"
  require_file "${REPO_ROOT}/brain/aar-log.md"
}

resolve_mission() {
  local slug="${MISSION_SLUG:-}"
  if [[ -n "$slug" ]]; then
    echo "$slug"
    return
  fi
  local envfile active=""
  while IFS= read -r envfile; do
    if grep -q '^ACTIVE=1' "$envfile" 2>/dev/null; then
      active="$(dirname "$envfile")"
      active="${active##*/}"
      echo "$active"
      return
    fi
  done < <(find "${REPO_ROOT}/missions" -mindepth 2 -maxdepth 2 -name 'squad.env' 2>/dev/null | sort)
  fail "no active mission; set MISSION_SLUG or set ACTIVE=1 in one missions/*/squad.env"
}

validate_mission() {
  local slug="$1"
  local mdir="${REPO_ROOT}/missions/${slug}"
  [[ -d "$mdir" ]] || fail "mission directory not found: $mdir"
  require_file "${mdir}/mission.md"
  require_file "${mdir}/intel.md"
  require_file "${mdir}/board.md"
  require_file "${mdir}/squad.env"
  if ! grep -q '^ACTIVE=1' "${mdir}/squad.env"; then
    log "warning: squad.env ACTIVE is not 1 for ${slug}"
  fi
  export MISSION_SLUG="$slug"
  local root_before="$REPO_ROOT"
  # shellcheck source=/dev/null
  set -a
  # shellcheck disable=SC1090
  source "${mdir}/squad.env" 2>/dev/null || true
  set +a
  if [[ -z "${REPO_ROOT:-}" ]]; then
    REPO_ROOT="$root_before"
    export REPO_ROOT
  fi
}

main() {
  validate_layout
  slug="$(resolve_mission)"
  validate_mission "$slug"
  log "repo=${REPO_ROOT}"
  log "mission=${slug}"
  log "profiles=$(ls -1 "${REPO_ROOT}/profiles" | wc -l)"
  log "ready"
  # Optional: emit router smoke when RUN_ROUTER_SMOKE=1
  if [[ "${RUN_ROUTER_SMOKE:-0}" == "1" ]]; then
    python3 "${REPO_ROOT}/scripts/router.py" "plan and assign tasks" || fail "router smoke failed"
  fi
  exit 0
}

main "$@"