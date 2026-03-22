# GCS Backup Setup

Continuous SQLite replication via Litestream and periodic file sync via `gcloud storage rsync` to a GCS bucket. Provides near-zero data loss for the database (~10s RPO) and periodic backup of group files, auth tokens, and session data (~15min RPO).

---

## Prerequisites

- GCE VM with an attached service account
- `gcloud` CLI installed and authenticated
- `sqlite3` CLI installed
- NanoClaw deployed to `~/nanoclaw` on the VM

---

## GCP Setup

### Create a GCS Bucket

Follow the `{project}-nanoclaw-{tenant}` naming convention:

```bash
gcloud storage buckets create gs://YOUR_PROJECT-nanoclaw-YOUR_USERNAME \
  --location=us-central1 \
  --uniform-bucket-level-access
```

If using Pulumi (recommended), add the tenant to `stix/infra/nanoclaw-tenants.ts` and run `pulumi up` — this creates the bucket with lifecycle rules automatically.

### Grant Bucket Access

The VM's attached service account needs `storage.objectAdmin` on the bucket:

```bash
gcloud storage buckets add-iam-policy-binding gs://YOUR_PROJECT-nanoclaw-YOUR_USERNAME \
  --member="serviceAccount:YOUR_VM_SERVICE_ACCOUNT@YOUR_PROJECT.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

If the service account already has project-level `storage.objectAdmin`, this step is unnecessary.

### Optional: Lifecycle Rules

If not using Pulumi (which applies these automatically), add lifecycle rules to reduce storage costs:

```bash
# Transition to Nearline after 30 days
gcloud storage buckets update gs://YOUR_PROJECT-nanoclaw-YOUR_USERNAME \
  --lifecycle-file=/dev/stdin <<'EOF'
{
  "rule": [
    {"action": {"type": "SetStorageClass", "storageClass": "NEARLINE"}, "condition": {"age": 30}},
    {"action": {"type": "Delete"}, "condition": {"age": 365}}
  ]
}
EOF
```

---

## VM Setup

### Install Litestream

Download and install from the [Litestream releases](https://github.com/benbjohnson/litestream/releases):

```bash
LITESTREAM_VERSION=0.3.13
wget https://github.com/benbjohnson/litestream/releases/download/v${LITESTREAM_VERSION}/litestream-v${LITESTREAM_VERSION}-linux-amd64.deb
sudo dpkg -i litestream-v${LITESTREAM_VERSION}-linux-amd64.deb
```

Verify installation:

```bash
litestream version
# Expected: v0.3.13
which litestream
# Expected: /usr/bin/litestream
```

### Enable User Linger

Required for user-level systemd services to survive SSH disconnection:

```bash
sudo loginctl enable-linger $(whoami)
```

---

## NanoClaw Configuration

### Set Environment Variables

Add to `~/nanoclaw/.env`:

```bash
LITESTREAM_ENABLED=true
GCS_BACKUP_BUCKET=YOUR_PROJECT-nanoclaw-YOUR_USERNAME
```

### Run Setup

```bash
cd ~/nanoclaw
npm run setup
```

This calls `setup/service.ts` which:

1. Generates a per-tenant `~/.config/litestream.yml` with the correct bucket name and DB path
2. Copies `deploy/litestream.service`, `deploy/nanoclaw-rsync.service`, and `deploy/nanoclaw-rsync.timer` to `~/.config/systemd/user/`
3. Injects `GCS_BACKUP_BUCKET` into the rsync service environment
4. Adds `After=litestream.service` and `Wants=litestream.service` to `nanoclaw.service`
5. Sets `Environment=LITESTREAM_ENABLED=true` on `nanoclaw.service`
6. Enables and starts Litestream and the rsync timer

---

## Verification

### Quick Check

```bash
./sup --snap
```

The **Backup Status** section should show:

```
=== Backup Status ===
Litestream: active
WAL size: <number> bytes
rsync timer: active
```

### Detailed Checks

```bash
# Litestream is running and replicating
systemctl --user is-active litestream
# Expected: active

# rsync timer is scheduled
systemctl --user list-timers nanoclaw-rsync.timer
# Should show NEXT and LAST trigger times

# GCS bucket has data
gcloud storage ls gs://YOUR_BUCKET/litestream/
# Should show WAL segment files

gcloud storage ls gs://YOUR_BUCKET/rsync/
# Should show groups/, store/, data/ prefixes after first timer run

# LAST_SYNC sentinel exists (after first successful rsync)
gcloud storage cat gs://YOUR_BUCKET/rsync/LAST_SYNC
# Should show an ISO timestamp
```

---

## Disaster Recovery

### Restore from Backup

On a fresh or failed VM:

1. Ensure `~/nanoclaw/.env` has `GCS_BACKUP_BUCKET` set
2. Run the restore script:

```bash
cd ~/nanoclaw
bash deploy/restore.sh
```

The script will:

1. Stop all services (nanoclaw, litestream, rsync timer)
2. Back up the existing DB (if present) to `messages.db.pre-restore`
3. Restore SQLite from Litestream (GCS WAL replay)
4. Run an integrity check (warns but proceeds on failure)
5. Restore files from rsync (groups, auth, sessions)
6. Start all services
7. Verify services are running

### Post-Restore Checklist

| Check | Command |
|-------|---------|
| Services running | `systemctl --user is-active nanoclaw litestream` |
| WhatsApp connected | Check logs for `connection.open` |
| Re-auth if needed | `cd ~/nanoclaw && npm run setup` (scan QR code) |
| Backup resuming | `./sup --snap` — Litestream active, rsync timer active |
| Groups intact | `ls ~/nanoclaw/groups/` — should contain `main/` and group folders |

WhatsApp auth tokens (`store/auth/`) may be stale after restore. If the bot does not connect, re-authenticate by scanning the QR code.

---

## Monitoring

### What to Watch

| Signal | Healthy | Unhealthy |
|--------|---------|-----------|
| Litestream service | `active` | `failed` or `not running` |
| WAL size | < 10 MB | > 100 MB (Litestream not checkpointing) |
| LAST_SYNC age | < 30 min | > 1 hour (rsync failing) |
| rsync timer | `active` with recent LAST trigger | `inactive` or no recent trigger |

### Check Commands

```bash
# Litestream status
systemctl --user status litestream

# WAL size (should be < 10 MB normally)
ls -lh ~/nanoclaw/store/messages.db-wal

# Last rsync time
gcloud storage cat gs://YOUR_BUCKET/rsync/LAST_SYNC

# rsync timer next/last run
systemctl --user list-timers nanoclaw-rsync.timer
```

### Failure Recovery

If Litestream is failed:

```bash
systemctl --user restart litestream
systemctl --user status litestream
```

If rsync is failing, check bucket permissions:

```bash
# Test write access
echo "test" | gcloud storage cp - gs://YOUR_BUCKET/test-write
gcloud storage rm gs://YOUR_BUCKET/test-write
```

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Litestream fails to start | Binary not installed | `which litestream` — install if missing |
| Litestream fails to replicate | Bucket permissions | Verify service account has `storage.objectAdmin` |
| rsync timer not running | Service not enabled | `systemctl --user enable --now nanoclaw-rsync.timer` |
| Services stop after SSH disconnect | Linger not enabled | `sudo loginctl enable-linger $(whoami)` |
| `GCS_BACKUP_BUCKET not set` | Missing from `.env` or environment | Add to `~/nanoclaw/.env` and re-run `npm run setup` |
| WAL growing unbounded | Litestream crashed | Restart Litestream; built-in watchdog triggers passive checkpoint at 100 MB |
| Restore fails on fresh VM | No backup exists yet | Expected on first deploy — creates fresh DB |
| Litestream config has wrong bucket | Setup not re-run after `.env` change | Re-run `npm run setup` to regenerate `~/.config/litestream.yml` |

### Architecture Reference

```
GCE VM
├── store/
│   ├── messages.db          ← Litestream → gs://bucket/litestream/messages.db
│   └── auth/                ← rsync → gs://bucket/rsync/store/auth/
├── groups/                  ← rsync → gs://bucket/rsync/groups/
└── data/
    └── sessions/            ← rsync → gs://bucket/rsync/data/sessions/

Systemd Service Graph:
  litestream.service → (After) → nanoclaw.service
  nanoclaw-rsync.timer → (triggers) → nanoclaw-rsync.service
```
