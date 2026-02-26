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
ENV_SOURCE="$TENANT_HOME/.$TENANT/.env.nanoclaw"

# Initial clone if needed
if [ ! -d "$NCLAW_DIR" ]; then
  echo "Initial clone..."
  $RUN git clone "$REPO_URL" "$NCLAW_DIR"
fi

# Symlink .env from ~/.<tenant>/.env.nanoclaw into the repo
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

# One-time admin tasks (only when running as admin with sudo)
if [ -n "$RUN" ] && sudo -n true 2>/dev/null; then
  sudo loginctl enable-linger "$TENANT" 2>/dev/null || true
  sudo systemctl disable --now "nanoclaw@${TENANT}" 2>/dev/null || true
fi

# Kill orphaned processes
$RUN bash -c "pgrep -u $TENANT -f 'node.*nanoclaw/dist/index\.js' | xargs -r kill" 2>/dev/null || true
sleep 1

# Restart user service
TENANT_UID=$(id -u "$TENANT")
if [ -n "$RUN" ]; then
  $RUN XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user restart nanoclaw
else
  systemctl --user restart nanoclaw
fi

echo "Deploy complete for tenant: $TENANT"
