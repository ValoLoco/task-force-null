#!/usr/bin/env bash
# Tests for scripts/op-log.sh (isolated temp mission logs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "${ROOT}/scripts/op-log.sh"

MISSION="oplog-test"
mkdir -p "${TMP}/missions/${MISSION}/logs"
touch "${TMP}/missions/${MISSION}/board.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

"${ROOT}/scripts/op-log.sh" --repo-root "$TMP" "$MISSION" lead -- printf 'line-one\n' \
  || fail "valid role should succeed"
LOG="${TMP}/missions/${MISSION}/logs/lead.log"
[[ -f "$LOG" ]] || fail "log file missing"
grep -q 'line-one' "$LOG" || fail "log missing content"
grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$LOG" \
  || fail "timestamp format"
count="$(grep -c 'line-one' "$LOG" || true)"
[[ "$count" -eq 1 ]] || fail "expected one stamped line"

BAD_RC=0
"${ROOT}/scripts/op-log.sh" --repo-root "$TMP" "$MISSION" invalid-role -- true 2>/dev/null || BAD_RC=$?
[[ "$BAD_RC" -ne 0 ]] || fail "invalid role must exit non-zero"

EXIT_RC=0
"${ROOT}/scripts/op-log.sh" --repo-root "$TMP" "$MISSION" builder -- sh -c 'echo builder-line; exit 7' || EXIT_RC=$?
[[ "$EXIT_RC" -eq 7 ]] || fail "expected exit code 7 from wrapped command, got ${EXIT_RC}"
[[ -f "${TMP}/missions/${MISSION}/logs/builder.log" ]] || fail "builder log missing"
grep -q 'builder-line' "${TMP}/missions/${MISSION}/logs/builder.log" || fail "builder log content"

echo "test_op_log: ok"