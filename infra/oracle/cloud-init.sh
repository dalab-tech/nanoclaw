#!/bin/bash
set -euo pipefail

# Wait for unattended-upgrades to release apt lock (common on first boot)
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# Detect OS user
if id ubuntu &>/dev/null; then USER_NAME=ubuntu; else USER_NAME=opc; fi
USER_HOME=$(eval echo ~$USER_NAME)

# Detect package manager (Oracle Linux = dnf, Ubuntu = apt)
if command -v dnf &>/dev/null; then
  # --- Docker CE (Oracle Linux) ---
  dnf install -y dnf-utils
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  usermod -aG docker $USER_NAME

  # --- Node.js 20 LTS ---
  curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
  dnf install -y nodejs

  # --- Essential tools ---
  dnf install -y git tmux htop unzip cron stress-ng

  # --- Firewall (firewalld on Oracle Linux) ---
  firewall-cmd --permanent --add-service=ssh
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --reload
else
  # --- Docker CE (Ubuntu) ---
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  ARCH=$(dpkg --print-architecture)
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  usermod -aG docker $USER_NAME

  # --- Node.js 20 LTS ---
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs

  # --- Essential tools ---
  apt-get install -y git tmux htop unzip cron stress-ng

  # --- UFW firewall ---
  apt-get install -y ufw
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable

  # --- Fail2ban ---
  apt-get install -y fail2ban
  systemctl enable fail2ban
  systemctl start fail2ban
fi

# --- Swap ---
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# --- Claude Code CLI ---
npm install -g @anthropic-ai/claude-code

# --- Users ---
# son: human admin for managing nanoclaw and the instance
# anton: bot user for autonomous GitHub engineering tasks
for NEW_USER in son anton; do
  useradd -m -s /bin/bash "$NEW_USER"
  usermod -aG docker "$NEW_USER"
  echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
  chmod 440 "/etc/sudoers.d/$NEW_USER"
  # Copy SSH authorized keys from default OS user
  mkdir -p "/home/$NEW_USER/.ssh"
  cp "$USER_HOME/.ssh/authorized_keys" "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 700 "/home/$NEW_USER/.ssh"
  chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  # Workspace
  mkdir -p "/home/$NEW_USER/workspace"
  chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/workspace"
done

# anton-specific: state directory for GitHub task tracking
mkdir -p /home/anton/.anton
chown anton:anton /home/anton/.anton

# --- Anti-idle cron (prevents OCI free-tier reclamation) ---
systemctl enable cron 2>/dev/null || true
systemctl start cron 2>/dev/null || true
su - $USER_NAME -c '(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/stress-ng --cpu 2 --timeout 90s > /dev/null 2>&1") | crontab -'

# --- Status script (available to all users) ---
cat > /usr/local/bin/status << 'STATUS'
#!/bin/bash
G="\033[0;32m" R="\033[0;31m" Y="\033[1;33m" C="\033[0;36m" N="\033[0m"
ok() { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}!${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

echo -e "${C}nanoclaw status${N}"

# Check nanoclaw services (template instances like nanoclaw@anton)
NCLAW_SERVICES=$(systemctl list-units --type=service --state=running --no-legend 'nanoclaw@*' 2>/dev/null | awk '{print $1}')
if [ -n "$NCLAW_SERVICES" ]; then
  for SVC in $NCLAW_SERVICES; do
    PERSONA=$(echo "$SVC" | sed 's/nanoclaw@\(.*\)\.service/\1/')
    PID=$(systemctl show -p MainPID "$SVC" --value)
    UPTIME=$(ps -o etime= -p "$PID" 2>/dev/null | xargs)
    ok "$SVC running (pid $PID, uptime $UPTIME)"
  done
else
  warn "no nanoclaw services running"
fi

if systemctl is-active --quiet docker 2>/dev/null; then
  AGENT_COUNT=$(docker ps --filter "name=nanoclaw-" --format '{{.Names}}' 2>/dev/null | wc -l)
  ok "docker running ($AGENT_COUNT agent containers)"
else
  fail "docker not running"
fi

if su - anton -c "claude auth status" 2>&1 | grep -q '"loggedIn": true'; then
  ok "claude authenticated (anton)"
else
  warn "claude not authenticated (anton) — run: sudo su - anton -c 'claude auth login'"
fi

if sudo crontab -l -u ubuntu 2>/dev/null | grep -q stress-ng; then
  ok "anti-idle cron active"
else
  warn "anti-idle cron missing"
fi

echo -e "\n${C}reclamation risk${N} (safe if any metric >=20%)"
CPU_USED=$(top -bn2 -d0.5 | grep '%Cpu' | tail -1 | awk '{printf "%.0f", 100 - $8}')
MEM_PCT=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
if [ "$CPU_USED" -ge 20 ]; then ok "cpu: ${CPU_USED}%"; else warn "cpu: ${CPU_USED}% (<20%) — normal between stress-ng bursts"; fi
if [ "$MEM_PCT" -ge 20 ]; then ok "mem: ${MEM_PCT}%"; else warn "mem: ${MEM_PCT}% (<20%)"; fi

MEM=$(free -h | awk '/Mem:/{printf "%s/%s", $3, $2}')
DISK=$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')
LOAD=$(uptime | awk -F"load average: " '{print $2}')
echo -e "\n${C}resources${N}"
echo "  mem: $MEM  disk: $DISK  load: $LOAD"
echo ""
STATUS
chmod +x /usr/local/bin/status

# --- GitHub deploy key + repo clone (appended by Pulumi) ---

echo "=== cloud-init complete ==="
