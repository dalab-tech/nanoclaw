#!/bin/bash
# Provision a tenant user on a nanoclaw instance.
# Idempotent — safe to re-run. Creates OS user, sets port, configures basics.
#
# Usage: sudo provision-tenant.sh <username> --port <port> [--admin]
set -euo pipefail

usage() {
  echo "Usage: sudo $0 <username> --port <port> [--admin]"
  echo "  --port   localhost port for this tenant's nanoclaw (e.g. 3001)"
  echo "  --admin  grant sudo access"
  exit 1
}

[ "$(id -u)" -eq 0 ] || { echo "Must run as root (use sudo)"; exit 1; }

USERNAME="${1:-}"
[ -z "$USERNAME" ] && usage
shift

PORT=""
ADMIN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --port)  PORT="$2"; shift 2 ;;
    --admin) ADMIN=true; shift ;;
    *)       usage ;;
  esac
done

[ -z "$PORT" ] && usage

# Validate port is a number
if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: port must be a number, got '$PORT'"
  exit 1
fi

# ── Port collision check ─────────────────────────────────────────────
for portfile in /home/*/.config/nanoclaw/port.env; do
  [ -f "$portfile" ] || continue
  EXISTING_PORT=$(grep -m1 '^PORT=' "$portfile" 2>/dev/null | cut -d= -f2-)
  EXISTING_USER=$(echo "$portfile" | cut -d/ -f3)
  if [ "$EXISTING_PORT" = "$PORT" ] && [ "$EXISTING_USER" != "$USERNAME" ]; then
    echo "Error: port $PORT already assigned to $EXISTING_USER (in $portfile)"
    exit 1
  fi
done

# ── Detect default OS user (for SSH key copy) ────────────────────────
if id ubuntu &>/dev/null; then DEFAULT_USER=ubuntu
elif id opc &>/dev/null; then DEFAULT_USER=opc
else DEFAULT_USER=root; fi
DEFAULT_HOME=$(eval echo "~$DEFAULT_USER")

echo "Provisioning tenant: $USERNAME (port $PORT, admin=$ADMIN)"

# ── 1. Create OS user ────────────────────────────────────────────────
if id "$USERNAME" &>/dev/null; then
  echo "  User $USERNAME already exists, skipping creation"
else
  useradd -m -s /bin/bash "$USERNAME"
  echo "  Created user $USERNAME"
fi

# ── 2. Groups ────────────────────────────────────────────────────────
usermod -aG docker,systemd-journal "$USERNAME"

# ── 3. SSH authorized_keys from default OS user ──────────────────────
USER_HOME=$(eval echo "~$USERNAME")
mkdir -p "$USER_HOME/.ssh"
if [ -f "$DEFAULT_HOME/.ssh/authorized_keys" ]; then
  cp "$DEFAULT_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/authorized_keys"
  chmod 600 "$USER_HOME/.ssh/authorized_keys"
fi
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

# ── 4. GitHub SSH key ────────────────────────────────────────────────
if [ -f "$USER_HOME/.ssh/id_ed25519" ]; then
  echo "  SSH key already exists, skipping"
else
  su - "$USERNAME" -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C '${USERNAME}@nanoclaw'"
  echo "  Generated SSH key"
fi

# ── 5. Workspace ─────────────────────────────────────────────────────
mkdir -p "$USER_HOME/workspace"
chown "$USERNAME:$USERNAME" "$USER_HOME/workspace"

# ── 6. Midnight Commander config ─────────────────────────────────────
mkdir -p "$USER_HOME/.config/mc"
echo -e "[Midnight-Commander]\nskin=warm256" > "$USER_HOME/.config/mc/ini"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config"

# ── 7. Lingering ─────────────────────────────────────────────────────
loginctl enable-linger "$USERNAME"

# ── 8. Sudo ──────────────────────────────────────────────────────────
if [ "$ADMIN" = true ]; then
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
  chmod 440 "/etc/sudoers.d/$USERNAME"
  echo "  Granted sudo access"
else
  rm -f "/etc/sudoers.d/$USERNAME"
fi

# ── 9. Nanoclaw config dir ───────────────────────────────────────────
mkdir -p "$USER_HOME/.config/nanoclaw"

# ── 10. Port assignment ──────────────────────────────────────────────
echo "PORT=$PORT" > "$USER_HOME/.config/nanoclaw/port.env"
chown -R "$USERNAME:$USERNAME" "$USER_HOME/.config/nanoclaw"

echo ""
echo "Tenant $USERNAME provisioned successfully (port $PORT)"
echo ""
echo "Next steps:"
echo "  1. Add GitHub deploy key:"
echo "     cat $USER_HOME/.ssh/id_ed25519.pub"
echo ""
echo "  2. Add route to infra/cloudflare/tunnel.config.ts and run pulumi up"
echo ""
echo "  3. Deploy nanoclaw:"
echo "     gh workflow run deploy.yml -f tenant=$USERNAME -f target=gcp"
