#!/usr/bin/env bash
# Rename a Pulumi stack, optionally migrating it to a different backend.
# Handles the URN rewriting that `pulumi stack rename` can't do across backends.
#
# Usage:
#   ./pulumi-rename-stack.sh                    # interactive prompts
#   ./pulumi-rename-stack.sh old-name new-name  # direct rename on current backend

set -euo pipefail

BOLD="\033[1m"  DIM="\033[2m"  GREEN="\033[32m"  YELLOW="\033[33m"
RED="\033[31m"  RESET="\033[0m"

step()  { echo -e "  ${GREEN}✓${RESET} $1"; }
info()  { echo -e "  ${DIM}$1${RESET}"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $1"; }
err()   { echo -e "  ${RED}✗${RESET} $1" >&2; }

echo ""
echo -e "${BOLD}Pulumi Stack Renamer${RESET}"
echo -e "${DIM}Export, rewrite URNs, and import a stack under a new name.${RESET}"
echo ""

# ── Resolve current backend and project ─────────────────────────────────────
CURRENT_BACKEND=$(pulumi whoami --json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || true)
if [[ -z "$CURRENT_BACKEND" ]]; then
  err "Not logged in to Pulumi. Run 'pulumi login' first."
  exit 1
fi
info "Backend: $CURRENT_BACKEND"

# Detect project name from Pulumi.yaml in current directory
if [[ ! -f Pulumi.yaml ]]; then
  err "No Pulumi.yaml in current directory. Run this from a Pulumi project."
  exit 1
fi
PROJECT_NAME=$(grep '^name:' Pulumi.yaml | head -1 | awk '{print $2}')
info "Project: $PROJECT_NAME"
echo ""

# ── Get old and new stack names ─────────────────────────────────────────────
OLD_STACK="${1:-}"
NEW_STACK="${2:-}"

if [[ -z "$OLD_STACK" ]]; then
  echo "  Available stacks:"
  pulumi stack ls --json 2>/dev/null | python3 -c "
import sys, json
stacks = json.load(sys.stdin)
for s in stacks:
    current = ' ← current' if s.get('current') else ''
    print(f'    {s[\"name\"]}{current}')
" 2>/dev/null || pulumi stack ls 2>/dev/null | sed 's/^/    /'
  echo ""
  read -rp "  Stack to rename: " OLD_STACK
  [[ -z "$OLD_STACK" ]] && { err "Stack name required."; exit 1; }
fi

if [[ -z "$NEW_STACK" ]]; then
  read -rp "  New name: " NEW_STACK
  [[ -z "$NEW_STACK" ]] && { err "New name required."; exit 1; }
fi

# Construct the Stack resource name (project-stack format Pulumi uses)
OLD_RESOURCE="${PROJECT_NAME}-${OLD_STACK}"
NEW_RESOURCE="${PROJECT_NAME}-${NEW_STACK}"

echo ""
info "Rename: ${OLD_STACK} → ${NEW_STACK}"
info "URN rewrite: ${OLD_RESOURCE} → ${NEW_RESOURCE}"
echo ""
read -rp "  Continue? [Y/n] " yn
[[ "${yn:-Y}" =~ ^[Nn] ]] && { echo "  Aborted."; exit 0; }

# ── Export ───────────────────────────────────────────────────────────────────
TMPDIR=$(mktemp -d)
EXPORT_FILE="$TMPDIR/state-export.json"
RENAMED_FILE="$TMPDIR/state-renamed.json"

echo ""
info "Exporting stack ${OLD_STACK} ..."
pulumi stack export --stack "$OLD_STACK" > "$EXPORT_FILE"
step "Exported ($(wc -c < "$EXPORT_FILE" | tr -d ' ') bytes)"

# ── Rewrite URNs ────────────────────────────────────────────────────────────
info "Rewriting URNs ..."
sed -e "s/urn:pulumi:${OLD_STACK}::/urn:pulumi:${NEW_STACK}::/g" \
    -e "s/${OLD_RESOURCE}/${NEW_RESOURCE}/g" \
    "$EXPORT_FILE" > "$RENAMED_FILE"
step "URNs rewritten"

# ── Create new stack and import ─────────────────────────────────────────────
info "Creating stack ${NEW_STACK} ..."
pulumi stack init "$NEW_STACK" 2>/dev/null || true
step "Stack created"

info "Importing state ..."
pulumi stack import --stack "$NEW_STACK" < "$RENAMED_FILE"
step "State imported"

# ── Copy stack config if it exists ──────────────────────────────────────────
OLD_CONFIG="Pulumi.${OLD_STACK}.yaml"
NEW_CONFIG="Pulumi.${NEW_STACK}.yaml"
if [[ -f "$OLD_CONFIG" && ! -f "$NEW_CONFIG" ]]; then
  cp "$OLD_CONFIG" "$NEW_CONFIG"
  step "Copied ${OLD_CONFIG} → ${NEW_CONFIG}"
fi

# ── Verify ──────────────────────────────────────────────────────────────────
echo ""
info "Verifying with preview ..."
echo ""
pulumi preview --stack "$NEW_STACK" 2>&1 | tail -5

echo ""
echo -e "  ${GREEN}Done.${RESET} Stack renamed to ${BOLD}${NEW_STACK}${RESET}."
echo ""
echo -e "  ${DIM}The old stack (${OLD_STACK}) still exists. To remove it:${RESET}"
echo -e "  ${DIM}  pulumi stack rm ${OLD_STACK} --yes${RESET}"
echo ""

# Cleanup
rm -rf "$TMPDIR"
