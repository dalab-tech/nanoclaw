#!/usr/bin/env bash
# Installs claude-watch (https://github.com/xleddyl/claude-watch)
# A minimal statusline for Claude Code showing model, branch, API usage, and context.
#
# Usage:
#   bash install-claude-watch.sh            # install
#   bash install-claude-watch.sh --remove   # uninstall

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
REPO_BASE="https://raw.githubusercontent.com/xleddyl/claude-watch/main"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install it first (brew install jq / apt install jq)."
  exit 1
fi

# --- Uninstall ---
if [ "${1:-}" = "--remove" ]; then
  echo "Removing claude-watch..."

  rm -f "$CLAUDE_DIR/fetch-usage.sh" "$CLAUDE_DIR/statusline-command.sh"
  echo "  Deleted scripts"

  rm -f /tmp/.claude_usage_cache /tmp/.claude_token_cache
  echo "  Cleared caches"

  if [ -f "$SETTINGS" ]; then
    jq 'del(.statusLine)
      | .hooks.PreToolUse |= (if . then map(select(.hooks | all(.command | contains("fetch-usage.sh") | not))) else . end)
      | .hooks.Stop |= (if . then map(select(.hooks | all(.command | contains("fetch-usage.sh") | not))) else . end)
      | if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
      | if .hooks == {} then del(.hooks) else . end' "$SETTINGS" > "$SETTINGS.tmp"
    mv "$SETTINGS.tmp" "$SETTINGS"
    echo "  Cleaned settings.json"
  fi

  echo "Done! Restart Claude Code."
  exit 0
fi

# --- Install ---
echo "Installing claude-watch..."

mkdir -p "$CLAUDE_DIR"

curl -fsSL "$REPO_BASE/fetch-usage.sh" -o "$CLAUDE_DIR/fetch-usage.sh"
curl -fsSL "$REPO_BASE/statusline-command.sh" -o "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/fetch-usage.sh" "$CLAUDE_DIR/statusline-command.sh"
echo "  Downloaded scripts to $CLAUDE_DIR/"

PATCH=$(cat <<'JSON'
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &"
          }
        ]
      }
    ]
  }
}
JSON
)

if [ -f "$SETTINGS" ]; then
  jq -s '.[0] * .[1]' "$SETTINGS" <(echo "$PATCH") > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
  echo "  Merged config into existing $SETTINGS"
else
  echo "$PATCH" | jq . > "$SETTINGS"
  echo "  Created $SETTINGS"
fi

bash "$CLAUDE_DIR/fetch-usage.sh" 2>/dev/null || true

echo "Done! Restart Claude Code to see the statusline."
