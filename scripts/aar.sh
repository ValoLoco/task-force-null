#!/usr/bin/env bash
# Append timestamped 3-line AAR to brain/aar-log.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${REPO_ROOT}/brain/aar-log.md"
MISSION_SLUG="${MISSION_SLUG:-unknown}"

usage() {
  echo "Usage: $0 --outcome TEXT --friction TEXT --fix TEXT"
  echo "   or: $0 \"outcome\" \"friction\" \"fix\""
  exit 1
}

OUTCOME=""
FRICTION=""
FIX=""

if [[ $# -eq 3 && "$1" != --* ]]; then
  OUTCOME="$1"
  FRICTION="$2"
  FIX="$3"
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --outcome) OUTCOME="$2"; shift 2 ;;
      --friction) FRICTION="$2"; shift 2 ;;
      --fix) FIX="$2"; shift 2 ;;
      --mission) MISSION_SLUG="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
fi

[[ -n "$OUTCOME" && -n "$FRICTION" && -n "$FIX" ]] || usage
[[ -f "$LOG" ]] || { echo "error: missing $LOG" >&2; exit 1; }

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
  echo ""
  echo "## ${TS} | mission:${MISSION_SLUG}"
  echo "- Outcome: ${OUTCOME}"
  echo "- Friction: ${FRICTION}"
  echo "- Fix: ${FIX}"
} >> "$LOG"

echo "AAR appended to ${LOG}"