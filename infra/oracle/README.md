# Oracle Cloud Instance (nanoclaw)

ARM A1.Flex instance on Oracle Cloud Always Free tier.

| Spec | Value |
|------|-------|
| Shape | VM.Standard.A1.Flex |
| CPUs | 4 OCPU (ARM) |
| RAM | 24 GB |
| Disk | 200 GB |
| OS | Ubuntu 24.04 Minimal (aarch64) |
| Region | us-phoenix-1 |

## Quick Reference

```bash
# Connect (runs status check, drops into ~/workspace)
./infra/oracle/connect-nanoclaw.sh

# Or SSH directly
ssh ubuntu@$(cd infra/oracle && pulumi stack output publicIp)

# Status check on the instance
~/workspace/status.sh
```

## Provisioning a New Instance

### 1. Create a Pulumi stack

```bash
cd infra/oracle
pulumi stack init <stack-name>
```

### 2. Run setup

```bash
./setup.sh
```

This prompts for three values from the [OCI Console](https://cloud.oracle.com):
- **Tenancy OCID** — Profile > Tenancy > Copy OCID
- **User OCID** — Profile > My profile > Copy OCID
- **Region** — shown in top bar (e.g. `us-phoenix-1`)

It generates an API signing key and stores everything in Pulumi stack config.
The only manual step is pasting the public key into OCI Console (prompted during setup).

### 3. Deploy

```bash
pulumi up
```

If ARM capacity is unavailable (common on free tier), use the retry script:

```bash
nohup ./retry.sh &    # retries every 5 min for 24 hours
tail -f retry.log     # monitor progress
```

### 4. Post-deploy setup

Cloud-init automatically installs: Docker, Node.js 20, Claude Code CLI, git, tmux, htop, stress-ng, UFW, fail2ban, 4GB swap, anti-idle cron, and `~/workspace/status.sh`.

After cloud-init completes (~2 min), SSH in and finish setup:

```bash
./connect-nanoclaw.sh

# Authenticate Claude Code (device-code flow, no browser needed)
claude auth login

# Clone and setup nanoclaw
cd ~/workspace
git clone https://github.com/qwibitai/nanoclaw.git
cd nanoclaw
claude    # then type: /setup

# Enable nanoclaw as a systemd service
sudo tee /etc/systemd/system/nanoclaw.service > /dev/null << 'EOF'
[Unit]
Description=Nanoclaw AI Assistant
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/workspace/nanoclaw
ExecStart=/usr/bin/node dist/index.js
Restart=always
RestartSec=5
EnvironmentFile=/home/ubuntu/workspace/nanoclaw/.env

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable nanoclaw
sudo systemctl start nanoclaw
```

## Destroying

```bash
pulumi destroy    # tears down all OCI resources
pulumi stack rm   # removes the stack
```

## Managing the Instance

### Nanoclaw service

```bash
sudo systemctl status nanoclaw    # check status
sudo systemctl restart nanoclaw   # restart
journalctl -u nanoclaw -f         # live logs
```

### Free tier limits

| Resource | Free Cap | This Instance |
|----------|----------|---------------|
| OCPU-hours/month | 3,000 | 2,976 (4 OCPU x 744 hrs) |
| GB-hours/month | 18,000 | 17,856 (24 GB x 744 hrs) |
| Boot volume | 200 GB total | 200 GB |

Pay-as-you-go account required for full ARM allocation. Stays free within limits.

### Idle reclamation

OCI reclaims free-tier instances idle for 7 consecutive days (CPU < 20%, Network < 20%, Memory < 20% — all three must be below threshold). Cloud-init sets up a stress-ng cron job that spikes CPU every 5 minutes to prevent this.

### Firewall rules

Managed at two levels:
- **OCI Security List** — defined in `network.ts` (SSH, HTTP, HTTPS, ICMP)
- **UFW on instance** — same ports, configured by cloud-init

To open a new port (e.g. 8080):
```bash
# On instance
sudo ufw allow 8080/tcp

# Then add to network.ts ingressSecurityRules and run: pulumi up
```

## File Layout

```
infra/oracle/
  Pulumi.yaml            # Project definition
  Pulumi.*.yaml          # Per-stack config (encrypted secrets)
  provider.ts            # OCI provider (reads from Pulumi config)
  config.ts              # Instance shape, SSH key, availability domain
  network.ts             # VCN, subnet, security list, IGW, routes
  compute.ts             # Instance + image lookup + cloud-init
  index.ts               # Stack outputs (publicIp, sshCommand, etc.)
  cloud-init.sh          # Bootstrap: Docker, Node, Claude Code, firewall, swap, anti-idle, status.sh
  setup.sh               # Interactive setup for new stacks
  retry.sh               # Retry loop for capacity-constrained regions
  connect-nanoclaw.sh    # SSH connect with status dashboard
```
