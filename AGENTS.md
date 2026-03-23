# Agents Guide

Rules for AI agents working in this repo (Anton or Claude Code sessions).

## Repository Structure

This is a **monorepo** containing the nanoclaw platform, agent definitions, and cloud infrastructure.

```
nanoclaw/
  src/                  # Platform code — channels, routing, containers
  container/            # Agent container definition and skills
  agents/               # Agent definitions (brain, groups, config)
    anton/
      brain/            # Identity, standards, architecture context
      groups/           # Agent-specific group configs (CLAUDE.md files)
  infra/
    gcp/                # Pulumi stack — GCP compute, network, IAM
    oracle/             # Pulumi stack — OCI compute, network
    cloudflare/         # Pulumi stack — DNS, email routing, tunnels
    cloud-init.sh       # First-boot provisioning
    cloud-setup.sh      # Idempotent setup (runnable standalone)
    status.sh           # Single-source status script
  scripts/
    deploy-remote.sh    # Runs on instance during deploy
    provision-tenant.sh # Onboard a new tenant
  config/               # Shared config (mount-allowlist, etc.)
  .github/workflows/
    deploy.yml          # Deploys to instances
  connect.sh            # SSH to instances
  sup                   # Remote diagnostics
```

## Upstream Sync

This repo is a fork of `qwibitai/nanoclaw`. Directories that don't exist upstream (`infra/`, `agents/`, `scripts/`, `config/`, `brain/`, `connect.sh`) won't conflict during upstream merges.

To sync upstream:
```bash
git remote add upstream https://github.com/qwibitai/nanoclaw.git  # once
git fetch upstream
git merge upstream/main
```

## Infrastructure Conventions

### Pulumi

- All infrastructure is TypeScript Pulumi. Three stacks: `gcp`, `oracle`, `cloudflare`.
- Each stack has its own `Pulumi.yaml`, `package.json`, and `node_modules`.
- Run `pulumi preview` from the stack directory (`infra/gcp/`, `infra/oracle/`, etc.) to validate changes.
- Secrets go in Pulumi config (`pulumi config set --secret`), never in files.

### Cloud-Init

- Provisioning is split into two scripts: `infra/cloud-init.sh` (first-boot only) and `infra/cloud-setup.sh` (idempotent, runnable standalone).
- Cloud-init only creates the admin user (`son`). Tenant users are provisioned later via `scripts/provision-tenant.sh`.
- `cloud-init.sh` has a `# __CLOUD_SETUP_PLACEHOLDER__` marker where Pulumi inlines `cloud-setup.sh`.
- `cloud-setup.sh` has a `# __STATUS_SCRIPT_PLACEHOLDER__` marker where Pulumi injects `infra/status.sh`.
- Changes to `cloud-init.sh` only take effect on **new instances**. Changes to `cloud-setup.sh` can be applied to running instances.

### Deploy Workflow

- `.github/workflows/deploy.yml` handles deployments to all instances.
- Triggers: `workflow_dispatch` (manual) or push to main.
- GCP connects via IAP tunnel (`gcloud compute ssh`). OCI connects via direct SSH.
- Both providers SSH as admin, delegate tenant ops via `sudo -u $TENANT`.

### Cloudflare Tunnel

**Architecture**: `Internet → subdomain.dalab.lol → Cloudflare Edge → Tunnel → cloudflared → localhost:PORT → nanoclaw`

**Route table** (`infra/cloudflare/tunnel.config.ts`): defines instances and routes. Each route creates an ingress rule + CNAME.

## Operational Rules

1. **Never hardcode secrets** in scripts or cloud-init. Use Pulumi config or GitHub secrets.
2. **Test cloud-init changes** by running `pulumi preview` on both stacks.
3. **Status script changes** propagate via `pulumi up` (new instances) and deploy workflow (existing instances).

## Commit Style

Descriptive plain-language messages. Explain what changed and why.

```
Good: "Auto-deploy status script and single-source cloud-init injection"
Good: "Fix deploy key churn and ignore instance metadata changes"
Bad:  "feat: update infra"
Bad:  "misc changes"
```
