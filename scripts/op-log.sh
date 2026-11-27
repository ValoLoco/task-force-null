#!/usr/bin/env bash
# Tee an operator command into missions/<slug>/logs/<role>.log with UTC timestamps.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VALID_ROLES=(command lead recon builder medic-qa comms)

usage() {
  cat <<EOF
Usage: $0 [--repo-root PATH] <mission-slug> <role> -- <command...>

Roles: ${VALID_ROLES[*]}
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage ;;
    *) break ;;
  esac
done

[[ $# -ge 3 ]] || usage
SLUG="$1"
ROLE="$2"
shift 2
[[ "$1" == "--" ]] || usage
shift
[[ $# -gt 0 ]] || usage

role_ok=0
for r in "${VALID_ROLES[@]}"; do
  [[ "$ROLE" == "$r" ]] && { role_ok=1; break; }
done
[[ "$role_ok" -eq 1 ]] || { echo "op-log: invalid role '${ROLE}'" >&2; usage; }

LOG_DIR="${REPO_ROOT}/missions/${SLUG}/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/${ROLE}.log"

stamp_tee() {
  local log="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$line" | tee -a "$log"
  done
}

set -o pipefail
"$@" 2>&1 | stamp_tee "$LOG_FILE"
exit "${PIPESTATUS[0]}"