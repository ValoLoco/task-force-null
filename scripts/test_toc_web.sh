#!/usr/bin/env bash
# Smoke tests for scripts/toc-web.py and scripts/toc.sh --web
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -m py_compile "${ROOT}/scripts/toc_lib.py" "${ROOT}/scripts/toc_chat.py" "${ROOT}/scripts/toc-web.py"

TMP="$(mktemp -d)"
trap 'cleanup' EXIT INT TERM

SRV_PID=""
cleanup() {
  if [[ -n "${SRV_PID:-}" ]] && kill -0 "$SRV_PID" 2>/dev/null; then
    kill -TERM "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}

mkdir -p "${TMP}/brain" "${TMP}/missions/setup-mission/logs"
cp "${ROOT}/brain/toc-config.md" "${TMP}/brain/toc-config.md"
printf '%s\n' '# Harness' '## Harness' '| field | value |' '| harness | test |' >"${TMP}/brain/models.md"
printf '%s\n' "# Intent" "" "**Objective:** Web TOC test." >"${TMP}/missions/setup-mission/mission.md"
printf '%s\n' 'ACTIVE=1' 'AUTONOMOUS_MODE=false' >"${TMP}/missions/setup-mission/squad.env"
{
  echo '| ID | Task | Owner | Status | Acceptance |'
  echo '|----|------|-------|--------|------------|'
  echo '| T-1 | Alpha | lead | todo | ok |'
} >"${TMP}/missions/setup-mission/board.md"
echo "log line one" >"${TMP}/missions/setup-mission/logs/lead.log"

SRV_LOG="$TMP/server.log"
rm -f "${TMP}/.toc-web.json"

"${ROOT}/scripts/toc.sh" --web --port 0 --no-open --repo-root "$TMP" >"$SRV_LOG" 2>&1 &
SRV_PID=$!

URL=""
for _ in $(seq 1 40); do
  if grep -qE '^http://127\.0\.0\.1:[0-9]+$' "$SRV_LOG" 2>/dev/null; then
    URL="$(grep -E '^http://127\.0\.0\.1:[0-9]+$' "$SRV_LOG" | head -1)"
    break
  fi
  kill -0 "$SRV_PID" 2>/dev/null || {
    echo "FAIL: web server exited early" >&2
    cat "$SRV_LOG" >&2
    exit 1
  }
  sleep 0.15
done

if [[ -z "$URL" ]]; then
  echo "FAIL: no URL printed" >&2
  cat "$SRV_LOG" >&2
  exit 1
fi

DUP_OUT="$("${ROOT}/scripts/toc.sh" --web --port 0 --no-open --repo-root "$TMP" 2>&1)"
echo "$DUP_OUT" | grep -qF "$URL" || {
  echo "FAIL: idempotent restart did not return existing URL" >&2
  echo "$DUP_OUT"
  exit 1
}

HTML="$(curl -fsS "$URL/")"
echo "$HTML" | grep -q 'TFN_TOC_WEB' || { echo "FAIL: HTML marker missing" >&2; exit 1; }
echo "$HTML" | grep -q 'tfn-toc-dashboard' || { echo "FAIL: dashboard id missing" >&2; exit 1; }

STATE="$(curl -fsS "$URL/api/state")"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
for key in ('missions', 'aars', 'routing', 'armory'):
    assert key in d, 'missing ' + key
assert isinstance(d['missions'], list)
if d['missions']:
    assert 'tasks' in d['missions'][0]
" "$STATE"

LOG_MARK="tfn_sse_log_probe_$$"
SSE_LOG="$TMP/sse-capture.txt"
: >"$SSE_LOG"
curl -sS -N --max-time 20 "$URL/events" >>"$SSE_LOG" 2>/dev/null &
SSE_PID=$!
sleep 0.6
grep -q 'event: state' "$SSE_LOG" || { echo "FAIL: SSE state frame missing" >&2; cat "$SSE_LOG" >&2; exit 1; }
"${ROOT}/scripts/op-log.sh" --repo-root "$TMP" setup-mission lead -- printf '%s\n' "$LOG_MARK"
for _ in $(seq 1 60); do
  if grep -q 'event: log' "$SSE_LOG" && grep -qF "$LOG_MARK" "$SSE_LOG"; then
    break
  fi
  sleep 0.15
done
kill -TERM "$SSE_PID" 2>/dev/null || true
wait "$SSE_PID" 2>/dev/null || true
grep -q 'event: log' "$SSE_LOG" || { echo "FAIL: SSE log event missing" >&2; cat "$SSE_LOG" >&2; exit 1; }
grep -qF "$LOG_MARK" "$SSE_LOG" || { echo "FAIL: SSE log payload missing marker" >&2; cat "$SSE_LOG" >&2; exit 1; }

CHAT_MARK="tfn_chat_probe_$$"
CHAT_SSE="$TMP/chat-sse.txt"
: >"$CHAT_SSE"
curl -sS -N --max-time 25 "$URL/events" >>"$CHAT_SSE" 2>/dev/null &
CHAT_SSE_PID=$!
sleep 0.5

CHAT_POST="$(curl -sS -w '\n%{http_code}' -X POST "$URL/api/chat" \
  -H 'Content-Type: application/json' \
  -d "{\"mission\":\"setup-mission\",\"sender\":\"user\",\"text\":\"$CHAT_MARK\"}")"
CHAT_HTTP="$(echo "$CHAT_POST" | tail -1)"
CHAT_BODY="$(echo "$CHAT_POST" | sed '$d')"
[[ "$CHAT_HTTP" == "201" ]] || {
  echo "FAIL: POST /api/chat expected 201 got $CHAT_HTTP" >&2
  echo "$CHAT_BODY" >&2
  exit 1
}
python3 -c "
import json, sys
row = json.loads(sys.argv[1])
assert row.get('text') == sys.argv[2]
assert row.get('mission') == 'setup-mission'
" "$CHAT_BODY" "$CHAT_MARK"

CHAT_LOG="${TMP}/missions/setup-mission/logs/commander-chat.jsonl"
[[ -f "$CHAT_LOG" ]] || { echo "FAIL: commander-chat.jsonl missing" >&2; exit 1; }
grep -qF "$CHAT_MARK" "$CHAT_LOG" || {
  echo "FAIL: chat not persisted to JSONL" >&2
  cat "$CHAT_LOG" >&2
  exit 1
}

CHAT_GET="$(curl -fsS "$URL/api/chat?mission=setup-mission&limit=50")"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['mission'] == 'setup-mission'
texts = [m['text'] for m in d['messages']]
assert sys.argv[2] in texts, 'GET /api/chat missing posted message'
" "$CHAT_GET" "$CHAT_MARK"

BAD_CODE="$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/chat?mission=../etc&limit=10")"
[[ "$BAD_CODE" == "400" ]] || {
  echo "FAIL: invalid mission slug expected 400 got $BAD_CODE" >&2
  exit 1
}

for _ in $(seq 1 60); do
  if grep -q 'event: chat' "$CHAT_SSE" && grep -qF "$CHAT_MARK" "$CHAT_SSE"; then
    break
  fi
  sleep 0.15
done
kill -TERM "$CHAT_SSE_PID" 2>/dev/null || true
wait "$CHAT_SSE_PID" 2>/dev/null || true
grep -q 'event: chat' "$CHAT_SSE" || {
  echo "FAIL: SSE chat event missing" >&2
  cat "$CHAT_SSE" >&2
  exit 1
}
grep -qF "$CHAT_MARK" "$CHAT_SSE" || {
  echo "FAIL: SSE chat payload missing marker" >&2
  cat "$CHAT_SSE" >&2
  exit 1
}

CODE="$(curl -s -o /dev/null -w '%{http_code}' "$URL/.env")"
[[ "$CODE" == "404" ]] || { echo "FAIL: expected 404 for /.env got $CODE" >&2; exit 1; }

[[ -f "${TMP}/.toc-web.json" ]] || { echo "FAIL: .toc-web.json missing" >&2; exit 1; }

kill -TERM "$SRV_PID" 2>/dev/null || true
wait "$SRV_PID" 2>/dev/null || true
SRV_PID=""

for _ in $(seq 1 30); do
  [[ ! -f "${TMP}/.toc-web.json" ]] && break
  sleep 0.1
done
[[ ! -f "${TMP}/.toc-web.json" ]] || { echo "FAIL: stale .toc-web.json after shutdown" >&2; exit 1; }

echo "test_toc_web: ok"