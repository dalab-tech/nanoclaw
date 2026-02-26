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
    cloudflare/       # Pulumi stack — DNS, email routing, redirects
    status.sh         # Single-source status script (deployed to instances)
  scripts/
    deploy-remote.sh  # Runs on instance during deploy (pull, build, restart)
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

- `infra/oracle/cloud-init.sh` and `infra/gcp/cloud-init.sh` are base provisioning scripts.
- The status script is **not** embedded — a `# __STATUS_SCRIPT_PLACEHOLDER__` marker gets replaced by Pulumi at build time with the contents of `infra/status.sh`.
- The deploy key section is appended by Pulumi (not a placeholder — it's concatenated after cloud-init).
- If you modify cloud-init, the change only takes effect on **new instances** (instance replacement or fresh provision). For running instances, use the deploy workflow or manual SSH.

### Deploy Workflow

- `.github/workflows/deploy.yml` handles deployments to both GCP and OCI.
- Triggers: `workflow_dispatch` (manual) or `repository_dispatch` (nanoclaw-updated event).
- The workflow deploys `infra/status.sh` to instances on every run, then deploys nanoclaw.
- GCP connects via IAP tunnel (`gcloud compute ssh`). OCI connects via direct SSH with a deploy key.

### Shared Scripts

- `infra/status.sh` is the **single source of truth** for the instance health check. Edit it here; it propagates to cloud-init (via Pulumi) and running instances (via deploy workflow).
- `scripts/deploy-remote.sh` runs on the instance — pulls nanoclaw, builds, restarts the service.
- `connect.sh` and `sup` are local convenience scripts, not deployed.

## Operational Rules

1. **Never hardcode secrets** in scripts or cloud-init. Use Pulumi config for provisioning-time secrets, GitHub environment secrets for deploy-time secrets.
2. **Test cloud-init changes** by running `pulumi preview` on both stacks — confirm the diff looks right.
3. **Status script changes** propagate two ways: next `pulumi up` (new instances) and next deploy workflow run (existing instances). No manual SSH needed.
4. **Deploy workflow changes** — validate YAML syntax. The GCP and OCI jobs should stay structurally parallel (same steps, different connection methods).
5. **Don't modify nanoclaw source** from this repo. If a task requires nanoclaw changes, note what's needed and handle it in `../nanoclaw`.

## Commit Style

Descriptive plain-language messages. Explain what changed and why.

```
Good: "Auto-deploy status script and single-source cloud-init injection"
Good: "Fix deploy key churn and ignore instance metadata changes"
Bad:  "feat: update infra"
Bad:  "misc changes"
```
