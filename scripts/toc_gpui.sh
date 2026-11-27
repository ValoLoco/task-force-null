#!/usr/bin/env bash
# Launch optional native GPUI TOC (requires Rust/Cargo for build).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CRATE_DIR="${REPO_ROOT}/toc-gpui"
BIN_NAME="tfn-toc-gpui"
MISSION=""
SSE_URL=""
REPO_OVERRIDE=""

usage() {
  cat <<EOF
Usage: $0 [options] [mission-slug]

Options:
  --repo-root PATH   Task Force Null repo root
  --url URL          SSE mode: web TOC base URL (http://127.0.0.1:<port>)
  --mission SLUG     Preferred mission header slug
  -h, --help         Show help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --url) SSE_URL="${2:-}"; shift 2 ;;
    --mission) MISSION="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    --*) echo "unknown arg: $1" >&2; usage ;;
    *) MISSION="$1"; shift ;;
  esac
done

if [[ -n "$REPO_OVERRIDE" ]]; then
  REPO_ROOT="$(cd "$REPO_OVERRIDE" && pwd)"
  CRATE_DIR="${REPO_ROOT}/toc-gpui"
fi

find_binary() {
  local release="${CRATE_DIR}/target/release/${BIN_NAME}"
  local debug="${CRATE_DIR}/target/debug/${BIN_NAME}"
  if [[ -x "$release" ]]; then
    echo "$release"
    return 0
  fi
  if [[ -x "$debug" ]]; then
    echo "$debug"
    return 0
  fi
  return 1
}

if ! command -v cargo >/dev/null 2>&1; then
  cat <<EOF >&2
toc-gpui: Rust/Cargo is not installed.

Install Rust from https://rustup.rs/ then run:
  cd toc-gpui && cargo build --release --features desktop

Or use the zero-dependency dashboards:
  ./scripts/toc.sh
  ./scripts/toc.sh --web
EOF
  exit 1
fi

BIN="$(find_binary || true)"
if [[ -z "$BIN" ]]; then
  echo "toc-gpui: building ${BIN_NAME} (first run may take several minutes)..." >&2
  export RUSTFLAGS="${RUSTFLAGS:-} ${TFN_TOC_GPUI_RUSTFLAGS:-}"
  (cd "$CRATE_DIR" && cargo build --release --features desktop)
  BIN="$(find_binary || true)"
fi

if [[ -z "$BIN" ]]; then
  echo "toc-gpui: build failed or binary missing under toc-gpui/target/" >&2
  exit 1
fi

args=(--repo-root "$REPO_ROOT")
[[ -n "$SSE_URL" ]] && args+=(--url "$SSE_URL")
[[ -n "$MISSION" ]] && args+=(--mission "$MISSION")

exec "$BIN" "${args[@]}"