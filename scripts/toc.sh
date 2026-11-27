#!/usr/bin/env bash
# Tactical Operations Center dashboard. Bash plus Python 3 stdlib.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WATCH=0
INTERVAL=30
TOGGLE=0
MUTATE=0
SET_AUTONOMOUS=""
DELEGATION_SET=""
WEB=0
WEB_PORT=""
NO_OPEN=0
GPUI=0
GPUI_URL=""
MISSION_SLUG=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --watch                         Refresh every 30 seconds (clears the screen)
  --interval SECONDS              Watch period in seconds (use with --watch)
  --set-delegation KEY=true|false Set DELEGATE_BLOCKERS and/or DELEGATE_EXTERNAL
                                  Keys: blockers, external (one or both)
  --set-autonomous true|false     Set AUTONOMOUS_MODE in toc-config and active squad.env
  --toggle                        Prompt for blockers, external, and autonomous
  --web                           Localhost real-time web TOC (scripts/toc-web.py)
  --gpui|--native                 Optional native GPUI desktop TOC (requires Rust/Cargo)
  --url URL                       With --gpui: connect to web TOC SSE at URL
  --port N                        Web server port (0 = ephemeral). Env: TFN_TOC_PORT
  --no-open                       Do not open a browser for --web
  --repo-root PATH                Read and write this repo root (tests)

Config: brain/toc-config.md
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --watch) WATCH=1; shift ;;
    --interval)
      INTERVAL="${2:-}"
      shift 2
      ;;
    --set-delegation)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        DELEGATION_SET="${DELEGATION_SET} $1"
        shift
      done
      MUTATE=1
      ;;
    --set-autonomous)
      SET_AUTONOMOUS="${2:-}"
      shift 2
      MUTATE=1
      ;;
    --toggle) TOGGLE=1; MUTATE=1; shift ;;
    --web) WEB=1; shift ;;
    --gpui|--native) GPUI=1; shift ;;
    --url)
      GPUI_URL="${2:-}"
      shift 2
      ;;
    --port)
      WEB_PORT="${2:-}"
      shift 2
      ;;
    --no-open) NO_OPEN=1; shift ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *)
      if [[ "$1" == --* ]]; then
        echo "unknown arg: $1" >&2
        usage
      fi
      MISSION_SLUG="$1"
      shift
      ;;
  esac
done

if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  echo "interval must be a positive integer" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "toc: python3 is required" >&2
  exit 1
fi

if [[ "$GPUI" -eq 1 && "$WEB" -eq 1 ]]; then
  echo "toc: use either --web or --gpui, not both" >&2
  exit 2
fi

if [[ "$GPUI" -eq 1 ]]; then
  GPUI_ARGS=(--repo-root "$REPO_ROOT")
  [[ -n "$GPUI_URL" ]] && GPUI_ARGS+=(--url "$GPUI_URL")
  [[ -n "$MISSION_SLUG" ]] && GPUI_ARGS+=(--mission "$MISSION_SLUG")
  exec "${SCRIPT_DIR}/toc_gpui.sh" "${GPUI_ARGS[@]}"
fi

if [[ "$WEB" -eq 1 ]]; then
  WEB_ARGS=(--repo-root "$REPO_ROOT")
  if [[ -n "$WEB_PORT" ]]; then
    WEB_ARGS+=(--port "$WEB_PORT")
  elif [[ -n "${TFN_TOC_PORT:-}" ]]; then
    WEB_ARGS+=(--port "$TFN_TOC_PORT")
  fi
  if [[ "$NO_OPEN" -eq 1 ]]; then
    WEB_ARGS+=(--no-open)
  fi
  exec python3 "${SCRIPT_DIR}/toc-web.py" "${WEB_ARGS[@]}"
fi

render() {
  local mutate="$1"
  local del="${DELEGATION_SET# }"
  local args=(render --repo-root "$REPO_ROOT" --watch-interval "$INTERVAL")
  [[ "$mutate" == "1" ]] && args+=(--mutate)
  [[ "$TOGGLE" == "1" ]] && args+=(--toggle)
  [[ "$WATCH" == "1" ]] && args+=(--watching)
  [[ -n "$del" ]] && args+=(--delegation "$del")
  [[ -n "$SET_AUTONOMOUS" ]] && args+=(--autonomous "$SET_AUTONOMOUS")
  python3 "${SCRIPT_DIR}/toc_lib.py" "${args[@]}"
}

if [[ "$WATCH" -eq 1 ]]; then
  render "$MUTATE"
  TOGGLE=0
  MUTATE=0
  DELEGATION_SET=""
  SET_AUTONOMOUS=""
  trap 'exit 0' INT TERM
  while true; do
    sleep "$INTERVAL"
    if command -v clear >/dev/null 2>&1; then
      clear
    else
      printf '\033[2J\033[H'
    fi
    render 0
  done
else
  render "$MUTATE"
fi