#!/bin/bash
# Usage: ./connect-nanoclaw.sh [user]
#   son   — human admin (default)
#   anton — bot user
IP=$(cd "$(dirname "$0")" && pulumi stack output publicIp)
USER=${1:-son}

# Pre-flight checks (run as the target user)
ssh -q "$USER@$IP" 'status 2>/dev/null || true'

# Change terminal background to light mode to indicate SSH session
printf '\033]11;#fff8e7\007'
printf '\033]10;#1a1a1a\007'

# Reset background on exit (normal exit, interrupt, or termination)
reset_bg() { printf '\033]11;#000000\007'; printf '\033]10;#ffffff\007'; }
trap reset_bg EXIT INT TERM

# Connect and navigate to workspace
ssh -t "$USER@$IP" "cd ~/workspace && exec \$SHELL -l"
