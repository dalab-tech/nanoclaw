#!/bin/bash
# Usage: ./connect.sh [target] [user]
#   target: gcp (default) | oci
#   user:   anton (default) | son
TARGET="${1:-gcp}"
USER="${2:-anton}"

case "$TARGET" in
  gcp)
    INSTANCE=$(cd "$(dirname "$0")/infra/gcp" && pulumi stack output instanceName 2>/dev/null)
    ZONE=$(cd "$(dirname "$0")/infra/gcp" && pulumi config get nanoclaw:zone 2>/dev/null || echo "us-central1-a")
    if [ -z "$INSTANCE" ]; then
      echo "ERROR: could not resolve GCP instance name from Pulumi" >&2
      exit 1
    fi
    echo "Connecting to GCP ($INSTANCE) via IAP as $USER..."
    exec gcloud compute ssh "$INSTANCE" --zone="$ZONE" --tunnel-through-iap
    ;;
  oci)
    exec "$(dirname "$0")/infra/oracle/connect-nanoclaw.sh" "$USER"
    ;;
  *)
    echo "Usage: ./connect.sh [gcp|oci] [son|anton]"
    exit 1
    ;;
esac
