# NanoClaw GCP Enterprise Architecture

## Overview

Enterprise-grade deployment of NanoClaw on Google Cloud Platform using an **instance-per-tenant** model. Each customer gets one or more dedicated NanoClaw instances running in isolated Kubernetes namespaces on GKE.

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Google Cloud Platform                        │
│                                                                     │
│  ┌──────────────┐   ┌──────────────────────────────────────────┐   │
│  │ Control Plane │   │            GKE Cluster                   │   │
│  │ (Cloud Run)   │   │                                          │   │
│  │               │   │  ┌─────────────┐  ┌─────────────┐       │   │
│  │ • Provision   │──▶│  │ ns: tenant-a │  │ ns: tenant-b │      │   │
│  │ • Scale       │   │  │ ┌─────────┐ │  │ ┌─────────┐ │       │   │
│  │ • Monitor     │   │  │ │NanoClaw │ │  │ │NanoClaw │ │       │   │
│  │ • Billing     │   │  │ │  + DinD  │ │  │ │  + DinD  │ │      │   │
│  └──────────────┘   │  │ │sidecar  │ │  │ │sidecar  │ │       │   │
│                      │  │ └─────────┘ │  │ └─────────┘ │       │   │
│  ┌──────────────┐   │  │ ┌─────────┐ │  │ ┌─────────┐ │       │   │
│  │Secret Manager│   │  │ │   PVC   │ │  │ │   PVC   │ │       │   │
│  │ (per-tenant) │   │  │ │ (state) │ │  │ │ (state) │ │       │   │
│  └──────────────┘   │  │ └─────────┘ │  │ └─────────┘ │       │   │
│                      │  └─────────────┘  └─────────────┘       │   │
│  ┌──────────────┐   │                                          │   │
│  │  Artifact    │   │  ┌─────────────────────────────────┐     │   │
│  │  Registry    │   │  │         Shared Services          │     │   │
│  │ (images)     │   │  │  • Ingress (Cloud Load Balancer) │     │   │
│  └──────────────┘   │  │  • Cloud Logging agent           │     │   │
│                      │  │  • Cloud Monitoring agent        │     │   │
│  ┌──────────────┐   │  └─────────────────────────────────┘     │   │
│  │ Cloud SQL    │   └──────────────────────────────────────────┘   │
│  │ (control     │                                                   │
│  │  plane DB)   │   ┌──────────────────────────────────────────┐   │
│  └──────────────┘   │              VPC Network                  │   │
│                      │  • Private GKE nodes                     │   │
│                      │  • Cloud NAT for outbound                │   │
│                      │  • Private Google Access                  │   │
│                      └──────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Architecture Decisions

### 1. Compute: GKE with DinD Sidecar

**Why GKE over GCE VMs:**
- Kubernetes-native namespace isolation per tenant (network policies, resource quotas, RBAC)
- Rolling updates with zero downtime across all tenants
- Built-in autoscaling (HPA + cluster autoscaler)
- Better resource utilization (bin-packing multiple tenants per node)
- Native integration with GCP services (Workload Identity, Cloud Logging)

**Why DinD sidecar over alternatives:**
- NanoClaw spawns Docker containers for agent execution — this is core architecture
- Docker-in-Docker sidecar gives each pod its own Docker daemon
- No changes to container-runner.ts needed (Docker socket mounted from sidecar)
- Isolated Docker daemons prevent tenant cross-contamination
- Alternative (Cloud Run Jobs for agents) would require significant refactoring of IPC/filesystem patterns

### 2. Storage: SQLite on PersistentVolumes + GCS Backup

**Why keep SQLite:**
- Each instance is single-tenant — SQLite handles the load easily
- No database migration required (zero code changes)
- PersistentVolumes on GCE Persistent Disks give SSD performance + replication
- GCS backup via CronJob for point-in-time recovery

**When to migrate to Cloud SQL:**
- If cross-tenant analytics are needed (centralized reporting)
- If instance restart time (PV reattach) becomes unacceptable
- If SOC2 auditors require managed database with encryption at rest

### 3. Secrets: Google Secret Manager

- Per-tenant secrets (ANTHROPIC_API_KEY, channel tokens) stored in Secret Manager
- Kubernetes External Secrets Operator syncs to namespace-scoped K8s secrets
- Workload Identity ensures pods can only access their own tenant's secrets
- No `.env` files on disk — secrets injected at pod startup

### 4. Networking: Private GKE + Cloud NAT

- Private GKE nodes (no public IPs)
- Cloud NAT for outbound traffic (WhatsApp, Slack, Anthropic API)
- Network Policies isolate tenant namespaces from each other
- Cloud Load Balancer for web channel ingress (per-tenant subdomain)

### 5. Observability: Cloud Operations Suite

- Structured JSON logging (pino) → Cloud Logging (automatic via GKE)
- Cloud Monitoring dashboards per tenant
- Uptime checks for health endpoints
- Alert policies: container crash loops, high error rate, API quota exhaustion

## GKE Cluster Design

### Node Pools

| Pool | Machine Type | Purpose | Scaling |
|------|-------------|---------|---------|
| `system` | e2-standard-2 | GKE system pods, monitoring | Fixed (1-2 nodes) |
| `nanoclaw` | e2-standard-4 | NanoClaw orchestrator pods | Autoscale (1-50 nodes) |
| `agent` | c2-standard-8 | Agent container execution (via DinD) | Autoscale (0-100 nodes) |

### Resource Quotas Per Tenant

```yaml
# Applied per namespace
resources:
  requests.cpu: "2"
  requests.memory: "4Gi"
  limits.cpu: "8"
  limits.memory: "16Gi"
  persistentvolumeclaims: "3"
  pods: "20"
```

## Tenant Lifecycle

### Provisioning Flow

```
1. Admin calls Control Plane API: POST /tenants
2. Control Plane creates:
   a. GCP Secret Manager secrets (API keys, channel tokens)
   b. Kubernetes namespace: tenant-{id}
   c. ResourceQuota + LimitRange
   d. NetworkPolicy (isolate from other tenants)
   e. PersistentVolumeClaim (10Gi SSD for SQLite + groups/)
   f. Kubernetes Secret (synced from Secret Manager)
   g. NanoClaw Deployment + Service
3. Control Plane records tenant in Cloud SQL metadata DB
4. Health check confirms instance is running
```

### Update Flow (Rolling Deployments)

```
1. New nanoclaw-agent image pushed to Artifact Registry
2. CI/CD pipeline updates Deployment image tag
3. Kubernetes performs rolling update per namespace
4. Pod Disruption Budget ensures min 1 pod available
5. Readiness probe gates traffic until new pod is healthy
6. Old pod gets SIGTERM → GroupQueue.gracefulShutdown() → clean exit
```

## Security Model

### Per-Tenant Isolation

| Layer | Mechanism |
|-------|-----------|
| **Compute** | Separate Kubernetes namespace per tenant |
| **Network** | NetworkPolicy: deny all inter-namespace traffic |
| **Storage** | Separate PVC per tenant (GCE PD encryption at rest) |
| **Secrets** | Secret Manager + Workload Identity (scoped per SA) |
| **Docker** | Isolated DinD sidecar (separate Docker daemon per pod) |
| **IAM** | Per-tenant GCP service account with least-privilege |

### Workload Identity

Each tenant namespace has a Kubernetes ServiceAccount bound to a GCP service account:
```
tenant-a-sa@project.iam.gserviceaccount.com → roles/secretmanager.secretAccessor
```
This SA can only access secrets prefixed with `nanoclaw/tenant-a/`.

## Code Changes Required

### Minimal Changes (Phase 1)

1. **Health check endpoint** — Add `/healthz` and `/readyz` to web channel (already has Hono server)
2. **Graceful shutdown** — Already implemented in `GroupQueue.gracefulShutdown()`, just needs SIGTERM handler
3. **Structured logging** — Already using pino (JSON format), works with Cloud Logging out of the box

### Future Changes (Phase 2+)

1. **Secret Manager integration** — Load secrets from Secret Manager instead of `.env` file
2. **GCS backup** — Sidecar CronJob that syncs SQLite + groups/ to GCS bucket
3. **Cloud SQL migration** — Replace `better-sqlite3` with `pg` (postgres) for HA
4. **Metrics endpoint** — Prometheus `/metrics` for custom dashboards

## Implementation Phases

### Phase 1: Foundation (Weeks 1-3)
- GKE cluster with Terraform
- Artifact Registry for container images
- VPC + networking
- First tenant deployed manually via kubectl
- Health check endpoint added to NanoClaw

### Phase 2: Automation (Weeks 4-6)
- Terraform tenant module
- Secret Manager integration
- CI/CD pipeline (Cloud Build)
- Monitoring dashboards + alerts
- GCS backup CronJob

### Phase 3: Control Plane (Weeks 7-10)
- Control Plane API (Cloud Run)
- Self-service tenant provisioning
- Billing integration
- Multi-region support
- SLA monitoring

## Cost Estimate (per tenant/month)

| Component | Spec | Cost |
|-----------|------|------|
| GKE pod (NanoClaw) | 1 vCPU, 2Gi RAM | ~$35 |
| GKE pod (DinD sidecar) | 2 vCPU, 4Gi RAM | ~$70 |
| Persistent Disk (SSD) | 10Gi | ~$2 |
| Cloud NAT | Egress traffic | ~$5-15 |
| Secret Manager | 5 secrets | ~$0.30 |
| Cloud Logging | ~1GB/month | ~$0.50 |
| **Total per tenant** | | **~$115-125/mo** |

Shared costs (GKE management fee, load balancer, Cloud SQL for control plane): ~$200/mo fixed.
