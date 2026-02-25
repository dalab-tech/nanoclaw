#!/bin/bash
# Deploy script executed on the remote server.
# Called by .github/workflows/deploy.yml — do not run locally.
set -e

# Run deploy commands as anton (bot user that owns nanoclaw)
sudo -u anton bash -lc "
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

# Restart system service
sudo systemctl restart nanoclaw@anton
echo "Deploy complete"
