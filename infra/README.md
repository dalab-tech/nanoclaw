# Infrastructure

Pulumi stacks and shared provisioning scripts for dalab's cloud instances.

## Layout

```
infra/
  gcp/                      Pulumi stack — GCE instance, network, IAM, WIF, GitHub integration
  oracle/                   Pulumi stack — OCI instance, network, GitHub integration
  cloudflare/               Pulumi stack — DNS zones, email routing, redirects
  cloud-init.sh             First-boot provisioning (swap, user creation, SSH keys)
  cloud-setup.sh            Idempotent setup (packages, configs, services) — runnable standalone
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

### cloud-init.sh + cloud-setup.sh

Provisioning is split into two scripts:

- **`cloud-init.sh`** — first-boot only: swap, user creation (useradd, SSH keys, workspace), sudoers. Contains a `__CLOUD_SETUP_PLACEHOLDER__` marker.
- **`cloud-setup.sh`** — idempotent setup: packages (Docker, Node.js, tools, GitHub CLI, cloudflared), firewall, fail2ban, Ghostty terminfo, Claude CLI, MC skin, user config (docker group, lingering), Cloudflare Tunnel unit, anti-idle cron, and `__STATUS_SCRIPT_PLACEHOLDER__`.

Both `gcp/compute.ts` and `oracle/compute.ts` assemble the final script: inline `cloud-setup.sh` at the `__CLOUD_SETUP_PLACEHOLDER__`, then inject `status.sh` at `__STATUS_SCRIPT_PLACEHOLDER__`, then append deploy key + tunnel token sections.

`cloud-setup.sh` is self-contained (own shebang, variables, OS detection) so it can be run standalone on existing instances:

```bash
scp infra/cloud-setup.sh son@<instance>:/tmp/
ssh son@<instance> sudo bash /tmp/cloud-setup.sh
```

### status.sh

Instance health-check that reports on systemd services, Docker, disk, memory, and nanoclaw status. Deployed two ways:

1. **New instances** — injected into cloud-init by Pulumi
2. **Running instances** — copied by the GitHub Actions deploy workflow

Edit `status.sh` here; it propagates automatically via both paths.

## Modifying Provisioning

Changes to `cloud-init.sh` only take effect on **new instances** (instance replacement or fresh provision). Changes to `cloud-setup.sh` can be applied to running instances by copying and running it directly (see above).

Always validate after editing:

```bash
bash -n infra/cloud-init.sh          # syntax check
bash -n infra/cloud-setup.sh         # syntax check
cd infra/gcp && pulumi preview       # confirm GCP diff
cd infra/oracle && pulumi preview    # confirm OCI diff
```
