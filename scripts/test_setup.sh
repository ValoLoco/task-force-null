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
[[ "$(stat -c '%a' "${ROOT}/.env")" == "600" ]] || { echo "FAIL: .env mode not 600" >&2; exit 1; }
grep -q '^\.env$' "${ROOT}/.gitignore" || { echo "FAIL: .gitignore missing .env" >&2; exit 1; }

OUT="$("${ROOT}/scripts/setup.sh" --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
echo "$OUT" | grep -q '\[dry-run\]' || { echo "FAIL: dry-run markers missing" >&2; echo "$OUT"; exit 1; }

echo "test_setup: ok"