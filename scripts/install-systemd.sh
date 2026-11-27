#!/usr/bin/env bash
# Install systemd user template for sf-agent-unit@<slug>
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIT_SRC="${REPO_ROOT}/systemd/sf-agent-unit@.service"
USER_UNIT_DIR="${HOME}/.config/systemd/user"

usage() {
  echo "Usage: $0 <mission-slug>"
  echo ""
  echo "After install:"
  echo "  systemctl --user daemon-reload"
  echo "  systemctl --user enable --now sf-agent-unit@<slug>.service"
  echo "  loginctl enable-linger \$USER   # so user units survive logout/reboot"
  exit 1
}

[[ $# -eq 1 ]] || usage
SLUG="$1"

if [[ -n "${TERMUX_VERSION:-}" || "${PREFIX:-}" == *com.termux* ]]; then
  echo "error: Termux has no systemd. Run ./scripts/start.sh in a shell. See README Quick install." >&2
  exit 1
fi
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux) ;;
  *)
    echo "error: systemd user units are for Linux with systemd. macOS and Windows run ./scripts/start.sh directly." >&2
    exit 1
    ;;
esac
if ! command -v systemctl >/dev/null 2>&1; then
  echo "error: systemctl not found. This host has no systemd user manager." >&2
  exit 1
fi

[[ -f "$UNIT_SRC" ]] || { echo "error: missing unit template" >&2; exit 1; }
mkdir -p "$USER_UNIT_DIR"
cp "$UNIT_SRC" "${USER_UNIT_DIR}/sf-agent-unit@.service"

# Substitute repo path in drop-in for clarity
DROPIN_DIR="${USER_UNIT_DIR}/sf-agent-unit@${SLUG}.service.d"
mkdir -p "$DROPIN_DIR"
cat > "${DROPIN_DIR}/override.conf" <<EOF
[Service]
Environment=REPO_ROOT=${REPO_ROOT}
Environment=MISSION_SLUG=${SLUG}
EOF

echo "Installed: ${USER_UNIT_DIR}/sf-agent-unit@.service"
echo "Override:  ${DROPIN_DIR}/override.conf"
echo ""
echo "Commands:"
echo "  systemctl --user daemon-reload"
echo "  systemctl --user enable --now sf-agent-unit@${SLUG}.service"
echo "  systemctl --user status sf-agent-unit@${SLUG}.service"
echo ""
echo "Persistence across reboot (run once per user):"
echo "  loginctl enable-linger \${USER}"