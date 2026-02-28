#!/usr/bin/env bash
# Switch Pulumi state backend between GCS buckets.
# Usage: ./pulumi-login.sh [bucket-name]

set -euo pipefail

BUCKETS=(
  "dalab-anton-pulumi-state"
  "stix-dev-13dd5-pulumi-state"
)

BOLD="\033[1m"  DIM="\033[2m"  GREEN="\033[32m"  CYAN="\033[36m"  RESET="\033[0m"

current=$(pulumi whoami --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)

echo ""
echo -e "${BOLD}Pulumi Backend Switcher${RESET}"
echo -e "${DIM}Each GCP project has its own state bucket. Switch between them${RESET}"
echo -e "${DIM}to manage different projects' infrastructure with Pulumi.${RESET}"
echo ""

# Direct argument — skip menu
if [[ ${1:-} ]]; then
  pulumi login "gs://$1"
  exit 0
fi

for i in "${!BUCKETS[@]}"; do
  bucket="gs://${BUCKETS[$i]}"
  if [[ "$bucket" == "$current" ]]; then
    echo -e "  ${BOLD}$((i+1)))${RESET} $bucket ${GREEN}← current${RESET}"
  else
    echo -e "  ${BOLD}$((i+1)))${RESET} $bucket"
  fi
done
echo ""

read -rp "  Select [1-${#BUCKETS[@]}]: " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BUCKETS[@]} )); then
  echo "  Invalid selection." >&2
  exit 1
fi

selected="gs://${BUCKETS[$((choice-1))]}"
if [[ "$selected" == "$current" ]]; then
  echo -e "  ${DIM}Already on $selected${RESET}"
  exit 0
fi

pulumi login "$selected"
