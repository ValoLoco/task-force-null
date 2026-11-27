#!/usr/bin/env bash
# Sync vendored ECC armory from upstream (no nested .git under armory/ecc/).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARMORY_DIR="${REPO_ROOT}/armory/ecc"
PINNED_FILE="${ARMORY_DIR}/PINNED_SHA"
UPSTREAM_URL="${ECC_UPSTREAM_URL:-https://github.com/affaan-m/ECC.git}"
UPSTREAM_BRANCH="${ECC_UPSTREAM_BRANCH:-}"
ALLOW_OFFLINE=0

usage() {
  echo "Usage: $0 [--allow-offline]"
  echo "Env: ECC_UPSTREAM_URL, ECC_UPSTREAM_BRANCH, SKIP_SYNC_ARMORY=1"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-offline) ALLOW_OFFLINE=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

if [[ "${SKIP_SYNC_ARMORY:-0}" == "1" ]]; then
  echo "sync-armory: skipped (SKIP_SYNC_ARMORY=1)"
  exit 0
fi

current_pinned() {
  if [[ -f "$PINNED_FILE" ]]; then
    tr -d '[:space:]' <"$PINNED_FILE"
  else
    echo "unknown"
  fi
}

sync_from_upstream() {
  local tmp clone_sha
  tmp="$(mktemp -d)"
  if [[ -n "$UPSTREAM_BRANCH" ]]; then
    if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" "$UPSTREAM_URL" "$tmp/ecc" 2>/dev/null; then
      rm -rf "$tmp"
      return 1
    fi
  else
    if ! git clone --depth 1 "$UPSTREAM_URL" "$tmp/ecc" 2>/dev/null; then
      rm -rf "$tmp"
      return 1
    fi
  fi
  clone_sha="$(git -C "$tmp/ecc" rev-parse HEAD)"
  mkdir -p "$ARMORY_DIR"
  find "$ARMORY_DIR" -mindepth 1 -maxdepth 1 ! -name 'PINNED_SHA' -exec rm -rf {} + 2>/dev/null || true
  (cd "$tmp/ecc" && tar cf - --exclude='.git' .) | (cd "$ARMORY_DIR" && tar xf -)
  rm -rf "$tmp"
  printf '%s\n' "$clone_sha" >"$PINNED_FILE"
  if [[ -d "${ARMORY_DIR}/.git" ]]; then
    rm -rf "${ARMORY_DIR}/.git"
  fi
  echo "Synced armory/ecc to affaan-m/ECC commit ${clone_sha}"
  return 0
}

if sync_from_upstream; then
  exit 0
fi

if [[ "$ALLOW_OFFLINE" -eq 1 ]]; then
  echo "sync-armory: upstream unreachable; keeping local armory/ecc (offline mode)"
  echo "sync-armory: local PINNED_SHA=$(current_pinned)"
  exit 0
fi

echo "sync-armory: error: upstream unreachable and --allow-offline not set" >&2
echo "sync-armory: local PINNED_SHA=$(current_pinned)" >&2
exit 1