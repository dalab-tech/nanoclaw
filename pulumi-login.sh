#!/usr/bin/env bash
# Switch Pulumi state backend between GCS buckets.
# Auto-discovers *-pulumi-state buckets across all accessible GCP projects.
# Usage: ./pulumi-login.sh [bucket-name]

set -euo pipefail

BOLD="\033[1m"  DIM="\033[2m"  GREEN="\033[32m"  YELLOW="\033[33m"  RED="\033[31m"  RESET="\033[0m"

IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

install_or_exit() {
  local cmd="$1" desc="$2" brew_pkg="$3" linux_cmd="$4"
  echo -e "  ${YELLOW}⚠${RESET} $cmd is not installed."
  echo ""
  if $IS_MACOS; then
    echo -e "  ${DIM}Install with Homebrew:  brew install $brew_pkg${RESET}"
  else
    echo -e "  ${DIM}Install with:  $linux_cmd${RESET}"
  fi
  echo ""
  read -rp "  Install $desc now? [Y/n] " yn
  if [[ "${yn:-Y}" =~ ^[Nn] ]]; then
    echo "  Please install $cmd and re-run this script."
    exit 1
  fi
  echo ""
  echo -e "  ${DIM}Installing $desc ...${RESET}"
  if $IS_MACOS; then
    if ! command -v brew &>/dev/null; then
      echo -e "  ${RED}✗${RESET} Homebrew is not installed. Install it from https://brew.sh and re-run." >&2
      exit 1
    fi
    brew install $brew_pkg
  else
    eval "$linux_cmd"
  fi
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "  ${RED}✗${RESET} $cmd still not found after install. Check your PATH and re-run." >&2
    exit 1
  fi
  echo -e "  ${GREEN}✓${RESET} $cmd installed"
}

# ── Prerequisites ────────────────────────────────────────────────────────────
if ! command -v gcloud &>/dev/null; then
  install_or_exit "gcloud" "Google Cloud SDK" \
    "--cask google-cloud-sdk" \
    "curl -fsSL https://sdk.cloud.google.com | bash"
fi

if ! command -v pulumi &>/dev/null; then
  install_or_exit "pulumi" "Pulumi CLI" \
    "pulumi" \
    "curl -fsSL https://get.pulumi.com | sh"
fi

current=$(pulumi whoami --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)

echo ""
echo -e "${BOLD}Pulumi Backend Switcher${RESET}"
echo -e "${DIM}Switch between GCP project state buckets.${RESET}"
echo ""

# Direct argument — skip menu
if [[ ${1:-} ]]; then
  arg="${1#gs://}"
  pulumi login "gs://$arg"
  exit 0
fi

# ── Discover Pulumi state buckets across all projects ────────────────────────

projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
count=$(echo "$projects" | wc -l | tr -d ' ')

printf "  Scanning %d projects...\r" "$count" >&2

PROJECTS=()
BUCKETS=()
while IFS='|' read -r project bucket; do
  [[ -n "$project" && -n "$bucket" ]] || continue
  PROJECTS+=("$project")
  BUCKETS+=("$bucket")
done < <(
  echo "$projects" \
    | xargs -P10 -I{} bash -c \
      'gcloud storage ls --project="{}" 2>/dev/null \
       | grep -i pulumi-state \
       | while read -r b; do echo "{}|${b%/}"; done' \
    | sort
)

printf "\033[K" >&2

if [[ ${#BUCKETS[@]} -eq 0 ]]; then
  echo -e "  ${YELLOW}No Pulumi state buckets found.${RESET}"
  echo -e "  ${DIM}Run ./pulumi-bootstrap.sh to create one.${RESET}"
  echo ""
  exit 1
fi

# ── Auto-select if only one bucket ────────────────────────────────────────────

if [[ ${#BUCKETS[@]} -eq 1 ]]; then
  if [[ "${BUCKETS[0]}" == "$current" ]]; then
    echo -e "  ${DIM}Already on ${PROJECTS[0]}${RESET}"
    exit 0
  fi
  echo -e "  Found: ${BOLD}${PROJECTS[0]}${RESET}  ${DIM}${BUCKETS[0]}${RESET}"
  pulumi login "${BUCKETS[0]}"
  echo ""
  echo -e "  ${GREEN}Switched to ${BOLD}${PROJECTS[0]}${RESET}"
  echo ""
  exit 0
fi

# ── Menu ─────────────────────────────────────────────────────────────────────

for i in "${!BUCKETS[@]}"; do
  bucket="${BUCKETS[$i]}"
  label="${PROJECTS[$i]}"
  if [[ "$bucket" == "$current" ]]; then
    echo -e "  ${BOLD}$((i+1)))${RESET} ${BOLD}$label${RESET}  ${DIM}$bucket${RESET}  ${GREEN}← current${RESET}"
  else
    echo -e "  ${BOLD}$((i+1)))${RESET} $label  ${DIM}$bucket${RESET}"
  fi
done
echo ""

read -rp "  Select [1-${#BUCKETS[@]}]: " choice

if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#BUCKETS[@]} )); then
  echo "  Invalid selection." >&2
  exit 1
fi

selected="${BUCKETS[$((choice-1))]}"
if [[ "$selected" == "$current" ]]; then
  echo -e "  ${DIM}Already on ${PROJECTS[$((choice-1))]}${RESET}"
  exit 0
fi

echo ""
pulumi login "$selected"
echo ""
echo -e "  ${GREEN}Switched to ${BOLD}${PROJECTS[$((choice-1))]}${RESET}"
echo ""
