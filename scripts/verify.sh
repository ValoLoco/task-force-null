#!/usr/bin/env bash
# Single entry point for repo health checks (CI and local).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FAILURES=0

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*" >&2
  FAILURES=$((FAILURES + 1))
}

run_check() {
  local name="${1:?}"
  local cmd="${2:?}"
  shift 2
  if "$cmd" "$@"; then
    pass "$name"
  else
    fail "$name"
  fi
}

check_shell_scripts() {
  local s ok=0
  shopt -s nullglob
  for s in "${REPO_ROOT}"/scripts/*.sh; do
    if [[ ! -x "$s" ]]; then
      echo "not executable: $s" >&2
      ok=1
    fi
    if ! bash -n "$s"; then
      echo "bash -n failed: $s" >&2
      ok=1
    fi
  done
  [[ "$ok" -eq 0 ]]
}

check_router() {
  python3 -m py_compile "${REPO_ROOT}/scripts/router.py" &&
    python3 "${REPO_ROOT}/scripts/router.py" --test
}

check_sync_armory() {
  local pinned="${REPO_ROOT}/armory/ecc/PINNED_SHA"
  if [[ ! -f "$pinned" ]] || [[ ! -s "$pinned" ]]; then
    echo "missing or empty armory/ecc/PINNED_SHA" >&2
    return 1
  fi
  if [[ "${VERIFY_SKIP_ONLINE_SYNC:-1}" == "1" ]]; then
    SKIP_SYNC_ARMORY=1 "${REPO_ROOT}/scripts/sync-armory.sh" --allow-offline
  else
    "${REPO_ROOT}/scripts/sync-armory.sh" --allow-offline
  fi
}

check_profiles() {
  local f base count limit=25 ok=0
  local names=(command lead recon builder medic-qa comms)
  for base in "${names[@]}"; do
    f="${REPO_ROOT}/profiles/${base}.md"
    if [[ ! -f "$f" ]]; then
      echo "missing profile: $f" >&2
      ok=1
      continue
    fi
    count="$(wc -l <"$f" | tr -d '[:space:]')"
    echo "  profiles/${base}.md: ${count} lines"
    if [[ "$count" -gt "$limit" ]]; then
      echo "profile over ${limit} lines: $f ($count)" >&2
      ok=1
    fi
  done
  [[ "$ok" -eq 0 ]]
}

check_license_readme() {
  [[ -f "${REPO_ROOT}/LICENSE" ]] || return 1
  grep -q 'MIT' "${REPO_ROOT}/LICENSE" || return 1
  grep -q 'BUENATURA' "${REPO_ROOT}/README.md" || return 1
  grep -q 'TASK FORCE NULL' "${REPO_ROOT}/README.md" || return 1
}

check_setup_artifacts() {
  local ok=0 ps1="${REPO_ROOT}/scripts/setup.ps1"
  [[ -f "$ps1" ]] || { echo "missing setup.ps1" >&2; ok=1; }
  [[ -f "${REPO_ROOT}/scripts/setup.bat" ]] || { echo "missing setup.bat" >&2; ok=1; }
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command "
      \$e = \$null; \$t = \$null
      [void][System.Management.Automation.Language.Parser]::ParseFile('$ps1', [ref]\$t, [ref]\$e)
      if (\$e.Count -gt 0) { \$e | ForEach-Object { Write-Error \$_.ToString() }; exit 1 }
    " || ok=1
  elif command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command "
      \$e = \$null; \$t = \$null
      [void][System.Management.Automation.Language.Parser]::ParseFile('$ps1', [ref]\$t, [ref]\$e)
      if (\$e.Count -gt 0) { \$e | ForEach-Object { Write-Error \$_.ToString() }; exit 1 }
    " || ok=1
  else
    grep -q 'param' "$ps1" && grep -q 'function Write-SetupLog' "$ps1" || ok=1
  fi
  [[ "$ok" -eq 0 ]]
}

check_setup_dry_run() {
  local out
  out="$("${REPO_ROOT}/scripts/setup.sh" \
    --dry-run --non-interactive --skip-llm --skip-keys --skip-deploy --harness generic 2>&1)" || true
  echo "$out" | grep -q '\[dry-run\]'
}

check_no_em_dashes() {
  local hits emdash
  emdash="$(printf '\342\200\224')"
  hits="$(
    find "$REPO_ROOT" \
      -path "${REPO_ROOT}/.git" -prune -o \
      -path "${REPO_ROOT}/armory/ecc" -prune -o \
      -type f -print 2>/dev/null |
      while IFS= read -r f; do
        if grep -qF "$emdash" "$f" 2>/dev/null; then
          echo "$f"
        fi
      done
  )"
  if [[ -n "$hits" ]]; then
    echo "em dash (U+2014) in owned files:" >&2
    echo "$hits" >&2
    return 1
  fi
  return 0
}

echo "verify: repo=${REPO_ROOT}"

run_check "scripts/*.sh executable and bash -n" check_shell_scripts
run_check "router.py py_compile and --test" check_router
run_check "test_detect_models.sh" "${REPO_ROOT}/scripts/test_detect_models.sh"
run_check "sync-armory offline-safe and PINNED_SHA" check_sync_armory
run_check "test_setup.sh" "${REPO_ROOT}/scripts/test_setup.sh"
run_check "test_toc.sh" "${REPO_ROOT}/scripts/test_toc.sh"
run_check "test_toc_web.sh" "${REPO_ROOT}/scripts/test_toc_web.sh"
run_check "setup.ps1 setup.bat syntax" check_setup_artifacts
run_check "setup.sh --dry-run smoke" check_setup_dry_run
run_check "profiles (6 files, <=25 lines)" check_profiles
run_check "LICENSE and README branding" check_license_readme
run_check "no em dashes in owned files" check_no_em_dashes

if [[ "$FAILURES" -gt 0 ]]; then
  echo "verify: ${FAILURES} check(s) failed" >&2
  exit 1
fi

echo "verify: all checks passed"
exit 0