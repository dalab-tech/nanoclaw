#!/bin/bash
G="\033[0;32m" R="\033[0;31m" Y="\033[1;33m" C="\033[0;36m" D="\033[0;90m" N="\033[0m"
ok() { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}!${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

# Ensure systemctl --user works even in non-login shells (SSH, cron, etc.)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

PERSONA=$(whoami)
NCLAW_DIR="$HOME/nanoclaw"

echo -e "${C}nanoclaw status${N} ($PERSONA)"

# ── Illegal state checks ───────────────────────────────────────

# System-level nanoclaw services should not exist in multi-tenant setup
SYS_SVCS=$(systemctl list-units --type=service --state=running,failed --no-legend 'nanoclaw@*' 2>/dev/null | awk '{print $1}')
if [ -n "$SYS_SVCS" ]; then
  for svc in $SYS_SVCS; do
    fail "ILLEGAL: system-level $svc detected — multi-tenant requires user-level services only"
  done
fi

# Multiple nanoclaw processes for this user
NCLAW_PIDS=$(pgrep -u "$PERSONA" -f 'node.*dist/index\.js' 2>/dev/null)
NCLAW_PID_COUNT=$(echo "$NCLAW_PIDS" | grep -c '[0-9]' 2>/dev/null || echo 0)
if [ "$NCLAW_PID_COUNT" -gt 1 ]; then
  fail "ILLEGAL: $NCLAW_PID_COUNT nanoclaw processes running (expected at most 1)"
  echo "$NCLAW_PIDS" | while read -r p; do fail "  pid $p: $(ps -o args= -p "$p" 2>/dev/null)"; done
fi

# Sudo access — tenant users shouldn't need it
if sudo -n true 2>/dev/null; then
  warn "$PERSONA has sudo access — not needed for nanoclaw, consider removing for tenant isolation"
fi

# ── Service ─────────────────────────────────────────────────────
if systemctl --user is-active nanoclaw >/dev/null 2>&1; then
  PID=$(systemctl --user show -p MainPID nanoclaw --value)
  UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | xargs)
  ok "nanoclaw running (pid $PID, uptime $UPTIME)"

  SVC_START=$(systemctl --user show -p ActiveEnterTimestamp nanoclaw --value 2>/dev/null)
  LOGS=$(journalctl --user -u nanoclaw --since="$SVC_START" --no-pager --output=cat 2>/dev/null)
  if [ -z "$LOGS" ]; then
    LOGS=$(tail -200 "$NCLAW_DIR/logs/nanoclaw.log" 2>/dev/null)
  fi

  # Channel checks from own .env (no sudo needed — it's our file)
  ENV_DATA=$(cat "$NCLAW_DIR/.env" 2>/dev/null)

  # Slack: live token check
  SLACK_TOKEN=$(echo "$ENV_DATA" | grep -m1 '^SLACK_BOT_TOKEN=' | cut -d= -f2-)
  if [ -n "$SLACK_TOKEN" ]; then
    RESP=$(curl -s -m5 -H "Authorization: Bearer $SLACK_TOKEN" https://slack.com/api/auth.test 2>/dev/null)
    if echo "$RESP" | jq -e '.ok == true' >/dev/null 2>&1; then
      TEAM=$(echo "$RESP" | jq -r '.team // "unknown"')
      SLACK_LIVE="${G}✓${N} token valid (${TEAM})"
    else
      SLACK_LIVE="${R}✗${N} token invalid"
    fi
  else
    SLACK_LIVE="${Y}!${N} not configured"
  fi

  # GitHub: live token check
  GH_TOKEN=$(echo "$ENV_DATA" | grep -m1 '^GITHUB_TOKEN=' | cut -d= -f2-)
  if [ -n "$GH_TOKEN" ]; then
    RESP=$(curl -sf -m5 -H "Authorization: token $GH_TOKEN" https://api.github.com/user 2>/dev/null)
    if [ -n "$RESP" ] && echo "$RESP" | jq -e '.login' >/dev/null 2>&1; then
      LOGIN=$(echo "$RESP" | jq -r '.login')
      GH_LIVE="${G}✓${N} token valid (${LOGIN})"
    else
      GH_LIVE="${R}✗${N} token invalid"
    fi
  else
    GH_LIVE="${Y}!${N} not configured"
  fi

  # WhatsApp: auth creds check
  WA_DIR="$NCLAW_DIR/store/auth"
  if [ -d "$WA_DIR" ] && [ "$(ls -A "$WA_DIR" 2>/dev/null)" ]; then
    WA_LIVE="${G}✓${N} auth creds present"
  else
    WA_LIVE="${Y}!${N} no auth creds"
  fi

  for CH in Slack GitHub WhatsApp; do
    case $CH in
      Slack)    LIVE="$SLACK_LIVE";  PAD="   " ;;
      GitHub)   LIVE="$GH_LIVE";     PAD="  " ;;
      WhatsApp) LIVE="$WA_LIVE";     PAD="" ;;
    esac
    if echo "$LOGS" | grep -q "$CH channel connected"; then JSIG="${D}· connected${N}"
    elif echo "$LOGS" | grep -q "$CH.*error"; then JSIG="${R}· error${N}"
    elif echo "$LOGS" | grep -q "$CH.*skipping"; then JSIG="${D}· skipping${N}"
    else JSIG=""; fi
    echo -e "    ${CH}:${PAD} ${LIVE} ${JSIG}"
  done

elif systemctl --user is-failed nanoclaw >/dev/null 2>&1; then
  fail "nanoclaw service failed"
else
  warn "nanoclaw service not running"
fi

# ── Docker ──────────────────────────────────────────────────────
ROOTLESS_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock"
if [ -S "$ROOTLESS_SOCK" ]; then
  AGENT_COUNT=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | wc -l)
  ok "docker (rootless) running ($AGENT_COUNT agent containers)"
elif systemctl is-active --quiet docker 2>/dev/null; then
  AGENT_COUNT=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | wc -l)
  warn "using system docker ($AGENT_COUNT containers) — rootless recommended for tenant isolation"
else
  fail "docker not available"
fi

# Cross-tenant container leak check
ENV_DATA=${ENV_DATA:-$(cat "$NCLAW_DIR/.env" 2>/dev/null)}
INSTANCE_ID=$(echo "$ENV_DATA" | grep -m1 '^INSTANCE_ID=' | cut -d= -f2-)
EXPECTED_PREFIX="nanoclaw-${INSTANCE_ID:-$PERSONA}"
FOREIGN=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | grep -v "^${EXPECTED_PREFIX}-" || true)
if [ -n "$FOREIGN" ]; then
  fail "ILLEGAL: containers with foreign prefix (possible cross-tenant leak):"
  echo "$FOREIGN" | while read -r c; do fail "  $c"; done
fi

# ── Cloudflare Tunnel ──────────────────────────────────────────
if command -v cloudflared >/dev/null 2>&1; then
  if systemctl is-active --quiet cloudflared 2>/dev/null; then
    ok "cloudflared tunnel active"
  elif systemctl is-enabled --quiet cloudflared 2>/dev/null; then
    fail "cloudflared enabled but not running"
  else
    warn "cloudflared installed but not configured"
  fi
fi

# ── Dependencies ───────────────────────────────────────────────
echo -e "\n${C}dependencies${N}"
for cmd in node npm git jq curl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd $(command $cmd --version 2>&1 | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1)"
  else
    fail "$cmd not installed"
  fi
done

if bash -l -c "command -v claude" >/dev/null 2>&1; then
  if bash -l -c "claude auth status" 2>&1 | grep -q '"loggedIn": true'; then
    ok "claude authenticated"
  else
    warn "claude installed but not authenticated — run: claude auth login"
  fi
else
  fail "claude not installed — run: curl -fsSL https://claude.ai/install.sh | sh"
fi

# ── Anti-idle (informational, no sudo) ──────────────────────────
if pgrep -x stress-ng >/dev/null 2>&1; then
  ok "anti-idle active (stress-ng running)"
elif crontab -l 2>/dev/null | grep -q stress-ng; then
  ok "anti-idle cron active"
else
  warn "anti-idle not detected (expected on OCI free-tier)"
fi

# ── Resources ───────────────────────────────────────────────────
echo -e "\n${C}reclamation risk${N} (safe if any metric >=20%)"
CPU_USED=$(top -bn2 -d0.5 | grep '%Cpu' | tail -1 | awk '{printf "%.0f", 100 - $8}')
MEM_PCT=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
if [ "$CPU_USED" -ge 20 ] 2>/dev/null; then ok "cpu: ${CPU_USED}%"; else warn "cpu: ${CPU_USED}% (<20%) — normal between stress-ng bursts"; fi
if [ "$MEM_PCT" -ge 20 ] 2>/dev/null; then ok "mem: ${MEM_PCT}%"; else warn "mem: ${MEM_PCT}% (<20%)"; fi

MEM=$(free -h | awk '/Mem:/{printf "%s/%s", $3, $2}')
DISK=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')
LOAD=$(uptime | awk -F"load average: " '{print $2}')
echo -e "\n${C}resources${N}"
echo "  mem: $MEM  disk: $DISK  load: $LOAD"
echo ""
