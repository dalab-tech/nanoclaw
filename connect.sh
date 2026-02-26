#!/bin/bash
# Usage: ./connect.sh <user> [--gcp|--oci]
#   user:   son | anton (required)
#   target: --oci (default) | --gcp
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$1" ] || [[ "$1" == --* ]]; then
  echo "Usage: ./connect.sh <user> [--gcp|--oci]"
  echo "  user:   son | anton"
  echo "  target: --oci (default) | --gcp"
  exit 1
fi

USER="$1"
TARGET="oci"
shift
for arg in "$@"; do
  case "$arg" in
    --gcp) TARGET="gcp" ;;
    --oci) TARGET="oci" ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

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
esac
