# Infrastructure

Pulumi stacks and shared provisioning scripts for dalab's cloud instances.

## Layout

```
infra/
  gcp/                      Pulumi stack — GCE instance, network, IAM, WIF, GitHub integration
  oracle/                   Pulumi stack — OCI instance, network, GitHub integration
  cloudflare/               Pulumi stack — DNS zones, email routing, redirects
  cloud-init.sh             Shared cloud-init provisioning (used by GCP + OCI stacks)
  status.sh                 Instance health-check script (single source of truth)
  slack-app-manifest.json   Slack app config for Anton bot
```

## Stacks

Each stack (`gcp/`, `oracle/`, `cloudflare/`) is an independent Pulumi project with its own `Pulumi.yaml`, `package.json`, and `node_modules`. Run commands from within the stack directory:

```bash
cd infra/gcp && pulumi preview
cd infra/oracle && pulumi preview
cd infra/cloudflare && pulumi preview
```

See each stack's README for instance specs, quick reference, and stack-specific details.

## Shared Scripts

### cloud-init.sh

Base provisioning script shared by both compute stacks. Handles:

- OS detection (Ubuntu vs Oracle Linux) with dnf/apt branching
- Docker CE, Node.js 22 LTS, GitHub CLI, essential tools
- Firewall (UFW on Ubuntu, firewalld on Oracle Linux) and fail2ban
- Swap, Ghostty terminfo, Claude Code CLI
- User creation (admins + tenants) with SSH keys, Docker access, lingering
- Anti-idle cron (runtime-gated, only activates on OCI instances)
- Placeholder for status script injection and deploy key appendage

Both `gcp/compute.ts` and `oracle/compute.ts` read this file, inject the status script at the `__STATUS_SCRIPT_PLACEHOLDER__` marker, and append the deploy key section.

### status.sh

Instance health-check that reports on systemd services, Docker, disk, memory, and nanoclaw status. Deployed two ways:

1. **New instances** — injected into cloud-init by Pulumi
2. **Running instances** — copied by the GitHub Actions deploy workflow

Edit `status.sh` here; it propagates automatically via both paths.

## Modifying Cloud-Init

Changes to `cloud-init.sh` only take effect on **new instances** (instance replacement or fresh provision). For running instances, use the deploy workflow (`.github/workflows/deploy.yml`) or SSH.

Always validate after editing:

```bash
bash -n infra/cloud-init.sh          # syntax check
cd infra/gcp && pulumi preview       # confirm GCP diff
cd infra/oracle && pulumi preview    # confirm OCI diff
```
