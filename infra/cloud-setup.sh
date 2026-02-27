#!/bin/bash
set -euo pipefail

# Wait for unattended-upgrades to release apt lock (needed when run standalone)
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# Detect OS user (ubuntu on GCP/OCI-Ubuntu, opc on Oracle Linux, root otherwise)
if id ubuntu &>/dev/null; then USER_NAME=ubuntu
elif id opc &>/dev/null; then USER_NAME=opc
else USER_NAME=root; fi
USER_HOME=$(eval echo ~$USER_NAME)

# Variables re-defined here so cloud-setup.sh works standalone (outside cloud-init)
ADMINS="son"
ALL_USERS="$ADMINS"

# Detect package manager (Oracle Linux = dnf, Ubuntu = apt)
if command -v dnf &>/dev/null; then
  # --- Docker CE (Oracle Linux) ---
  dnf install -y dnf-utils
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable docker
  systemctl start docker
  usermod -aG docker $USER_NAME

  # --- Node.js 22 LTS ---
  curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -
  dnf install -y nodejs

  # --- Essential tools ---
  dnf install -y git tmux htop unzip sqlite3 cron stress-ng mc jq vim-minimal make gcc-c++

  # --- GitHub CLI ---
  dnf install -y 'dnf-command(config-manager)'
  dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
  dnf install -y gh

  # --- Firewall (firewalld on Oracle Linux) ---
  firewall-cmd --permanent --add-service=ssh
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --reload

  # --- Fail2ban ---
  dnf install -y fail2ban || true
  systemctl enable fail2ban || true
  systemctl start fail2ban || true

  # --- Cloudflared ---
  dnf install -y cloudflared || {
    ARCH=$(uname -m | sed 's/aarch64/arm64/')
    rpm -i "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.rpm"
  }
else
  # --- Docker CE (Ubuntu) ---
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
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

  # --- Node.js 22 LTS ---
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs

  # --- Essential tools ---
  apt-get install -y git tmux htop unzip sqlite3 cron stress-ng mc jq vim-tiny build-essential

  # --- GitHub CLI ---
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get install -y gh

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

  # --- Cloudflared ---
  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$(dpkg --print-architecture).deb" -o /tmp/cloudflared.deb
  dpkg -i /tmp/cloudflared.deb
  rm -f /tmp/cloudflared.deb
fi

# --- Ghostty terminfo (so TERM=xterm-ghostty works over SSH) ---
cat <<'TERMINFO' | tic -x -
xterm-ghostty|ghostty|Ghostty,
	am, bce, ccc, hs, km, mc5i, mir, msgr, npc, xenl,
	colors#256, cols#80, it#8, lines#24, pairs#32767,
	acsc=++\,\,--..00``aaffgghhiijjkkllmmnnooppqqrrssttuuvvwwxxyyzz{{||}}~~,
	bel=^G, blink=\E[5m, bold=\E[1m, cbt=\E[Z, civis=\E[?25l,
	clear=\E[H\E[2J, cnorm=\E[?12l\E[?25h, cr=^M,
	csr=\E[%i%p1%d;%p2%dr, cub=\E[%p1%dD, cub1=^H,
	cud=\E[%p1%dB, cud1=^J, cuf=\E[%p1%dC, cuf1=\E[C,
	cup=\E[%i%p1%d;%p2%dH, cuu=\E[%p1%dA, cuu1=\E[A,
	cvvis=\E[?12;25h, dch=\E[%p1%dP, dch1=\E[P, dim=\E[2m,
	dl=\E[%p1%dM, dl1=\E[M, dsl=\E]2;\007, ech=\E[%p1%dX,
	ed=\E[J, el=\E[K, el1=\E[1K, flash=\E[?5h$<100/>\E[?5l,
	fsl=^G, home=\E[H, hpa=\E[%i%p1%dG, ht=^I, hts=\EH,
	ich=\E[%p1%d@, ich1=\E[@, il=\E[%p1%dL, il1=\E[L, ind=^J,
	indn=\E[%p1%dS,
	initc=\E]4;%p1%d;rgb\:%p2%{255}%*%{1000}%/%2.2X/%p3%{255}%*%{1000}%/%2.2X/%p4%{255}%*%{1000}%/%2.2X\E\\,
	invis=\E[8m, kDC=\E[3;2~, kEND=\E[1;2F, kHOM=\E[1;2H,
	kIC=\E[2;2~, kLFT=\E[1;2D, kNXT=\E[6;2~, kPRV=\E[5;2~,
	kRIT=\E[1;2C, kbs=\177, kcbt=\E[Z, kcub1=\EOD, kcud1=\EOB,
	kcuf1=\EOC, kcuu1=\EOA, kdch1=\E[3~, kend=\EOF, kent=\EOM,
	kf1=\EOP, kf10=\E[21~, kf11=\E[23~, kf12=\E[24~,
	kf13=\E[1;2P, kf14=\E[1;2Q, kf15=\E[1;2R, kf16=\E[1;2S,
	kf17=\E[15;2~, kf18=\E[17;2~, kf19=\E[18;2~, kf2=\EOQ,
	kf20=\E[19;2~, kf21=\E[20;2~, kf22=\E[21;2~,
	kf23=\E[23;2~, kf24=\E[24;2~, kf25=\E[1;5P, kf26=\E[1;5Q,
	kf27=\E[1;5R, kf28=\E[1;5S, kf29=\E[15;5~, kf3=\EOR,
	kf30=\E[17;5~, kf31=\E[18;5~, kf32=\E[19;5~,
	kf33=\E[20;5~, kf34=\E[21;5~, kf35=\E[23;5~,
	kf36=\E[24;5~, kf37=\E[1;6P, kf38=\E[1;6Q, kf39=\E[1;6R,
	kf4=\EOS, kf40=\E[1;6S, kf41=\E[15;6~, kf42=\E[17;6~,
	kf43=\E[18;6~, kf44=\E[19;6~, kf45=\E[20;6~,
	kf46=\E[21;6~, kf47=\E[23;6~, kf48=\E[24;6~,
	kf49=\E[1;3P, kf5=\E[15~, kf50=\E[1;3Q, kf51=\E[1;3R,
	kf52=\E[1;3S, kf53=\E[15;3~, kf54=\E[17;3~,
	kf55=\E[18;3~, kf56=\E[19;3~, kf57=\E[20;3~,
	kf58=\E[21;3~, kf59=\E[23;3~, kf6=\E[17~, kf60=\E[24;3~,
	kf61=\E[1;4P, kf62=\E[1;4Q, kf63=\E[1;4R, kf7=\E[18~,
	kf8=\E[19~, kf9=\E[20~, khome=\EOH, kich1=\E[2~,
	kind=\E[1;2B, kmous=\E[<, knp=\E[6~, kpp=\E[5~,
	kri=\E[1;2A, oc=\E]104\007, op=\E[39;49m, rc=\E8,
	rep=%p1%c\E[%p2%{1}%-%db, rev=\E[7m, ri=\EM,
	rin=\E[%p1%dT, ritm=\E[23m, rmacs=\E(B, rmam=\E[?7l,
	rmcup=\E[?1049l, rmir=\E[4l, rmkx=\E[?1l\E>, rmso=\E[27m,
	rmul=\E[24m, rs1=\E]\E\\\Ec, sc=\E7,
	setab=\E[%?%p1%{8}%<%t4%p1%d%e%p1%{16}%<%t10%p1%{8}%-%d%e48;5;%p1%d%;m,
	setaf=\E[%?%p1%{8}%<%t3%p1%d%e%p1%{16}%<%t9%p1%{8}%-%d%e38;5;%p1%d%;m,
	sgr=%?%p9%t\E(0%e\E(B%;\E[0%?%p6%t;1%;%?%p2%t;4%;%?%p1%p3%|%t;7%;%?%p4%t;5%;%?%p7%t;8%;m,
	sgr0=\E(B\E[m, sitm=\E[3m, smacs=\E(0, smam=\E[?7h,
	smcup=\E[?1049h, smir=\E[4h, smkx=\E[?1h\E=, smso=\E[7m,
	smul=\E[4m, tbc=\E[3g, tsl=\E]2;, u6=\E[%i%d;%dR, u7=\E[6n,
	u8=\E[?%[;0123456789]c, u9=\E[c, vpa=\E[%i%p1%dd,
TERMINFO

# --- ~/.local/bin on PATH (for Claude Code, status script, etc.) ---
cat > /etc/profile.d/local-bin.sh << 'LOCALBIN'
export PATH="$HOME/.local/bin:$PATH"
LOCALBIN

# --- User config (idempotent) ---
for NEW_USER in $ALL_USERS; do
  usermod -aG docker,systemd-journal "$NEW_USER"
  mkdir -p "/home/$NEW_USER/.config"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.config"
  loginctl enable-linger "$NEW_USER"
  # Claude Code CLI (native binary, auto-updates) — install per user
  su - "$NEW_USER" -c "curl -fsSL https://claude.ai/install.sh | bash" || true
done

# --- Sudo (admins only, idempotent — overwrites) ---
for ADMIN in $ADMINS; do
  echo "$ADMIN ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$ADMIN"
  chmod 440 "/etc/sudoers.d/$ADMIN"
done

# --- Cloudflare Tunnel service ---
mkdir -p /etc/cloudflared
cat > /etc/systemd/system/cloudflared.service << 'CFDUNIT'
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/cloudflared/token.env
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
CFDUNIT
systemctl daemon-reload
# Not enabled yet — token written by Pulumi appendage below

# --- Anti-idle cron (prevents OCI free-tier reclamation) ---
# Only activates on OCI instances; harmless no-op on GCP.
if id opc &>/dev/null || [ -f /etc/oracle-cloud-agent/agent.yml ]; then
  systemctl enable cron 2>/dev/null || true
  systemctl start cron 2>/dev/null || true
  su - $USER_NAME -c 'crontab -l 2>/dev/null | grep -q stress-ng || \
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/bin/stress-ng --cpu 2 --timeout 90s > /dev/null 2>&1") | crontab -'
fi

# --- Status script (injected by Pulumi from infra/status.sh) ---
# __STATUS_SCRIPT_PLACEHOLDER__
