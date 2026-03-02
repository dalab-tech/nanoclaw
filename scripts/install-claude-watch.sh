#!/usr/bin/env bash
# claude-watch statusline for Claude Code
# Based on https://github.com/xleddyl/claude-watch (with dalab customizations)
#
# Usage:
#   bash install-claude-watch.sh            # install
#   bash install-claude-watch.sh --remove   # uninstall

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if ! command -v jq &>/dev/null; then
  printf "jq is required but not installed. Install it now? [y/N] "
  read -r answer
  case "$answer" in
    [yY]*)
      if command -v brew &>/dev/null; then
        brew install jq
      elif command -v apt-get &>/dev/null; then
        sudo apt-get install -y jq
      else
        echo "Error: Could not detect package manager. Install jq manually and re-run."
        exit 1
      fi
      ;;
    *) echo "Aborted."; exit 1 ;;
  esac
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
cat <<'BANNER'
claude-watch — minimal statusline for Claude Code
https://github.com/xleddyl/claude-watch

This will:
  1. Write 2 shell scripts to ~/.claude/
  2. Add statusLine + hooks config to ~/.claude/settings.json

Your statusline will look like this:

  dalab/anton • main
  opus 4.6 • 5h 42% • 7d 18% | ctx 19% (38k/200k)

To remove later: bash install-claude-watch.sh --remove
BANNER

printf "\nProceed? [y/N] "
read -r answer
case "$answer" in
  [yY]*) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo ""
echo "Installing claude-watch..."

mkdir -p "$CLAUDE_DIR"

# --- Write fetch-usage.sh ---
cat > "$CLAUDE_DIR/fetch-usage.sh" <<'FETCH_SCRIPT'
#!/bin/sh
# Fetches Claude API usage stats and writes them to /tmp/.claude_usage_cache.
# Line 1: five_hour.utilization (integer %)
# Line 2: seven_day.utilization (integer %)
# Line 3: five_hour.resets_at (raw ISO string, e.g. 2026-02-26T12:59:59.997656+00:00)
# Line 4: seven_day.resets_at (raw ISO string)
# All output is suppressed; meant to be run in background.

CACHE_FILE="/tmp/.claude_usage_cache"
TOKEN_CACHE="/tmp/.claude_token_cache"
CREDS_FILE="$HOME/.claude/.credentials.json"
TOKEN_TTL=900  # 15 minutes

# --- get token (with 15-min cache to avoid repeated credential reads) ---
token=""
if [ -f "$TOKEN_CACHE" ]; then
  cache_age=$(( $(date -u +%s) - $(stat -f %m "$TOKEN_CACHE" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$TOKEN_TTL" ]; then
    token=$(cat "$TOKEN_CACHE" 2>/dev/null)
  fi
fi

if [ -z "$token" ]; then
  if [ ! -f "$CREDS_FILE" ]; then
    exit 0
  fi
  token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS_FILE" 2>/dev/null)
  if [ -z "$token" ]; then
    exit 0
  fi
  printf '%s' "$token" > "$TOKEN_CACHE"
fi

usage_json=$(curl -s -m 3 \
  -H "accept: application/json" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "authorization: Bearer $token" \
  -H "user-agent: claude-code/2.1.11" \
  "https://api.anthropic.com/oauth/usage" 2>/dev/null)

if [ -z "$usage_json" ]; then
  exit 0
fi

five_h_raw=$(printf '%s' "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
seven_d_raw=$(printf '%s' "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
five_h_reset=$(printf '%s' "$usage_json" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
seven_d_reset=$(printf '%s' "$usage_json" | jq -r '.seven_day.resets_at // ""' 2>/dev/null)

if [ -n "$five_h_raw" ] && [ -n "$seven_d_raw" ]; then
  five_h=$(printf "%.0f" "$five_h_raw")
  seven_d=$(printf "%.0f" "$seven_d_raw")
  printf '%s\n%s\n%s\n%s\n' "$five_h" "$seven_d" "$five_h_reset" "$seven_d_reset" > "$CACHE_FILE"
fi
FETCH_SCRIPT

# --- Write statusline-command.sh ---
cat > "$CLAUDE_DIR/statusline-command.sh" <<'STATUS_SCRIPT'
#!/bin/sh
input=$(cat)

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // ""' | tr '[:upper:]' '[:lower:]')

# --- folder ---
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# show path relative to repo root (like starship)
repo_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$repo_root" ]; then
  repo_name=$(basename "$repo_root")
  subdir="${dir#"$repo_root"}"
  dir_name="${repo_name}${subdir}"
else
  dir_name=$(basename "$dir")
fi

# --- git branch ---
branch=""
if [ -d "${dir}/.git" ] || git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)
fi

# --- usage stats (5h / 7d) from cache ---
CACHE_FILE="/tmp/.claude_usage_cache"
five_h=""
seven_d=""
five_h_reset=""
seven_d_reset=""

if [ -f "$CACHE_FILE" ]; then
  five_h=$(sed -n '1p' "$CACHE_FILE")
  seven_d=$(sed -n '2p' "$CACHE_FILE")
  five_h_reset=$(sed -n '3p' "$CACHE_FILE")
  seven_d_reset=$(sed -n '4p' "$CACHE_FILE")
else
  bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &
fi

# --- compute_delta: given a raw ISO timestamp, returns human-readable time until reset ---
compute_delta() {
  clean=$(echo "$1" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
  reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null)
  if [ -z "$reset_epoch" ]; then return; fi
  now_epoch=$(date -u "+%s")
  diff=$(( reset_epoch - now_epoch ))
  if [ "$diff" -le 0 ]; then echo "now"; return; fi
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# --- context window ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
ctx_tokens_str=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_str="${used_int}%"
  ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty' 2>/dev/null)
  ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ]; then
    ctx_used_k=$(( ctx_used / 1000 ))
    ctx_total_k=$(( ctx_total / 1000 ))
    ctx_tokens_str="${ctx_used_k}k/${ctx_total_k}k"
  fi
fi

# --- assemble output ---
SEP="\033[90m • \033[0m"

# line 1: folder • branch
printf "\033[1m\033[38;2;76;208;222m%s\033[22m\033[0m" "$dir_name"
if [ -n "$branch" ]; then
  printf "%b" "$SEP"
  printf "\033[1m\033[38;2;192;103;222m%s\033[22m\033[0m" "$branch"
fi

# line 2: model | usage | ctx
printf "\n"
printf "\033[38;5;208m%s\033[0m" "$model"
if [ -n "$five_h" ]; then
  printf "%b" "$SEP"
  printf "\033[38;2;156;162;175m5h %s%%\033[0m" "$five_h"
  if [ -n "$five_h_reset" ]; then
    delta=$(compute_delta "$five_h_reset")
    [ -n "$delta" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$delta"
  fi
fi
if [ -n "$seven_d" ]; then
  printf "%b" "$SEP"
  printf "\033[38;2;156;162;175m7d %s%%\033[0m" "$seven_d"
  if [ -n "$seven_d_reset" ]; then
    delta=$(compute_delta "$seven_d_reset")
    [ -n "$delta" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$delta"
  fi
fi
if [ -n "$ctx_str" ]; then
  printf "\033[90m | \033[0m"
  printf "\033[38;2;156;162;175mctx %s\033[0m" "$ctx_str"
  [ -n "$ctx_tokens_str" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$ctx_tokens_str"
fi
STATUS_SCRIPT

chmod +x "$CLAUDE_DIR/fetch-usage.sh" "$CLAUDE_DIR/statusline-command.sh"
echo "  Wrote scripts to $CLAUDE_DIR/"

# --- Merge config into settings.json ---
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
