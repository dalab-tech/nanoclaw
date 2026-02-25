#!/bin/bash
# Usage: ./connect-nanoclaw.sh [user]
#   son   — human admin (default)
#   anton — bot user
IP=$(cd "$(dirname "$0")" && pulumi stack output publicIp)
USER=${1:-son}

# Pre-flight status check (timeout prevents hangs)
ssh -q -o ConnectTimeout=5 "$USER@$IP" 'timeout 10 status 2>/dev/null' || true

# Solarized Light theme to distinguish SSH from local terminal
printf '\033]11;#fdf6e3\007'
printf '\033]10;#073642\007'

# Reset to default on exit
reset_bg() { printf '\033]11;#282c34\007'; printf '\033]10;#ffffff\007'; }
trap reset_bg EXIT INT TERM

# Connect: open mc first, then drop to shell
ssh -t "$USER@$IP" "cd ~/workspace && mc; exec \$SHELL -l"
