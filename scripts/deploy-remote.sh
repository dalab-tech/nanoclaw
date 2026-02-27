#!/bin/bash
# Deploy script executed on the remote server.
# Called by .github/workflows/deploy.yml — do not run locally.
#
# Expects environment variables:
#   TENANT: OS username to deploy as (default: current user)
#   REPO_URL: Git repository URL (default: dalab-tech/nanoclaw)
set -e

TENANT="${TENANT:-$(whoami)}"
REPO_URL="${REPO_URL:-git@github.com:dalab-tech/nanoclaw.git}"

# Auto-detect: running as tenant or as admin?
if [ "$(whoami)" = "$TENANT" ]; then
  RUN=""
  TENANT_HOME="$HOME"
else
  RUN="sudo -u $TENANT"
  TENANT_HOME=$(eval echo "~$TENANT")
fi

NCLAW_DIR="$TENANT_HOME/nanoclaw"
NCLAW_CONFIG="$TENANT_HOME/.config/nanoclaw"
ENV_SOURCE="$NCLAW_CONFIG/.env"
SVC_DIR="$TENANT_HOME/.config/systemd/user"
TENANT_UID=$(id -u "$TENANT")

# ── Nanoclaw config provisioning ──────────────────────────────
# These are idempotent and run on every deploy so changes propagate
# without needing to replace the instance.

# Systemd user service for nanoclaw
$RUN mkdir -p "$SVC_DIR/default.target.wants"
$RUN tee "$SVC_DIR/nanoclaw.service" > /dev/null << UNIT
[Unit]
Description=NanoClaw Personal Assistant
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/node $NCLAW_DIR/dist/index.js
WorkingDirectory=$NCLAW_DIR
Restart=always
RestartSec=30
EnvironmentFile=-$ENV_SOURCE
EnvironmentFile=-$NCLAW_CONFIG/port.env
Environment=HOME=$TENANT_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$TENANT_HOME/.local/bin

[Install]
WantedBy=default.target
UNIT
$RUN ln -sf "$SVC_DIR/nanoclaw.service" "$SVC_DIR/default.target.wants/nanoclaw.service"

# GITHUB_TOKEN in .profile so gh/git auth works in interactive sessions
if ! grep -q 'GITHUB_TOKEN.*\.config/nanoclaw' "$TENANT_HOME/.profile" 2>/dev/null; then
  $RUN tee -a "$TENANT_HOME/.profile" > /dev/null << 'PROFILE'

# Auto-export GITHUB_TOKEN from nanoclaw config
if [ -f ~/.config/nanoclaw/.env ]; then
  export GITHUB_TOKEN=$(grep -m1 '^GITHUB_TOKEN=' ~/.config/nanoclaw/.env | cut -d= -f2-)
fi
PROFILE
fi

# ── Clone / update nanoclaw ───────────────────────────────────

# Initial clone if needed
if ! $RUN test -d "$NCLAW_DIR"; then
  echo "Initial clone..."
  $RUN git clone "$REPO_URL" "$NCLAW_DIR"
fi

# Symlink .env from ~/.config/nanoclaw/.env into the repo
if [ -f "$ENV_SOURCE" ]; then
  $RUN ln -sf "$ENV_SOURCE" "$NCLAW_DIR/.env"
fi

# Pull and build as tenant
$RUN bash -lc "
  cd ~/nanoclaw
  git stash --include-untracked 2>/dev/null || true
  git pull --rebase origin main
  git stash pop 2>/dev/null || true
  npm install
  npm run build
  if git diff HEAD~1 --name-only | grep -q container/; then
    echo 'Container files changed, rebuilding...'
    ./container/build.sh
  fi
"

# ── Service management ────────────────────────────────────────

# One-time admin tasks (only when running as admin with sudo)
if [ -n "$RUN" ] && sudo -n true 2>/dev/null; then
  sudo loginctl enable-linger "$TENANT" 2>/dev/null || true
  sudo systemctl disable --now "nanoclaw@${TENANT}" 2>/dev/null || true
fi

# Kill orphaned processes
$RUN bash -c "pgrep -u $TENANT -f 'node.*nanoclaw/dist/index\.js' | xargs -r kill" 2>/dev/null || true
sleep 1

# Reload and restart user service
if [ -n "$RUN" ]; then
  $RUN XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user daemon-reload
  $RUN XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user restart nanoclaw
else
  systemctl --user daemon-reload
  systemctl --user restart nanoclaw
fi

echo "Deploy complete for tenant: $TENANT"
