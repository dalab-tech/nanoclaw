#!/bin/bash
IP=$(cd "$(dirname "$0")" && pulumi stack output publicIp)

# Pre-flight checks before connecting
ssh -q ubuntu@"$IP" 'bash -s' <<'REMOTE'
G='\033[0;32m' R='\033[0;31m' Y='\033[1;33m' C='\033[0;36m' N='\033[0m'
ok() { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}!${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

echo -e "${C}nanoclaw status${N}"

# Nanoclaw host process (node dist/index.js — manages WhatsApp + spawns agent containers)
NCLAW_PIDS=$(pgrep -f "node.*nanoclaw/dist/index.js" 2>/dev/null)
NCLAW_COUNT=$(echo "$NCLAW_PIDS" | grep -c . 2>/dev/null || echo 0)
if [ "$NCLAW_COUNT" -eq 1 ]; then
  NCLAW_PID=$(echo "$NCLAW_PIDS" | head -1)
  NCLAW_UP=$(ps -o etime= -p "$NCLAW_PID" 2>/dev/null | xargs)
  ok "nanoclaw host running (pid $NCLAW_PID, uptime $NCLAW_UP)"
elif [ "$NCLAW_COUNT" -gt 1 ]; then
  fail "MULTIPLE nanoclaw hosts running ($NCLAW_COUNT) — WhatsApp conflicts! Kill extras: kill $NCLAW_PIDS"
else
  warn "nanoclaw host not running — cd ~/workspace/nanoclaw && node dist/index.js"
fi

# Docker + nanoclaw agent containers
if systemctl is-active --quiet docker 2>/dev/null; then
  AGENT_COUNT=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | wc -l)
  ok "docker running ($AGENT_COUNT nanoclaw agent containers)"
else
  fail "docker not running"
fi

# Claude Code auth
if claude auth status 2>&1 | grep -q '"loggedIn": true'; then
  ok "claude authenticated"
else
  warn "claude not authenticated — run: claude auth login"
fi

# Anti-idle cron
if crontab -l 2>/dev/null | grep -q stress-ng; then
  ok "anti-idle cron active"
else
  warn "anti-idle cron missing — installing..."
  (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/stress-ng --cpu 1 --timeout 30s > /dev/null 2>&1") | crontab -
  ok "anti-idle cron installed"
fi

# OCI reclamation risk (all 3 must be <20% for 7 days to reclaim)
echo -e "\n${C}reclamation risk${N} (safe if any metric ≥20%)"
CPU_IDLE=$(top -bn1 | grep '%Cpu' | awk '{print $8}')
CPU_USED=$(awk "BEGIN{printf \"%.0f\", 100 - $CPU_IDLE}")
MEM_PCT=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
NET_RX=$(cat /proc/net/dev | awk '/:/{rx+=$2} END{printf "%.0f", rx/1048576}')
if [ "$CPU_USED" -ge 20 ]; then ok "cpu: ${CPU_USED}%"; else warn "cpu: ${CPU_USED}% (<20%)"; fi
if [ "$MEM_PCT" -ge 20 ]; then ok "mem: ${MEM_PCT}%"; else warn "mem: ${MEM_PCT}% (<20%)"; fi

# System resources
MEM=$(free -h | awk '/Mem:/{printf "%s/%s", $3, $2}')
DISK=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')
LOAD=$(uptime | awk -F'load average: ' '{print $2}')
echo -e "\n${C}resources${N}"
echo "  mem: $MEM  disk: $DISK  load: $LOAD"
echo ""
REMOTE

# Change terminal background to light mode to indicate SSH session
printf '\033]11;#fff8e7\007'
printf '\033]10;#1a1a1a\007'

# Reset background on exit (normal exit, interrupt, or termination)
reset_bg() { printf '\033]11;#000000\007'; printf '\033]10;#ffffff\007'; }
trap reset_bg EXIT INT TERM

# Connect and navigate to workspace
ssh -t ubuntu@"$IP" "mkdir -p ~/workspace && cd ~/workspace && exec \$SHELL -l"
