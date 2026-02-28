#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a GCP project with Pulumi state backend on GCS
# Creates the project, links billing, creates a state bucket, and logs Pulumi in.
#
# Usage:
#   ./pulumi-bootstrap.sh                          # interactive prompts
#   ./pulumi-bootstrap.sh --project my-proj        # skip project prompt
#   ./pulumi-bootstrap.sh --project p --stack dev  # full non-interactive

# ── Defaults ──────────────────────────────────────────────────────────────────
PROJECT_ID=""
PROJECT_NAME=""
REGION="us-central1"
BUCKET_NAME=""
BILLING_ACCOUNT=""
STACK=""

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT_ID="$2"; shift 2 ;;
    --name)     PROJECT_NAME="$2"; shift 2 ;;
    --region)   REGION="$2"; shift 2 ;;
    --bucket)   BUCKET_NAME="$2"; shift 2 ;;
    --billing)  BILLING_ACCOUNT="$2"; shift 2 ;;
    --stack)    STACK="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Bootstrap a GCP project with Pulumi state backend on GCS.

Usage: ./pulumi-bootstrap.sh [OPTIONS]

Options:
  --project ID      GCP project ID (prompted if omitted)
  --name    NAME    Human-readable project name (default: same as project ID)
  --region  REGION  GCS bucket region (default: us-central1)
  --bucket  NAME    State bucket name (default: <project>-pulumi-state)
  --billing ID      Billing account ID (auto-detected if you have exactly one)
  --stack   NAME    Also run `pulumi stack init NAME`
  -h, --help        Show this help

What it does:
  0. Checks prerequisites (gcloud, pulumi) — offers to install if missing
  1. Verifies gcloud authentication and account
  2. Creates GCP project (or reuses existing)
  3. Links a billing account
  4. Enables the Cloud Storage API
  5. Creates a GCS bucket with versioning + public access prevention
  6. Runs `pulumi login gs://<bucket>`
  7. Optionally inits a Pulumi stack
EOF
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
IS_MACOS=false
[[ "$(uname -s)" == "Darwin" ]] && IS_MACOS=true

BOLD="\033[1m"  DIM="\033[2m"  GREEN="\033[32m"  YELLOW="\033[33m"
RED="\033[31m"  CYAN="\033[36m"  RESET="\033[0m"

header()  { echo ""; echo -e "${BOLD}${CYAN}── $1 ─────────────────────────────────────────${RESET}"; echo ""; }
step()    { echo -e "  ${GREEN}✓${RESET} $1"; }
info()    { echo -e "  ${DIM}$1${RESET}"; }
warn()    { echo -e "  ${YELLOW}⚠${RESET} $1"; }
err()     { echo -e "  ${RED}✗${RESET} $1" >&2; }

install_or_exit() {
  local cmd="$1" desc="$2" brew_pkg="$3" linux_cmd="$4"
  warn "$cmd is not installed."
  echo ""
  if $IS_MACOS; then
    info "Install with Homebrew:  brew install $brew_pkg"
  else
    info "Install with:  $linux_cmd"
  fi
  echo ""
  read -rp "  Install $desc now? [Y/n] " yn
  if [[ "${yn:-Y}" =~ ^[Nn] ]]; then
    echo "  Please install $cmd and re-run this script."
    exit 1
  fi
  echo ""
  info "Installing $desc ..."
  if $IS_MACOS; then
    if ! command -v brew &>/dev/null; then
      err "Homebrew is not installed. Install it from https://brew.sh and re-run."
      exit 1
    fi
    brew install $brew_pkg
  else
    eval "$linux_cmd"
  fi
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd still not found after install. Check your PATH and re-run."
    exit 1
  fi
  step "$cmd installed"
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Pulumi + GCP Bootstrap${RESET}"
echo -e "${DIM}Set up a GCP project with a GCS-backed Pulumi state bucket.${RESET}"

# ── Prerequisites ────────────────────────────────────────────────────────────
header "Prerequisites"

if ! command -v gcloud &>/dev/null; then
  install_or_exit "gcloud" "Google Cloud SDK" \
    "--cask google-cloud-sdk" \
    "curl -fsSL https://sdk.cloud.google.com | bash"
else
  step "gcloud $(gcloud version 2>/dev/null | head -1 | sed 's/Google Cloud SDK //')"
fi

if ! command -v pulumi &>/dev/null; then
  install_or_exit "pulumi" "Pulumi CLI" \
    "pulumi" \
    "curl -fsSL https://get.pulumi.com | sh"
else
  step "pulumi $(pulumi version 2>/dev/null)"
fi

# ── Authentication ───────────────────────────────────────────────────────────
header "GCP Authentication"

ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)

if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  warn "Not logged in to gcloud."
  echo ""
  read -rp "  Run 'gcloud auth login' now? [Y/n] " yn
  if [[ "${yn:-Y}" =~ ^[Nn] ]]; then
    echo "  Please run 'gcloud auth login' and re-run this script."
    exit 1
  fi
  gcloud auth login
  ACTIVE_ACCOUNT=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)
  if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    err "Still not authenticated. Please check and re-run."
    exit 1
  fi
fi

step "Logged in as ${BOLD}$ACTIVE_ACCOUNT${RESET}"
echo ""
read -rp "  Is this the correct account? [Y/n] " yn
if [[ "${yn:-Y}" =~ ^[Nn] ]]; then
  echo ""
  info "To switch accounts:"
  info "  gcloud auth login                         # log in with a different account"
  info "  gcloud config set account OTHER@gmail.com  # switch active account"
  echo ""
  echo "  Re-run this script after switching."
  exit 0
fi

PULUMI_BACKEND=$(pulumi whoami --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)
if [[ -n "$PULUMI_BACKEND" ]]; then
  echo ""
  info "Pulumi backend: $PULUMI_BACKEND (will switch after setup)"
fi

# ── Project Selection ────────────────────────────────────────────────────────
header "GCP Project"

echo -e "  ${DIM}Pulumi stores its state (what resources exist, their IDs, outputs) in a GCS${RESET}"
echo -e "  ${DIM}bucket. This bucket lives inside a GCP project — typically the same project${RESET}"
echo -e "  ${DIM}where your infrastructure runs. The bucket name will be: <project>-pulumi-state${RESET}"
echo ""

projects=()
while IFS= read -r line; do
  [[ -n "$line" ]] && projects+=("$line")
done < <(gcloud projects list --format="value(projectId)" 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
  for i in "${!projects[@]}"; do
    echo -e "  ${BOLD}$((i+1)))${RESET} ${projects[$i]}"
  done
  echo -e "  ${BOLD}new)${RESET} Create a new project"
  echo ""
  read -rp "  Select [1-${#projects[@]}/new]: " pick

  if [[ "$pick" =~ ^[Nn][Ee][Ww]$ ]]; then
    read -rp "  New project ID (lowercase, hyphens ok, globally unique): " PROJECT_ID
    [[ -z "$PROJECT_ID" ]] && { err "Project ID is required."; exit 1; }
  elif [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#projects[@]} )); then
    PROJECT_ID="${projects[$((pick-1))]}"
  else
    err "Invalid selection."; exit 1
  fi
fi

EXISTING_PROJECTS=$(printf '%s\n' "${projects[@]}")

PROJECT_EXISTS=false
if echo "$EXISTING_PROJECTS" | grep -qx "$PROJECT_ID"; then
  PROJECT_EXISTS=true
fi

if [[ "$PROJECT_EXISTS" == false ]]; then
  echo ""
  warn "Project '$PROJECT_ID' does not exist and will be CREATED."
  read -rp "  Type the project ID again to confirm: " CONFIRM_ID
  if [[ "$CONFIRM_ID" != "$PROJECT_ID" ]]; then
    err "Project IDs do not match. Aborting."
    exit 1
  fi
  if [[ -z "$PROJECT_NAME" ]]; then
    read -rp "  Human-readable project name [$PROJECT_ID]: " PROJECT_NAME
  fi
fi

[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$PROJECT_ID"
[[ -z "$BUCKET_NAME" ]] && BUCKET_NAME="${PROJECT_ID}-pulumi-state"

# ── Billing ──────────────────────────────────────────────────────────────────
header "Billing"

BILLING_DISPLAY=""
if [[ -z "$BILLING_ACCOUNT" ]]; then
  billing_lines=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && billing_lines+=("$line")
  done < <(gcloud billing accounts list --filter="open=true" --format="csv[no-heading](name,displayName)" 2>/dev/null)

  if [[ ${#billing_lines[@]} -eq 1 ]]; then
    BILLING_ACCOUNT="${billing_lines[0]%%,*}"
    BILLING_DISPLAY="${billing_lines[0]#*,}"
    step "Auto-detected: ${BOLD}$BILLING_DISPLAY${RESET}"
  elif [[ ${#billing_lines[@]} -gt 1 ]]; then
    echo "  Multiple billing accounts found:"
    gcloud billing accounts list --filter="open=true" --format="table(name, displayName)" 2>/dev/null | sed 's/^/  /'
    echo ""
    read -rp "  Billing account ID: " BILLING_ACCOUNT
    [[ -z "$BILLING_ACCOUNT" ]] && { err "Billing account is required."; exit 1; }
  else
    warn "No billing accounts found."
    info "Set one up at https://console.cloud.google.com/billing and re-run,"
    info "or continue without billing (bucket creation will fail until billing is linked)."
    echo ""
    read -rp "  Continue without billing? [y/N] " skip_billing
    if [[ "${skip_billing:-N}" =~ ^[Yy] ]]; then
      BILLING_ACCOUNT=""
    else
      exit 1
    fi
  fi
fi

# ── Confirm ──────────────────────────────────────────────────────────────────
header "Summary"

if [[ "$PROJECT_EXISTS" == true ]]; then
  echo -e "  Project:  ${BOLD}$PROJECT_ID${RESET} ${DIM}(exists)${RESET}"
else
  echo -e "  Project:  ${BOLD}$PROJECT_ID${RESET} ${YELLOW}(new)${RESET}"
fi
if [[ -n "$BILLING_ACCOUNT" ]]; then
  echo -e "  Billing:  ${BOLD}${BILLING_DISPLAY:-$BILLING_ACCOUNT}${RESET}"
else
  echo -e "  Billing:  ${DIM}(none)${RESET}"
fi
echo -e "  Region:   ${BOLD}$REGION${RESET}"
echo -e "  Bucket:   ${BOLD}gs://$BUCKET_NAME${RESET}"
[[ -n "$STACK" ]] && echo -e "  Stack:    ${BOLD}$STACK${RESET}"
echo ""
read -rp "  Proceed? [Y/n] " confirm
[[ "${confirm:-Y}" =~ ^[Nn] ]] && { echo "  Aborted."; exit 0; }

# ── Execute ──────────────────────────────────────────────────────────────────
header "Setting up"

if [[ "$PROJECT_EXISTS" == true ]]; then
  step "Project $PROJECT_ID already exists"
else
  info "Creating project $PROJECT_ID ..."
  gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" --set-as-default
  step "Project created"
fi

gcloud config set project "$PROJECT_ID" --quiet

if [[ -n "$BILLING_ACCOUNT" ]]; then
  CURRENT_BILLING=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || true)
  if [[ -n "$CURRENT_BILLING" ]]; then
    step "Billing already linked"
  else
    info "Linking billing account ..."
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
    step "Billing linked"
  fi
else
  info "Skipping billing (none provided)"
fi

info "Enabling Cloud Storage API ..."
gcloud services enable storage.googleapis.com --project="$PROJECT_ID" --quiet
step "Storage API enabled"

if gcloud storage buckets describe "gs://$BUCKET_NAME" &>/dev/null; then
  step "Bucket gs://$BUCKET_NAME already exists"
else
  info "Creating bucket gs://$BUCKET_NAME ..."
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
  step "Bucket created"
fi

info "Enabling object versioning ..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning
step "Versioning enabled"

info "Logging Pulumi into gs://$BUCKET_NAME ..."
pulumi login "gs://$BUCKET_NAME"
step "Pulumi logged in"

if [[ -n "$STACK" ]]; then
  info "Initializing stack: $STACK ..."
  pulumi stack init "$STACK" 2>/dev/null || pulumi stack select "$STACK"
  step "Stack ready: $STACK"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
header "Done"

echo -e "  Project ${BOLD}$PROJECT_ID${RESET} is ready."
echo ""
echo "  Next steps:"
[[ -z "$STACK" ]] && echo "    pulumi stack init <name>"
echo "    pulumi config set gcp:project $PROJECT_ID"
echo "    pulumi up"
echo ""
