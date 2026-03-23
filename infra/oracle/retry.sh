#!/bin/bash
set -euo pipefail

# Retry pulumi up until the instance is created.
# ARM capacity on Oracle free tier is scarce — this retries every 5 minutes.
# Usage: ./retry.sh        (runs in foreground)
#        nohup ./retry.sh & (runs in background, check retry.log)

INTERVAL=${1:-300}  # seconds between retries (default: 5 min)
MAX_ATTEMPTS=${2:-288}  # max retries (default: 288 = 24 hours at 5 min)
LOG="retry.log"

echo "Retrying pulumi up every ${INTERVAL}s (max ${MAX_ATTEMPTS} attempts)"
echo "Logging to $LOG"
echo ""

for i in $(seq 1 "$MAX_ATTEMPTS"); do
  echo "[$(date '+%H:%M:%S')] Attempt $i/$MAX_ATTEMPTS..." | tee -a "$LOG"

  if pulumi up --yes --skip-preview 2>&1 | tee -a "$LOG" | grep -q "Resources:"; then
    # Check if instance was created successfully
    if pulumi stack output publicIp 2>/dev/null; then
      echo "" | tee -a "$LOG"
      echo "=== Instance created! ===" | tee -a "$LOG"
      echo "SSH: $(pulumi stack output sshCommand)" | tee -a "$LOG"
      exit 0
    fi
  fi

  echo "  Out of capacity. Retrying in ${INTERVAL}s..." | tee -a "$LOG"
  sleep "$INTERVAL"
done

echo "Max attempts reached. Try a different region or time." | tee -a "$LOG"
exit 1
