#!/bin/bash
G="\033[0;32m" R="\033[0;31m" Y="\033[1;33m" C="\033[0;36m" D="\033[0;90m" N="\033[0m"
ok() { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}!${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

echo -e "${C}nanoclaw status${N}"

# Check nanoclaw services
NCLAW_RUNNING=$(systemctl list-units --type=service --state=running --no-legend 'nanoclaw@*' 2>/dev/null | awk '{print $1}')
NCLAW_FAILED=$(systemctl list-units --type=service --state=failed --no-legend 'nanoclaw@*' 2>/dev/null | awk '{print $1}')

if [ -z "$NCLAW_RUNNING" ] && [ -z "$NCLAW_FAILED" ]; then
  warn "no nanoclaw services running"
fi

for SVC in $NCLAW_RUNNING; do
  PERSONA=$(echo "$SVC" | sed 's/nanoclaw@\(.*\)\.service/\1/')
  PID=$(systemctl show -p MainPID "$SVC" --value)
  UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | xargs)
  ok "$SVC running (pid $PID, uptime $UPTIME)"

  # Read persona .env for live API checks
  ENV="/home/$PERSONA/nanoclaw/.env"
  ENV_DATA=$(sudo cat "$ENV" 2>/dev/null)

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
  WA_DIR="/home/$PERSONA/nanoclaw/store/auth"
  if [ -d "$WA_DIR" ] && [ "$(ls -A "$WA_DIR" 2>/dev/null)" ]; then
    WA_LIVE="${G}✓${N} auth creds present"
  else
    WA_LIVE="${Y}!${N} no auth creds"
  fi

  # Journal log secondary signal
  SVC_START=$(systemctl show -p ActiveEnterTimestamp "$SVC" --value 2>/dev/null)
  LOGS=$(sudo journalctl -u "$SVC" --since="$SVC_START" --no-pager --output=cat 2>/dev/null)

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
done

for SVC in $NCLAW_FAILED; do
  fail "$SVC failed"
done

if systemctl is-active --quiet docker 2>/dev/null; then
  AGENT_COUNT=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | wc -l)
  ok "docker running ($AGENT_COUNT agent containers)"
else
  fail "docker not running"
fi

if sudo -u anton bash -l -c "claude auth status" 2>&1 | grep -q '"loggedIn": true'; then
  ok "claude authenticated (anton)"
else
  warn "claude not authenticated (anton) — run: sudo -u anton bash -l -c 'claude auth login'"
fi

# Anti-idle cron (OCI free-tier; shows missing on GCP which is expected)
CRON_USER=""
for U in ubuntu opc; do id "$U" &>/dev/null && CRON_USER="$U" && break; done
if [ -n "$CRON_USER" ] && sudo crontab -l -u "$CRON_USER" 2>/dev/null | grep -q stress-ng; then
  ok "anti-idle cron active"
else
  warn "anti-idle cron missing"
fi

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
