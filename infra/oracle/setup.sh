#!/bin/bash
set -euo pipefail

# Oracle Cloud setup — stores ALL config in Pulumi stack (no ~/.oci/config needed).
#
# Usage:
#   ./setup.sh              # setup current stack
#   pulumi stack init foo   # create new stack for another account
#   ./setup.sh              # setup that stack

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${CYAN}→${NC} $1"; }

STACK=$(pulumi stack --show-name 2>/dev/null) || fail "No Pulumi stack selected. Run: pulumi stack init <name>"

echo "=== Oracle Cloud setup (stack: $STACK) ==="
echo ""
echo "Grab these from https://cloud.oracle.com :"
echo ""

info "Tenancy OCID → Profile icon (top-right) > Tenancy > Copy OCID"
read -rp "Tenancy OCID: " TENANCY_OCID
[ -z "$TENANCY_OCID" ] && fail "Tenancy OCID is required"

info "User OCID → Profile icon > My profile > Copy OCID"
read -rp "User OCID: " USER_OCID
[ -z "$USER_OCID" ] && fail "User OCID is required"

info "Region → shown in top bar (e.g. us-ashburn-1, us-phoenix-1)"
read -rp "Region: " REGION
[ -z "$REGION" ] && fail "Region is required"

# --- Generate API signing key ---
echo ""
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

KEY_FILE="$TMPDIR/api_key.pem"
PUB_KEY_FILE="$TMPDIR/api_key_public.pem"

openssl genrsa -out "$KEY_FILE" 2048 2>/dev/null
openssl rsa -pubout -in "$KEY_FILE" -out "$PUB_KEY_FILE" 2>/dev/null
FINGERPRINT=$(openssl rsa -pubout -outform DER -in "$KEY_FILE" 2>/dev/null | openssl md5 -c | awk '{print $2}')
pass "Generated API key (fingerprint: $FINGERPRINT)"

# --- Store in Pulumi stack config ---
pulumi config set oci:tenancyOcid "$TENANCY_OCID"
pulumi config set oci:userOcid "$USER_OCID"
pulumi config set oci:region "$REGION"
pulumi config set oci:fingerprint "$FINGERPRINT"
pulumi config set --secret oci:privateKey -- "$(cat "$KEY_FILE")"
pass "All credentials stored in Pulumi stack config"

# --- Upload public key (one manual step) ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}Upload this API public key to OCI Console:${NC}"
echo "  Profile icon > My profile > API keys > Add API key"
echo "  Select 'Paste a public key' and paste:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${CYAN}"
cat "$PUB_KEY_FILE"
echo -e "${NC}"
read -rp "Press Enter after uploading... "
pass "API key uploaded"

# --- SSH key ---
if [ -f ~/.ssh/id_ed25519.pub ] || [ -f ~/.ssh/id_rsa.pub ]; then
  pass "SSH public key found"
else
  echo ""
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
  pass "SSH key generated"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Deploy:   pulumi up"
echo "Connect:  \$(pulumi stack output sshCommand)"
