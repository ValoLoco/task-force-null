#!/usr/bin/env bash
# Smoke tests for detect-models.sh (stdlib bash + python3).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "${ROOT}/scripts/detect-models.sh"

cp -a "${ROOT}/brain" "${TMP}/brain"
cp -a "${ROOT}/missions/example-mission" "${TMP}/missions-example"
mkdir -p "${TMP}/missions/example-mission"
cp -a "${ROOT}/missions/example-mission/"* "${TMP}/missions/example-mission/"
cp "${ROOT}/AGENTS.md" "${TMP}/AGENTS.md"

"${ROOT}/scripts/detect-models.sh" --repo-root "$TMP" --slug example-mission \
  --env-file "${TMP}/missions/example-mission/squad.env"

grep -q '^| harness |' "${TMP}/brain/models.md" || { echo "missing harness table" >&2; exit 1; }
grep -q 'BEGIN:MODEL_INVENTORY' "${TMP}/AGENTS.md" || { echo "missing AGENTS inventory block" >&2; exit 1; }

HARNESS_LOG="$TMP/harness-pi.log"
CURSOR_AGENT=1 TFN_HARNESS=pi "${ROOT}/scripts/detect-models.sh" --repo-root "$TMP" --slug example-mission \
  --env-file "${TMP}/missions/example-mission/squad.env" >"$HARNESS_LOG" 2>&1
grep -q '^Harness: pi$' "$HARNESS_LOG" || {
  echo "FAIL: TFN_HARNESS=pi did not override CURSOR_AGENT" >&2
  cat "$HARNESS_LOG" >&2
  exit 1
}

HARNESS_LOG2="$TMP/harness-arg.log"
CURSOR_AGENT=1 "${ROOT}/scripts/detect-models.sh" --repo-root "$TMP" --slug example-mission \
  --env-file "${TMP}/missions/example-mission/squad.env" --harness pi >"$HARNESS_LOG2" 2>&1
grep -q '^Harness: pi$' "$HARNESS_LOG2" || {
  echo "FAIL: --harness pi did not override CURSOR_AGENT" >&2
  cat "$HARNESS_LOG2" >&2
  exit 1
}

echo "test_detect_models: ok"