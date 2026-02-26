#!/bin/bash
# Deploy script executed on the remote server.
# Called by .github/workflows/deploy.yml — do not run locally.
#
# Usage: deploy-remote.sh [tenant]
#   tenant: OS username to deploy as (default: anton)
set -e

TENANT="${1:-anton}"
TENANT_UID=$(id -u "$TENANT")

# Run deploy commands as tenant
sudo -u "$TENANT" bash -lc "
  cd ~/nanoclaw

  # Stash local changes, pull, restore
  git stash --include-untracked 2>/dev/null || true
  git pull --rebase origin main
  git stash pop 2>/dev/null || true

  # Install deps and build
  npm install
  npm run build

  # Rebuild container if Dockerfile changed
  if git diff HEAD~1 --name-only | grep -q container/; then
    echo \"Container files changed, rebuilding...\"
    ./container/build.sh
  fi
"

# Ensure lingering is enabled (user service must survive SSH disconnect)
sudo loginctl enable-linger "$TENANT"

# Disable system-level service if present (conflicts with user service)
sudo systemctl disable --now "nanoclaw@${TENANT}" 2>/dev/null || true

# Kill any orphaned nanoclaw processes before restart
sudo -u "$TENANT" bash -c "pgrep -u $TENANT -f 'node.*nanoclaw/dist/index\.js' | xargs -r kill" 2>/dev/null || true
sleep 1

# Restart user service
sudo -u "$TENANT" XDG_RUNTIME_DIR="/run/user/${TENANT_UID}" systemctl --user restart nanoclaw
echo "Deploy complete for tenant: $TENANT"
