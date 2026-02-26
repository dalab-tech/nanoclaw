#!/bin/bash
set -euo pipefail

# Wait for unattended-upgrades to release apt lock (common on first boot)
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do sleep 5; done
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do sleep 5; done

# Detect OS user
if id ubuntu &>/dev/null; then USER_NAME=ubuntu; else USER_NAME=root; fi
USER_HOME=$(eval echo ~$USER_NAME)

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

# --- Node.js 22 LTS ---
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# --- Essential tools ---
apt-get install -y git tmux htop unzip sqlite3 jq vim-tiny mc

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

# --- Swap ---
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# --- Claude Code CLI (native binary, auto-updates) ---
curl -fsSL https://claude.ai/install.sh | bash

# --- Users ---
# son: human admin for managing nanoclaw and the instance
# anton: bot user for autonomous GitHub engineering tasks
for NEW_USER in son anton; do
  useradd -m -s /bin/bash "$NEW_USER"
  usermod -aG docker,systemd-journal "$NEW_USER"
  echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
  chmod 440 "/etc/sudoers.d/$NEW_USER"
  # Copy SSH authorized keys from default OS user
  mkdir -p "/home/$NEW_USER/.ssh"
  if [ -f "$USER_HOME/.ssh/authorized_keys" ]; then
    cp "$USER_HOME/.ssh/authorized_keys" "/home/$NEW_USER/.ssh/authorized_keys"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  fi
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 700 "/home/$NEW_USER/.ssh"
  # Workspace
  mkdir -p "/home/$NEW_USER/workspace"
  chown "$NEW_USER:$NEW_USER" "/home/$NEW_USER/workspace"
  # SSH key for GitHub
  su - "$NEW_USER" -c "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C '${NEW_USER}@nanoclaw'"
done

# --- Midnight Commander warm skin + config ---
cat > /usr/share/mc/skins/warm256.ini << 'MCSKIN'
[skin]
    description = Warm cream/brown skin using 256 colors
    256colors = true
[Lines]
    horiz = ─
    vert = │
    lefttop = ┌
    righttop = ┐
    leftbottom = └
    rightbottom = ┘
    topmiddle = ┬
    bottommiddle = ┴
    leftmiddle = ├
    rightmiddle = ┤
    cross = ┼
    dhoriz = ─
    dvert = │
    dlefttop = ┌
    drighttop = ┐
    dleftbottom = └
    drightbottom = ┘
    dtopmiddle = ┬
    dbottommiddle = ┴
    dleftmiddle = ├
    drightmiddle = ┤
[core]
    _default_ = rgb200;rgb554
    selected = ;rgb542
    marked = rgb400;;italic
    markselect = rgb400;rgb542;italic
    gauge = ;rgb542
    input = ;rgb542
    inputunchanged = gray;rgb542
    inputmark = rgb542;gray
    disabled = gray;rgb543
    reverse = ;rgb542
    commandlinemark = white;gray
    header = rgb300;;italic
    shadow = rgb100;rgb321
[dialog]
    _default_ = rgb200;rgb543
    dfocus = ;rgb542
    dhotnormal = ;;underline
    dhotfocus = ;rgb542;underline
    dtitle = ;;italic+underline
[error]
    _default_ = rgb554;rgb400;bold
    errdfocus = rgb000;rgb542;bold
    errdhotnormal = ;;bold+underline
    errdhotfocus = rgb000;rgb542;bold+underline
    errdtitle = ;;bold+italic+underline
[filehighlight]
    directory = rgb203
    executable = rgb420
    symlink = rgb302
    hardlink =
    stalelink = rgb404
    device = rgb231
    special = rgb331
    core = rgb430
    temp = gray15
    archive = rgb013
    doc = rgb203
    source = rgb310
    media = rgb024
    graph = rgb033
    database = rgb421
[menu]
    _default_ = rgb200;rgb542;italic
    menusel = ;rgb531
    menuhot = ;;italic+underline
    menuhotsel = ;rgb531;italic+underline
    menuinactive =
[popupmenu]
    _default_ = rgb200;rgb543
    menusel = ;rgb542;underline
    menutitle = ;;italic+underline
[buttonbar]
    hotkey = rgb200;rgb554;italic
    button = rgb200;rgb542;italic
[statusbar]
    _default_ = rgb200;rgb542;italic
[help]
    _default_ = rgb200;rgb543
    helpitalic = rgb420;;italic
    helpbold = rgb400;;bold
    helplink = rgb203;;underline
    helpslink = rgb203;;reverse
    helptitle = ;;underline
[editor]
    _default_ = rgb200;rgb554
    editbold = rgb400
    editmarked = ;rgb542;italic
    editwhitespace = rgb400;rgb543
    editlinestate = ;rgb543
    bookmark = ;rgb531
    bookmarkfound = ;rgb530
    editrightmargin = rgb400;rgb543
    editframe = rgb420;
    editframeactive = rgb200;
    editframedrag = rgb400;
[viewer]
    _default_ = rgb200;rgb554
    viewbold = rgb000;;bold
    viewunderline = ;;underline
    viewselected = rgb400;rgb542
[diffviewer]
    added = ;rgb540
    changedline = rgb203;rgb543
    changednew = rgb400;rgb543
    changed = ;rgb543
    removed = ;rgb511
    error = rgb554;rgb400
[widget-panel]
    sort-up-char = ↑
    sort-down-char = ↓
    hiddenfiles-show-char = •
    hiddenfiles-hide-char = ○
    history-prev-item-char = «
    history-next-item-char = »
    history-show-list-char = ^
    filename-scroll-left-char = «
    filename-scroll-right-char = »
[widget-scrollbar]
    first-vert-char = ↑
    last-vert-char = ↓
    first-horiz-char = «
    last-horiz-char = »
    current-char = ■
    background-char = ▒
[widget-editor]
    window-state-char = ↕
    window-close-char = ✕
MCSKIN

for NEW_USER in son anton; do
  mkdir -p "/home/$NEW_USER/.config/mc"
  echo -e "[Midnight-Commander]\nskin=warm256" > "/home/$NEW_USER/.config/mc/ini"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.config/mc"
done

# Per-user config shortcut: ~/.<user> with symlinks to nanoclaw config
for NEW_USER in son anton; do
  mkdir -p "/home/$NEW_USER/.$NEW_USER"
  ln -sf "/home/$NEW_USER/nanoclaw/.env" "/home/$NEW_USER/.$NEW_USER/.env"
  ln -sf "/home/$NEW_USER/.config/nanoclaw/mount-allowlist.json" "/home/$NEW_USER/.$NEW_USER/mount-allowlist.json"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.$NEW_USER"
  # Source GITHUB_TOKEN from nanoclaw .env so gh/git auth works automatically
  cat >> "/home/$NEW_USER/.profile" << 'PROFILE'

# Auto-export GITHUB_TOKEN from nanoclaw .env
if [ -f ~/nanoclaw/.env ]; then
  export GITHUB_TOKEN=$(grep -m1 '^GITHUB_TOKEN=' ~/nanoclaw/.env | cut -d= -f2-)
fi
PROFILE
done

# Enable lingering so systemd user services run without login
for NEW_USER in son anton; do
  loginctl enable-linger "$NEW_USER"
done

# --- Nanoclaw systemd service template ---
cat > /etc/systemd/system/nanoclaw@.service << 'UNIT'
[Unit]
Description=Nanoclaw (%i persona)
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=%i
WorkingDirectory=/home/%i/nanoclaw
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
EnvironmentFile=/home/%i/nanoclaw/.env

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload

# --- Status script (injected by Pulumi from infra/status.sh) ---
# __STATUS_SCRIPT_PLACEHOLDER__

# --- GitHub deploy key + repo clone (appended by Pulumi) ---

echo "=== cloud-init complete ==="
