#!/usr/bin/env bash
# Clone missions/_template into missions/<slug> and activate deployment.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="${REPO_ROOT}/missions/_template"
MISSIONS="${REPO_ROOT}/missions"

usage() {
  echo "Usage: $0 <mission-slug> [mission-objective sentence]"
  exit 1
}

[[ $# -ge 1 ]] || usage

SLUG="$1"
OBJECTIVE="${2:-Complete mission objectives per success criteria.}"

if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
  echo "error: slug must match ^[a-z0-9][a-z0-9_-]*$" >&2
  exit 1
fi

DEST="${MISSIONS}/${SLUG}"
if [[ -e "$DEST" ]]; then
  echo "error: mission already exists: $DEST" >&2
  exit 1
fi

if [[ ! -d "$TEMPLATE" ]]; then
  echo "error: missing template: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$DEST"
for f in mission.md intel.md board.md; do
  cp "${TEMPLATE}/${f}" "${DEST}/"
done

cat > "${DEST}/squad.env" <<EOF
MISSION_SLUG=${SLUG}
REPO_ROOT=${REPO_ROOT}
MODEL_TIER_DEFAULT=standard
MODEL_TIER_RECON=light
MODEL_TIER_BUILDER=standard
MODEL_TIER_COMMAND=heavy
ACTIVE=1
EOF

# Patch mission.md slug and objective
sed -i "s/\`<slug>\`/\`${SLUG}\`/g" "${DEST}/mission.md"
sed -i "s/One sentence end state./${OBJECTIVE}/" "${DEST}/mission.md"

# Deactivate other missions (single active)
while IFS= read -r envfile; do
  [[ "$envfile" == "${DEST}/squad.env" ]] && continue
  if grep -q '^ACTIVE=1' "$envfile" 2>/dev/null; then
    sed -i 's/^ACTIVE=1$/ACTIVE=0/' "$envfile"
  fi
done < <(find "${MISSIONS}" -mindepth 2 -maxdepth 2 -name 'squad.env' 2>/dev/null)

if [[ "${SKIP_SYNC_ARMORY:-0}" != "1" ]]; then
  "${REPO_ROOT}/scripts/sync-armory.sh" --allow-offline || \
    echo "note: sync-armory failed unexpectedly"
fi

if [[ "${SKIP_DETECT_MODELS:-0}" != "1" ]]; then
  MISSION_SLUG="${SLUG}" "${REPO_ROOT}/scripts/detect-models.sh" --slug "${SLUG}" || \
    echo "note: detect-models.sh skipped or failed (offline OK); run manually later"
fi

echo "Deployed mission: ${SLUG}"
echo "Mission dir: ${DEST}"
echo "Run: MISSION_SLUG=${SLUG} ${REPO_ROOT}/scripts/start.sh"