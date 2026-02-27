# Agents Guide

Rules for AI agents working in this repo (Anton or Claude Code sessions).

## Repository Boundaries

This repo (`anton`) manages **infrastructure and operations** for dalab's cloud instances. The nanoclaw application source lives in a sibling directory (`../nanoclaw`). These are separate git repos with separate concerns:

| Repo | Scope |
|------|-------|
| `anton` (this repo) | Pulumi infra, cloud-init, deploy workflows, operational scripts, DNS |
| `../nanoclaw` | Application code — channels, agents, containers, business logic |

**Why separate**: nanoclaw tracks an upstream fork. Keeping infra changes here avoids merge conflicts when pulling upstream nanoclaw updates. Infrastructure changes should never leak into nanoclaw, and vice versa.

When a task touches both repos (e.g. adding a new env var that requires both a Pulumi config change and app code), make changes in each repo independently. Don't create cross-repo commits.

## Nanoclaw Context

When working on infra that serves nanoclaw (deploy scripts, cloud-init, systemd units, env injection), you may need to understand nanoclaw's structure. Read `../nanoclaw/CLAUDE.md` for application context. Key facts:

- Node.js process, runs as `anton` user on the instance
- Systemd service: `nanoclaw@anton.service`
- Working directory: `/home/anton/nanoclaw`
- Config: `.env` file in the working directory
- Containers: Docker-based agent sandboxes (`nanoclaw-*`)
- Channels: WhatsApp, Slack, GitHub

## Project Structure

```
anton/
  brain/              # Anton's identity, standards, architecture context
  infra/
    gcp/              # Pulumi stack — GCP compute, network, IAM, GitHub integration
    oracle/           # Pulumi stack — OCI compute, network, GitHub integration
    cloudflare/       # Pulumi stack — DNS, email routing, redirects, tunnels
    cloud-init.sh     # First-boot provisioning (swap, users, SSH keys)
    cloud-setup.sh    # Idempotent setup (packages, configs, services) — runnable standalone
    status.sh         # Single-source status script (deployed to instances)
  scripts/
    deploy-remote.sh  # Runs on instance during deploy (pull, build, restart)
    provision-tenant.sh  # Onboard a new tenant on an instance
  .github/workflows/
    deploy.yml        # Deploys nanoclaw + status script to instances
  connect.sh          # SSH to instances: ./connect.sh <user> [--gcp|--oci]
  sup                 # Remote diagnostics: sup [target] [--snap]
```

## Infrastructure Conventions

### Pulumi

- All infrastructure is TypeScript Pulumi. Three stacks: `gcp`, `oracle`, `cloudflare`.
- Each stack has its own `Pulumi.yaml`, `package.json`, and `node_modules`.
- Run `pulumi preview` from the stack directory (`infra/gcp/`, `infra/oracle/`, etc.) to validate changes.
- Secrets go in Pulumi config (`pulumi config set --secret`), never in files.
- Instance metadata is marked `ignoreChanges` (OCI) or managed carefully (GCP) to avoid unnecessary replacements.

### Cloud-Init

- Provisioning is split into two scripts: `infra/cloud-init.sh` (first-boot only) and `infra/cloud-setup.sh` (idempotent, runnable standalone).
- `cloud-init.sh` has a `# __CLOUD_SETUP_PLACEHOLDER__` marker where Pulumi inlines `cloud-setup.sh`.
- `cloud-setup.sh` has a `# __STATUS_SCRIPT_PLACEHOLDER__` marker where Pulumi injects `infra/status.sh`.
- The deploy key section is appended by Pulumi (not a placeholder — it's concatenated after cloud-init).
- Changes to `cloud-init.sh` only take effect on **new instances**. Changes to `cloud-setup.sh` can be applied to running instances: `scp` it over and `sudo bash` it.

### Deploy Workflow

- `.github/workflows/deploy.yml` handles deployments to all instances.
- Triggers: `workflow_dispatch` (manual) or `repository_dispatch` (nanoclaw-updated event).
- **Structure**: a `setup` job builds a matrix from `inputs.target`, then a single `deploy` job runs per instance. Each instance has a GitHub environment (`nanoclaw-gcp`, `nanoclaw-oci`) with a `DEPLOY_PROVIDER` variable that controls provider-specific steps.
- Targets use instance names from `tunnel.config.ts`: `nanoclaw-gcp`, `nanoclaw-oci`, or `all`.
- GCP connects via IAP tunnel (`gcloud compute ssh`). OCI connects via direct SSH as admin (`son`).
- Both providers SSH as an admin user with sudo, then delegate tenant-specific operations via `sudo -u $TENANT`.

### Shared Scripts

- `infra/status.sh` is the **single source of truth** for the instance health check. Edit it here; it propagates to cloud-init (via Pulumi) and running instances (via deploy workflow).
- `scripts/deploy-remote.sh` runs on the instance — pulls nanoclaw, builds, restarts the service.
- `connect.sh` and `sup` are local convenience scripts, not deployed.

### Cloudflare Tunnel

Nanoclaw's web channel uses Cloudflare Tunnel for inbound HTTP — outbound-only connections, no firewall ports needed.

**Architecture**: `Internet → subdomain.dalab.lol → Cloudflare Edge → Tunnel → cloudflared daemon → localhost:PORT → nanoclaw`

**Config pipeline**: `tunnel.config.ts` (route table) → `tunnel.ts` (Pulumi resources) → tunnels + DNS CNAMEs + ingress rules

**Route table** (`infra/cloudflare/tunnel.config.ts`):
- `instances`: one tunnel per compute instance (keyed by name, e.g. `nanoclaw-gcp`)
- `routes`: each creates an ingress rule + CNAME. Fields: `service`, `tenant`, `port`, `instance`
- **Subdomain convention**: `{service}-nanoclaw-{tenant}.dalab.lol` (e.g. `stix-api-nanoclaw-anton.dalab.lol`)

**Token flow**: Cloudflare stack auto-generates tunnel secret and exports token → operator copies token to compute stack (`pulumi config set --secret nanoclaw:cloudflareTunnelToken`) → cloud-init/deploy writes token to instance → cloudflared starts.

**Port conventions**: 3001+ for stix-api. Each tenant gets a unique port assigned by `provision-tenant.sh` and stored in `~/.config/nanoclaw/port.env`.

**Onboarding a new tenant**:
1. Add route to `tunnel.config.ts`, run `pulumi up` on cloudflare stack (creates DNS + ingress)
2. SSH to instance, run `sudo provision-tenant.sh <user> --port <port>` (creates OS user, sets port)
3. Deploy nanoclaw: `gh workflow run deploy.yml -f tenant=<user> -f target=nanoclaw-gcp`

**Adding a new instance**:
1. Add to `instances` in `tunnel.config.ts`, add routes
2. `pulumi up` on cloudflare stack → creates tunnel (secret auto-generated)
3. Copy token to compute stack: `pulumi config set --secret nanoclaw:cloudflareTunnelToken "$(pulumi stack output tunnel_<name>_token --show-secrets)"`
4. New Pulumi stack's `github-environments.ts` creates environment with `DEPLOY_PROVIDER` var
5. Add instance name to `deploy.yml` `options` list and `ALL` array in setup job
6. `pulumi up` on compute stack → instance gets cloudflared + token

## Operational Rules

1. **Never hardcode secrets** in scripts or cloud-init. Use Pulumi config for provisioning-time secrets, GitHub environment secrets for deploy-time secrets.
2. **Test cloud-init changes** by running `pulumi preview` on both stacks — confirm the diff looks right.
3. **Status script changes** propagate two ways: next `pulumi up` (new instances) and next deploy workflow run (existing instances). No manual SSH needed.
4. **Deploy workflow changes** — validate YAML syntax. The workflow uses a single matrix job with provider-conditional steps. When adding a new instance, add it to the `options` list and the `ALL` array in the setup job.
5. **Don't modify nanoclaw source** from this repo. If a task requires nanoclaw changes, note what's needed and handle it in `../nanoclaw`.

## Commit Style

Descriptive plain-language messages. Explain what changed and why.

```
Good: "Auto-deploy status script and single-source cloud-init injection"
Good: "Fix deploy key churn and ignore instance metadata changes"
Bad:  "feat: update infra"
Bad:  "misc changes"
```
