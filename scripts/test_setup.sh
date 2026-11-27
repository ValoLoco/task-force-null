#!/usr/bin/env bash
# Automated checks for scripts/setup.sh (no installers, no downloads).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_BACKUP=""

cleanup() {
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

OUT="$("${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
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

SKIP_OUT="$("${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
assert_declined "skip-llm" "$SKIP_OUT"

NON_OUT="$("${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-keys --skip-deploy --harness generic 2>&1)" || true
assert_declined "non-interactive" "$NON_OUT"

ANS_OUT="$(printf 'n\n' | "${ROOT}/scripts/setup.sh" --dry-run --skip-keys --skip-deploy --harness generic 2>&1)" || true
echo "$ANS_OUT" | grep -F -q '[y/N]' || { echo "FAIL: decline prompt missing [y/N]" >&2; echo "$ANS_OUT"; exit 1; }
echo "$ANS_OUT" | grep -F -q '6.5 GB' || { echo "FAIL: prompt missing 6.5 GB" >&2; echo "$ANS_OUT"; exit 1; }
echo "$ANS_OUT" | grep -F -q 'AD IQ1_S' || { echo "FAIL: prompt missing AD IQ1_S" >&2; echo "$ANS_OUT"; exit 1; }
assert_declined "answer n" "$ANS_OUT"

echo "test_setup: ok"