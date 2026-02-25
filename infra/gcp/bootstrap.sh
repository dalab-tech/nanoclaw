#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a GCP project with Pulumi state backend on GCS
# Creates the project, links billing, creates a state bucket, and logs Pulumi in.
#
# Usage:
#   ./bootstrap.sh                          # interactive prompts
#   ./bootstrap.sh --project my-proj        # skip project prompt
#   ./bootstrap.sh --project p --stack dev  # full non-interactive

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

Usage: ./bootstrap.sh [OPTIONS]

Options:
  --project ID      GCP project ID (prompted if omitted)
  --name    NAME    Human-readable project name (default: same as project ID)
  --region  REGION  GCS bucket region (default: us-central1)
  --bucket  NAME    State bucket name (default: <project>-pulumi-state)
  --billing ID      Billing account ID (auto-detected if you have exactly one)
  --stack   NAME    Also run `pulumi stack init NAME`
  -h, --help        Show this help

What it does:
  1. Creates GCP project (or reuses existing)
  2. Links a billing account
  3. Enables the Cloud Storage API
  4. Creates a GCS bucket with versioning + public access prevention
  5. Runs `pulumi login gs://<bucket>`
  6. Optionally inits a Pulumi stack
EOF
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Preflight checks ─────────────────────────────────────────────────────────
for cmd in gcloud pulumi; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: $cmd is required but not found in PATH" >&2
    exit 1
  fi
done

# ── Resolve project ───────────────────────────────────────────────────────────
# Fetch existing projects once for reuse
EXISTING_PROJECTS=$(gcloud projects list --format="value(projectId)" 2>/dev/null || true)

if [[ -z "$PROJECT_ID" ]]; then
  echo "Your existing GCP projects:"
  gcloud projects list --format="table(projectId, name)" 2>/dev/null || true
  echo ""
  read -rp "GCP project ID (existing or new): " PROJECT_ID
  [[ -z "$PROJECT_ID" ]] && { echo "ERROR: project ID is required"; exit 1; }
fi

PROJECT_EXISTS=false
if echo "$EXISTING_PROJECTS" | grep -qx "$PROJECT_ID"; then
  PROJECT_EXISTS=true
fi

# Guard against typos: if the project doesn't exist, require explicit confirmation
if [[ "$PROJECT_EXISTS" == false ]]; then
  echo ""
  echo "WARNING: Project '$PROJECT_ID' does not exist and will be CREATED."
  read -rp "Type the project ID again to confirm: " CONFIRM_ID
  if [[ "$CONFIRM_ID" != "$PROJECT_ID" ]]; then
    echo "ERROR: project IDs do not match. Aborting." >&2
    exit 1
  fi
  if [[ -z "$PROJECT_NAME" ]]; then
    read -rp "Human-readable project name [$PROJECT_ID]: " PROJECT_NAME
  fi
fi

[[ -z "$PROJECT_NAME" ]] && PROJECT_NAME="$PROJECT_ID"
[[ -z "$BUCKET_NAME" ]] && BUCKET_NAME="${PROJECT_ID}-pulumi-state"

# ── Detect billing account ───────────────────────────────────────────────────
BILLING_DISPLAY=""
if [[ -z "$BILLING_ACCOUNT" ]]; then
  # Read both ID and display name together
  billing_lines=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && billing_lines+=("$line")
  done < <(gcloud billing accounts list --filter="open=true" --format="csv[no-heading](name,displayName)" 2>/dev/null)

  if [[ ${#billing_lines[@]} -eq 1 ]]; then
    BILLING_ACCOUNT="${billing_lines[0]%%,*}"
    BILLING_DISPLAY="${billing_lines[0]#*,}"
  elif [[ ${#billing_lines[@]} -gt 1 ]]; then
    echo ""
    echo "Multiple billing accounts found:"
    gcloud billing accounts list --filter="open=true" --format="table(name, displayName)" 2>/dev/null
    echo ""
    read -rp "Billing account ID: " BILLING_ACCOUNT
    [[ -z "$BILLING_ACCOUNT" ]] && { echo "ERROR: billing account is required"; exit 1; }
  else
    echo ""
    echo "No billing accounts found. You can either:"
    echo "  1. Set one up at https://console.cloud.google.com/billing and re-run"
    echo "  2. Continue without billing (bucket creation will fail until billing is linked)"
    echo ""
    read -rp "Continue without billing? [y/N] " skip_billing
    if [[ "${skip_billing:-N}" =~ ^[Yy] ]]; then
      BILLING_ACCOUNT=""
    else
      exit 1
    fi
  fi
fi

# ── Confirm plan ──────────────────────────────────────────────────────────────
echo ""
if [[ "$PROJECT_EXISTS" == true ]]; then
  echo "==> Project:  $PROJECT_ID (exists)"
else
  echo "==> Project:  $PROJECT_ID (NEW — will be created)"
fi
if [[ -n "$BILLING_ACCOUNT" ]]; then
  echo "==> Billing:  ${BILLING_DISPLAY:-$BILLING_ACCOUNT} ($BILLING_ACCOUNT)"
else
  echo "==> Billing:  (none)"
fi
echo "==> Region:   $REGION"
echo "==> Bucket:   gs://$BUCKET_NAME"
[[ -n "$STACK" ]] && echo "==> Stack:    $STACK"
echo ""
read -rp "Continue? [Y/n] " confirm
[[ "${confirm:-Y}" =~ ^[Nn] ]] && { echo "Aborted."; exit 0; }

# ── 1. Create project (or skip if it exists) ─────────────────────────────────
if [[ "$PROJECT_EXISTS" == true ]]; then
  echo "==> Project $PROJECT_ID already exists, skipping creation"
else
  echo "==> Creating project $PROJECT_ID ..."
  gcloud projects create "$PROJECT_ID" --name="$PROJECT_NAME" --set-as-default
fi

gcloud config set project "$PROJECT_ID" --quiet

# ── 2. Link billing account ──────────────────────────────────────────────────
if [[ -n "$BILLING_ACCOUNT" ]]; then
  CURRENT_BILLING=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || true)
  if [[ -n "$CURRENT_BILLING" ]]; then
    echo "==> Billing already linked: $CURRENT_BILLING"
  else
    echo "==> Linking billing account $BILLING_ACCOUNT ..."
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
  fi
else
  echo "==> Skipping billing (none provided)"
fi

# ── 3. Enable required APIs ──────────────────────────────────────────────────
echo "==> Enabling Cloud Storage API..."
gcloud services enable storage.googleapis.com --project="$PROJECT_ID" --quiet

# ── 4. Create state bucket (if it doesn't exist) ─────────────────────────────
if gcloud storage buckets describe "gs://$BUCKET_NAME" &>/dev/null; then
  echo "==> Bucket gs://$BUCKET_NAME already exists, skipping creation"
else
  echo "==> Creating bucket gs://$BUCKET_NAME ..."
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi

# ── 5. Enable versioning (protects against accidental state overwrites) ──────
echo "==> Enabling object versioning on bucket..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

# ── 6. Login Pulumi to the GCS backend ───────────────────────────────────────
echo "==> Logging Pulumi into gs://$BUCKET_NAME ..."
pulumi login "gs://$BUCKET_NAME"

# ── 7. Optionally init a stack ────────────────────────────────────────────────
if [[ -n "$STACK" ]]; then
  echo "==> Initializing stack: $STACK ..."
  pulumi stack init "$STACK" 2>/dev/null || pulumi stack select "$STACK"
fi

echo ""
echo "Done. Project $PROJECT_ID is ready."
echo ""
echo "Next steps:"
[[ -z "$STACK" ]] && echo "  pulumi stack init <name>"
echo "  pulumi config set gcp:project $PROJECT_ID"
echo "  pulumi up"
