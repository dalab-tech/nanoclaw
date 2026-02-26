#!/bin/bash
# Usage: ./connect.sh [target] [user]
#   target: gcp | oci (default)
#   user:   son (default) | anton
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-oci}"
USER="${2:-son}"

# Solarized Light theme to distinguish SSH from local terminal
set_theme() {
  printf '\033]11;#fdf6e3\007'
  printf '\033]10;#073642\007'
}

# Reset to default on exit
reset_theme() {
  printf '\033]11;#282c34\007'
  printf '\033]10;#ffffff\007'
}

case "$TARGET" in
  gcp)
    INSTANCE=$(cd "$SCRIPT_DIR/infra/gcp" && pulumi stack output instanceName 2>/dev/null)
    ZONE=$(cd "$SCRIPT_DIR/infra/gcp" && pulumi config get nanoclaw:zone 2>/dev/null || echo "us-central1-a")
    if [ -z "$INSTANCE" ]; then
      echo "ERROR: could not resolve GCP instance name from Pulumi" >&2
      exit 1
    fi

    # GCP OS Login overrides the requested user — switch after connecting
    REMOTE_CMD="status 2>/dev/null; exec \$SHELL -l"
    if [ "$USER" != "$(whoami)" ]; then
      REMOTE_CMD="sudo -iu $USER bash -c 'cd ~/workspace && status 2>/dev/null; exec \$SHELL -l'"
    fi

    echo "Connecting to GCP ($INSTANCE) via IAP as $USER..."
    set_theme
    trap reset_theme EXIT INT TERM

    gcloud compute ssh "$INSTANCE" --zone="$ZONE" --tunnel-through-iap \
      -- -t "$REMOTE_CMD"
    ;;
  oci)
    IP=$(cd "$SCRIPT_DIR/infra/oracle" && pulumi stack output publicIp 2>/dev/null)
    if [ -z "$IP" ]; then
      echo "ERROR: could not resolve OCI public IP from Pulumi" >&2
      exit 1
    fi

    echo "Connecting to OCI ($IP) as $USER..."
    set_theme
    trap reset_theme EXIT INT TERM

    ssh -t "$USER@$IP" "cd ~/workspace && status 2>/dev/null; exec \$SHELL -l"
    ;;
  *)
    echo "Usage: ./connect.sh [gcp|oci] [son|anton]"
    exit 1
    ;;
esac
