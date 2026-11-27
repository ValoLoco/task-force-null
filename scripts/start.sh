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

env_is_active() {
  local f="$1" line
  [[ -f "$f" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^ACTIVE=1[[:space:]]*$ ]] && return 0
  done <"$f"
  return 1
}

resolve_mission() {
  local slug="${MISSION_SLUG:-}"
  if [[ -n "$slug" ]]; then
    printf '%s\n' "$slug"
    return
  fi
  local envfile chosen="" count=0 name
  while IFS= read -r envfile; do
    if env_is_active "$envfile"; then
      count=$((count + 1))
      name="$(basename "$(dirname "$envfile")")"
      if [[ -z "$chosen" ]]; then
        chosen="$name"
      fi
    fi
  done < <(find "${REPO_ROOT}/missions" -mindepth 2 -maxdepth 2 -name 'squad.env' 2>/dev/null | sort)
  if [[ "$count" -gt 1 ]]; then
    log "warning: ${count} missions have ACTIVE=1; using ${chosen}. Set MISSION_SLUG to choose."
  fi
  if [[ -z "$chosen" ]]; then
    fail "no active mission; set MISSION_SLUG or set ACTIVE=1 in one missions/*/squad.env"
  fi
  printf '%s\n' "$chosen"
}

validate_mission() {
  local slug="$1"
  local mdir="${REPO_ROOT}/missions/${slug}"
  [[ -d "$mdir" ]] || fail "mission directory not found: $mdir"
  require_file "${mdir}/mission.md"
  require_file "${mdir}/intel.md"
  require_file "${mdir}/board.md"
  require_file "${mdir}/squad.env"
  if ! env_is_active "${mdir}/squad.env"; then
    log "warning: squad.env ACTIVE is not 1 for ${slug}"
  fi
  local root_before="$REPO_ROOT"
  # shellcheck source=/dev/null
  set -a
  # shellcheck disable=SC1090
  source <(tr -d '\r' < "${mdir}/squad.env") 2>/dev/null || true
  set +a
  REPO_ROOT="$root_before"
  export REPO_ROOT
  export MISSION_SLUG="$slug"
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