#!/bin/bash
# Restart a tenant's nanoclaw service.
#
# Usage: sudo restart-tenant.sh <username>
set -euo pipefail
trap 'echo "Error: script failed at line $LINENO (exit code $?)" >&2' ERR

[ "$(id -u)" -eq 0 ] || { echo "Must run as root (use sudo)"; exit 1; }

USERNAME="${1:-}"
[ -z "$USERNAME" ] && { echo "Usage: sudo $0 <username>"; exit 1; }

id "$USERNAME" &>/dev/null || { echo "Error: user $USERNAME does not exist"; exit 1; }

TENANT_UID=$(id -u "$USERNAME")

echo "Restarting nanoclaw for $USERNAME..."
sudo -u "$USERNAME" XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user restart nanoclaw
echo "Done. Status:"
sudo -u "$USERNAME" XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user status nanoclaw --no-pager || true
