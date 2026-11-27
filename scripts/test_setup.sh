#!/usr/bin/env bash
# Automated checks for scripts/setup.sh (no installers, no downloads).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_BACKUP=""
MOCK_PID=""
PROBE_PORT="${TFN_TEST_PROBE_PORT:-}"
INKLING_TMP=""

closed_probe_port() {
  python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

cleanup() {
  if [[ -n "${MOCK_PID:-}" ]] && kill -0 "$MOCK_PID" 2>/dev/null; then
    kill -TERM "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  if [[ -n "${INKLING_TMP:-}" && -d "$INKLING_TMP" ]]; then
    rm -rf "$INKLING_TMP"
  fi
  if [[ -n "$ENV_BACKUP" && -f "$ENV_BACKUP" ]]; then
    mv "$ENV_BACKUP" "${ROOT}/.env"
  fi
}
trap cleanup EXIT

bash -n "${ROOT}/scripts/setup.sh"

if [[ -f "${ROOT}/.env" ]]; then
  ENV_BACKUP="$(mktemp)"
  cp "${ROOT}/.env" "$ENV_BACKUP"
else
  ENV_BACKUP="$(mktemp)"
  : >"$ENV_BACKUP"
fi

printf '%s\n' 'OPENAI_API_KEY=preserve-me' 'NVIDIA_API_KEY=old-nim' >"${ROOT}/.env"
chmod 600 "${ROOT}/.env"

"${ROOT}/scripts/setup.sh" \
  --dry-run \
  --non-interactive \
  --skip-llm \
  --harness cursor \
  --mission-slug setup-auto-test \
  --skip-deploy >/dev/null

grep -q 'preserve-me' "${ROOT}/.env" || { echo "FAIL: .env key wiped" >&2; exit 1; }
mode="$(stat -c '%a' "${ROOT}/.env" 2>/dev/null || true)"
if [[ ! "$mode" =~ ^[0-9]+$ ]]; then
  mode="$(stat -f '%OLp' "${ROOT}/.env" 2>/dev/null || true)"
fi
[[ "$mode" == "600" ]] || { echo "FAIL: .env mode not 600 (${mode})" >&2; exit 1; }
grep -q '^\.env$' "${ROOT}/.gitignore" || { echo "FAIL: .gitignore missing .env" >&2; exit 1; }

PROBE_PORT="${PROBE_PORT:-$(closed_probe_port)}"
probe_env() {
  env TFN_LLM_PROBE_HOST=127.0.0.1 "TFN_LLM_PROBE_PORT=${PROBE_PORT}" TFN_LLM_MODEL_SCAN=0 "$@"
}

GROK_ALIAS_OUT="$(
  probe_env "${ROOT}/scripts/setup.sh" \
    --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy \
    --harness grok 2>&1
)" || true
echo "$GROK_ALIAS_OUT" | grep -q 'using harness: grok-bot' \
  || { echo "FAIL: --harness grok must normalize to grok-bot" >&2; echo "$GROK_ALIAS_OUT"; exit 1; }

OUT="$(probe_env "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
echo "$OUT" | grep -q '\[dry-run\]' || { echo "FAIL: dry-run markers missing" >&2; echo "$OUT"; exit 1; }

assert_declined() {
  local label="$1"
  local body="$2"
  echo "$body" | grep -q 'API keys (in .env) or a remote inference endpoint will be needed to run models' \
    || { echo "FAIL: ${label} missing API key / remote endpoint note" >&2; echo "$body"; exit 1; }
  echo "$body" | grep -q 'setup complete' \
    || { echo "FAIL: ${label} did not continue setup" >&2; echo "$body"; exit 1; }
  if echo "$body" | grep -E -q 'huggingface\.co|would run: curl'; then
    echo "FAIL: ${label} attempted a download" >&2
    echo "$body"
    exit 1
  fi
}

SKIP_OUT="$(probe_env "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
assert_declined "skip-llm" "$SKIP_OUT"

NON_OUT="$(probe_env "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-keys --skip-deploy --harness generic 2>&1)" || true
assert_declined "non-interactive" "$NON_OUT"

ANS_OUT="$(printf 'n\n' | probe_env env TFN_DETECT_RAM_GB=32 TFN_DETECT_DISK_GB=100 \
  "${ROOT}/scripts/setup.sh" --dry-run --skip-keys --skip-deploy --harness generic 2>&1)" || true
echo "$ANS_OUT" | grep -F -q '[y/N]' || { echo "FAIL: decline prompt missing [y/N]" >&2; echo "$ANS_OUT"; exit 1; }
echo "$ANS_OUT" | grep -E -q 'Inkling 2 Mini|unsloth/Inkling' || {
  echo "FAIL: prompt missing Inkling hint" >&2; echo "$ANS_OUT"; exit 1
}
assert_declined "answer n" "$ANS_OUT"

INKLING_TMP="$(mktemp -d)"

assert_inkling_tier() {
  local label="$1" ram="$2" vram="$3" disk="$4" want_file="$5"
  local body
  body="$(probe_env env TFN_DETECT_RAM_GB="$ram" TFN_DETECT_VRAM_GB="$vram" TFN_DETECT_DISK_GB="$disk" \
    "LOCAL_LLM_DIR=${INKLING_TMP}/llm" \
    "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --install-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
  if [[ -z "$want_file" ]]; then
    echo "$body" | grep -q 'local Inkling not recommended' \
      || { echo "FAIL: ${label} should skip local Inkling" >&2; echo "$body"; exit 1; }
    if echo "$body" | grep -E -q 'would run: curl|huggingface\.co.*\.gguf'; then
      echo "FAIL: ${label} should not schedule download" >&2
      echo "$body"
      exit 1
    fi
    return 0
  fi
  echo "$body" | grep -q "$want_file" \
    || { echo "FAIL: ${label} expected ${want_file}" >&2; echo "$body"; exit 1; }
  echo "$body" | grep -q 'unsloth/Inkling-2-Mini-GGUF' \
    || { echo "FAIL: ${label} missing unsloth repo URL" >&2; echo "$body"; exit 1; }
}

assert_inkling_tier "8 GB skip" 8 0 100 ""
assert_inkling_tier "12 GB UD-IQ1_S" 12 0 100 "Inkling-2-Mini-UD-IQ1_S.gguf"
assert_inkling_tier "16 GB UD-Q2_K_XL" 16 0 100 "Inkling-2-Mini-UD-Q2_K_XL.gguf"
assert_inkling_tier "32 GB UD-Q4_K_M" 32 0 100 "Inkling-2-Mini-UD-Q4_K_M.gguf"
assert_inkling_tier "64 GB UD-Q8_K_XL" 64 0 100 "Inkling-2-Mini-UD-Q8_K_XL.gguf"
assert_inkling_tier "64 GB low disk" 64 0 5 ""

probe_env "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1 \
  | grep -q 'scripts/toc.sh' \
  || { echo "FAIL: setup missing TOC next-steps hint" >&2; exit 1; }

MOCK_PORT="$(closed_probe_port)"
MOCK_SCRIPT="$(mktemp)"
cat >"$MOCK_SCRIPT" <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

PORT = int(sys.argv[1])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return

    def do_GET(self):
        if self.path in ("/health", "/v1/models"):
            body = b'{"status":"ok"}' if self.path == "/health" else b'{"data":[{"id":"mock"}]}'
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

MOCK_OUT="$(env TFN_LLM_PROBE_HOST=127.0.0.1 "TFN_LLM_PROBE_PORT=${MOCK_PORT}" TFN_LLM_MODEL_SCAN=0 \
  "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-keys --skip-deploy --harness generic 2>&1)" || true
echo "$MOCK_OUT" | grep -q 'detected local model server at' \
  || { echo "FAIL: mock LLM server not detected" >&2; echo "$MOCK_OUT"; exit 1; }
echo "$MOCK_OUT" | grep -q "http://127.0.0.1:${MOCK_PORT}" \
  || { echo "FAIL: mock probe base URL missing" >&2; echo "$MOCK_OUT"; exit 1; }

kill -TERM "$MOCK_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
MOCK_PID=""
rm -f "$MOCK_SCRIPT"

SCAN_TMP="$(mktemp -d)"
touch "${SCAN_TMP}/probe-dummy.gguf"
SEARCH_OUT="$(env TFN_LLM_PROBE_HOST=127.0.0.1 "TFN_LLM_PROBE_PORT=${PROBE_PORT}" \
  "TFN_LLM_SEARCH_DIRS=${SCAN_TMP}" \
  "${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-keys --skip-deploy --harness generic 2>&1)" || true
rm -rf "$SCAN_TMP"
echo "$SEARCH_OUT" | grep -q 'detected local model at' \
  || { echo "FAIL: TFN_LLM_SEARCH_DIRS did not detect dummy .gguf" >&2; echo "$SEARCH_OUT"; exit 1; }
if echo "$SEARCH_OUT" | grep -E -q 'huggingface\.co|would run: curl'; then
  echo "FAIL: TFN_LLM_SEARCH_DIRS detection should skip install without download" >&2
  echo "$SEARCH_OUT"
  exit 1
fi

echo "test_setup: ok"