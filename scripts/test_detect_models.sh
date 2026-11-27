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

HARNESS_LOG3="$TMP/harness-grok.log"
CURSOR_AGENT=1 GROK_BOT_CLAIM_PRINCIPAL=test "${ROOT}/scripts/detect-models.sh" --repo-root "$TMP" --slug example-mission \
  --env-file "${TMP}/missions/example-mission/squad.env" >"$HARNESS_LOG3" 2>&1
grep -q '^Harness: grok-bot$' "$HARNESS_LOG3" || {
  echo "FAIL: GROK_BOT_CLAIM_PRINCIPAL must beat CURSOR_AGENT (expected grok-bot)" >&2
  cat "$HARNESS_LOG3" >&2
  exit 1
}

HARNESS_LOG4="$TMP/harness-grok-alias.log"
CURSOR_AGENT=1 "${ROOT}/scripts/detect-models.sh" --repo-root "$TMP" --slug example-mission \
  --env-file "${TMP}/missions/example-mission/squad.env" --harness grok >"$HARNESS_LOG4" 2>&1
grep -q '^Harness: grok-bot$' "$HARNESS_LOG4" || {
  echo "FAIL: --harness grok must normalize to grok-bot" >&2
  cat "$HARNESS_LOG4" >&2
  exit 1
}

closed_probe_port() {
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

MOCK_PORT="$(closed_probe_port)"
MOCK_SCRIPT="$(mktemp)"
MOCK_PID=""
cat >"$MOCK_SCRIPT" <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

PORT = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def do_GET(self):
        if self.path == "/v1/models":
            body = json.dumps({"data": [{"id": "detect-mock-model"}]}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
PY

python3 "$MOCK_SCRIPT" "$MOCK_PORT" &
MOCK_PID=$!
sleep 0.3

PROBE_TMP="$(mktemp -d)"
cp -a "${ROOT}/brain" "${PROBE_TMP}/brain"
mkdir -p "${PROBE_TMP}/missions/example-mission"
cp -a "${ROOT}/missions/example-mission/"* "${PROBE_TMP}/missions/example-mission/"
cp "${ROOT}/AGENTS.md" "${PROBE_TMP}/AGENTS.md"

TFN_DETECT_PROBE_OPENAI_URL="http://127.0.0.1:${MOCK_PORT}/v1/models" \
  TFN_DETECT_PROBE_VLLM_URL="http://127.0.0.1:1/v1/models" \
  TFN_DETECT_PROBE_OLLAMA_URL="http://127.0.0.1:1/api/tags" \
  "${ROOT}/scripts/detect-models.sh" --repo-root "$PROBE_TMP" --slug example-mission \
  --env-file "${PROBE_TMP}/missions/example-mission/squad.env" >/dev/null

grep -q 'detect-mock-model' "${PROBE_TMP}/brain/models.md" || {
  echo "FAIL: mock probe did not record model in models.md" >&2
  kill -TERM "$MOCK_PID" 2>/dev/null || true
  rm -f "$MOCK_SCRIPT"
  rm -rf "$PROBE_TMP"
  exit 1
}

kill -TERM "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
rm -f "$MOCK_SCRIPT"
rm -rf "$PROBE_TMP"

echo "test_detect_models: ok"