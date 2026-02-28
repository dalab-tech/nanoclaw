#!/usr/bin/env bash
# Switch Pulumi state backend between GCS buckets.
# Usage: ./pulumi-login.sh [bucket-name]

set -euo pipefail

BUCKETS=(
  "dalab-anton-pulumi-state"
  "stix-dev-13dd5-pulumi-state"
)

current=$(pulumi whoami --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('url','unknown'))" 2>/dev/null || echo "not logged in")

echo "Current backend: $current"
echo

if [[ ${1:-} ]]; then
  pulumi login "gs://$1"
  exit 0
fi

echo "Available backends:"
for i in "${!BUCKETS[@]}"; do
  echo "  $((i+1))) gs://${BUCKETS[$i]}"
done
echo

read -rp "Select [1-${#BUCKETS[@]}]: " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BUCKETS[@]} )); then
  echo "Invalid selection" >&2
  exit 1
fi

pulumi login "gs://${BUCKETS[$((choice-1))]}"
