#!/usr/bin/env bash
# Smoke tests for scripts/toc.sh. Does not mutate the real repo config.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "${ROOT}/scripts/toc.sh"

OUT="$("${ROOT}/scripts/toc.sh" 2>&1)"
echo "$OUT" | grep -q 'TASK FORCE NULL  TOC' || { echo "FAIL: toc banner missing" >&2; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q 'DELEGATION: blockers=OFF external=OFF' || { echo "FAIL: delegation strip" >&2; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q 'AUTONOMOUS: OFF' || { echo "FAIL: autonomous strip" >&2; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q 'pushback active' || { echo "FAIL: pushback status" >&2; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q 'setup-mission' || { echo "FAIL: setup-mission missing" >&2; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q 'PINNED_SHA:' || { echo "FAIL: armory line missing" >&2; echo "$OUT"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "${TMP}/brain" "${TMP}/missions/setup-mission" "${TMP}/missions/alpha" "${TMP}/missions/beta" "${TMP}/missions/gamma"
cp "${ROOT}/brain/toc-config.md" "${TMP}/brain/toc-config.md"
{
  echo "# AAR Log"
  for n in 1 2 3 4 5; do
    echo "## 2026-01-0${n}T00:00:00Z | mission:alpha"
    echo "- Outcome: ok ${n}"
    echo "- Friction: none"
    echo "- Fix: none"
  done
} >"${TMP}/brain/aar-log.md"
printf '%s\n' '# Model Inventory' '## Harness' '| field | value |' '| harness | generic |' >"${TMP}/brain/models.md"
for slug in setup-mission alpha beta gamma; do
  printf '%s\n' "# Intent" "" "**Objective:** Goal ${slug}." >"${TMP}/missions/${slug}/mission.md"
  printf '%s\n' 'ACTIVE=0' 'AUTONOMOUS_MODE=false' >"${TMP}/missions/${slug}/squad.env"
  printf '%s\n' '| ID | Task | Owner | Status | Acceptance |' '| T-1 | Work | lead | done | ok |' >"${TMP}/missions/${slug}/board.md"
done
printf '%s\n' 'ACTIVE=1' 'AUTONOMOUS_MODE=false' >"${TMP}/missions/setup-mission/squad.env"
printf '%s\n' '| ID | Task | Owner | Status | Acceptance |' '| T-1 | Work | lead | todo | ok |' >"${TMP}/missions/setup-mission/board.md"

"${ROOT}/scripts/toc.sh" --repo-root "$TMP" --set-delegation blockers=true >/dev/null
grep -q '^DELEGATE_BLOCKERS=true$' "${TMP}/brain/toc-config.md"
grep -q '^DELEGATE_EXTERNAL=false$' "${TMP}/brain/toc-config.md"
grep -q '^AUTONOMOUS_MODE=false$' "${TMP}/missions/setup-mission/squad.env"

"${ROOT}/scripts/toc.sh" --repo-root "$TMP" --set-autonomous true >/dev/null
grep -q '^AUTONOMOUS_MODE=true$' "${TMP}/brain/toc-config.md"
grep -q '^AUTONOMOUS_MODE=true$' "${TMP}/missions/setup-mission/squad.env"
grep -q '^AUTONOMOUS_MODE=false$' "${TMP}/missions/alpha/squad.env"

SET_OUT="$("${ROOT}/scripts/toc.sh" --repo-root "$TMP" 2>&1)"
echo "$SET_OUT" | grep -q 'blockers=ON' || { echo "FAIL: blockers not ON" >&2; echo "$SET_OUT"; exit 1; }
echo "$SET_OUT" | grep -q 'AUTONOMOUS: ON' || { echo "FAIL: autonomous not ON" >&2; echo "$SET_OUT"; exit 1; }
echo "$SET_OUT" | grep -q 'pushback ready' || { echo "FAIL: expected pushback ready with 3 done missions" >&2; echo "$SET_OUT"; exit 1; }

printf '%s\n' 'false' 'keep' 'false' | "${ROOT}/scripts/toc.sh" --repo-root "$TMP" --toggle >/dev/null
grep -q '^DELEGATE_BLOCKERS=false$' "${TMP}/brain/toc-config.md"
grep -q '^DELEGATE_EXTERNAL=false$' "${TMP}/brain/toc-config.md"
grep -q '^AUTONOMOUS_MODE=false$' "${TMP}/brain/toc-config.md"
grep -q '^AUTONOMOUS_MODE=false$' "${TMP}/missions/setup-mission/squad.env"

grep -q '^DELEGATE_BLOCKERS=false$' "${ROOT}/brain/toc-config.md"
grep -q '^AUTONOMOUS_MODE=false$' "${ROOT}/missions/setup-mission/squad.env"

echo "test_toc: ok"
