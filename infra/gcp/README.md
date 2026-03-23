# GCP Instance (nanoclaw)

GCE instance on Google Cloud with IAP-only SSH access and GitHub Actions auto-deploy.

| Spec | Value |
|------|-------|
| Machine | e2-micro (free tier eligible) |
| CPUs | 0.25 shared vCPU (x86) |
| RAM | 1 GB |
| Disk | 20 GB pd-standard |
| OS | Ubuntu 24.04 LTS (amd64) |
| Region | us-central1-a |

## Quick Reference

```bash
# SSH via IAP (OS Login handles auth)
gcloud compute ssh nanoclaw-vm --zone=us-central1-a --tunnel-through-iap

# Remote diagnostics
sup             # live logs (default: gcp)
sup --snap      # quick status snapshot
sup oci         # live logs on OCI instead
```

## Provisioning

### 1. Create stack and configure

```bash
cd infra/gcp
pulumi stack init prod

# Required
pulumi config set gcp:project <project-id>
pulumi config set nanoclaw:githubOwner dalab-tech
pulumi config set nanoclaw:githubRepo nanoclaw
pulumi config set nanoclaw:gitUserName Anton
pulumi config set nanoclaw:gitUserEmail anton@datech.lab
pulumi config set --secret github:antonNanoclawPAT <PAT>

# Optional (defaults shown)
pulumi config set gcp:region us-central1
pulumi config set nanoclaw:zone us-central1-a
pulumi config set nanoclaw:machineType e2-micro
pulumi config set nanoclaw:diskSizeGb 20
pulumi config set nanoclaw:diskType pd-standard
pulumi config set nanoclaw:deployUser anton
```

### 2. Deploy

```bash
pulumi up
```

Creates: VPC, subnet, IAP-only firewall, VM with OS Login, two service accounts (VM + CI/CD), Workload Identity Federation for GitHub Actions, deploy key, and GitHub environment variables.

### 3. Post-deploy setup

Cloud-init installs: Docker, Node.js 22, Claude Code CLI, git, sqlite3, tmux, htop, mc, GitHub CLI, UFW, fail2ban, 4GB swap, and the `status` command.

Two users are created:

| User | Purpose |
|------|---------|
| `son` | Human admin — SSH, sudo, instance management |
| `anton` | Bot persona — runs nanoclaw, deploy key, config at `~/.anton/` |

After cloud-init completes (~3 min):

```bash
gcloud compute ssh nanoclaw-vm --zone=us-central1-a --tunnel-through-iap

# Switch to anton
sudo su - anton

# Authenticate Claude Code
claude auth login

# Repo is auto-cloned to ~/nanoclaw via deploy key
cd ~/nanoclaw
claude    # then type: /setup

# Enable the service
sudo systemctl enable nanoclaw@anton
sudo systemctl start nanoclaw@anton
```

## CI/CD: Auto-Deploy on Push

Pushing to `main` triggers the GCP deploy job automatically. The workflow:

1. Authenticates via Workload Identity Federation (no stored credentials)
2. SSHes through IAP tunnel (instance-scoped `osAdminLogin`)
3. Runs `git pull`, `npm install`, `npm run build` as `anton`
4. Restarts `nanoclaw@anton` service

OCI deploy is manual-only via `workflow_dispatch` (target: `oci` or `both`).

### GitHub environment variables (set by Pulumi)

| Variable | Source |
|----------|--------|
| `GCP_PROJECT_ID` | `gcp:project` |
| `GCP_ZONE` | `nanoclaw:zone` |
| `WORKLOAD_IDENTITY_PROVIDER` | WIF pool/provider name |
| `CICD_SERVICE_ACCOUNT` | CI/CD SA email |
| `VM_INSTANCE_NAME` | GCE instance name |

## Security Model

- **No SSH from internet** — firewall allows port 22 only from IAP range (`35.235.240.0/20`)
- **OS Login** — SSH keys managed by Google identity, no static keys on the VM
- **Instance-scoped admin** — CI/CD SA has `osAdminLogin` on this VM only, not project-wide
- **WIF** — GitHub Actions authenticates via OIDC, tokens expire in minutes, scoped to `dalab-tech/nanoclaw`
- **VM SA** — minimal roles: `logging.logWriter` + `monitoring.metricWriter`

## Managing the Instance

```bash
sudo systemctl status nanoclaw@anton     # check status
sudo systemctl restart nanoclaw@anton    # restart
journalctl -u nanoclaw@anton -f          # live logs
status                                   # dashboard
```

## Destroying

```bash
pulumi destroy
pulumi stack rm
```

## File Layout

```
infra/gcp/
  Pulumi.yaml              Project definition
  Pulumi.prod.yaml         Stack config (encrypted secrets)
  config.ts                Region, zone, machine type, GitHub config
  apis.ts                  Enable GCP APIs
  network.ts               VPC, subnet, IAP-only firewall
  service-accounts.ts      VM SA + CI/CD SA with IAM roles
  workload-identity.ts     WIF pool/provider for GitHub OIDC
  github.ts                Deploy key (ED25519)
  github-environments.ts   Push WIF vars to GitHub environment
  compute.ts               GCE instance + cloud-init + instance IAM
  index.ts                 Stack outputs
```
