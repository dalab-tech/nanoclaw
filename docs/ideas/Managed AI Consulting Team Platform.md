# Plan: Managed AI Consulting Team Platform — NanoClaw + Paperclip

## Context

You're building a platform to deploy managed AI consulting teams to small businesses. Each client gets their own team of AI agents (engineering, content, operations, bookkeeping) that integrate with their tools and data. Clients interact via Slack/WhatsApp — they don't know or care about the infrastructure. You manage the platform, set guardrails, and handle escalations.

**Goal for v1:** Set up 2 tenants — your company (DaLab) and 1 test client — to validate the platform and deployment model.

**Architecture:** Anton (NanoClaw) is the team lead per tenant. Paperclip is the back-office (task tracking, budgets, audit logs, agent spawning). Clients talk to their team lead via Slack/WhatsApp.

---

## Architecture

```
You (Super Admin — WhatsApp/Slack)
  │
  │ Monitor all tenants, handle escalations
  │
Your Anton (NanoClaw — your personal instance)
  │ ── Manages your own company's work
  │ ── Can monitor all tenants via Paperclip API
  │
  ┌──────────────────────────────────────────────────┐
  │              Shared Infrastructure (OCI VM)      │
  │                                                  │
  │  Paperclip (single instance, multi-tenant)       │
  │  ├── Company: DaLab (your workspace)             │
  │  └── Company: Client Alpha (their workspace)     │
  │                                                  │
  │  NanoClaw Instances (per tenant)                 │
  │  ├── /home/son/nanoclaw/        → port 3100      │
  │  └── /home/client-alpha/nanoclaw/ → port 3101    │
  │                                                  │
  │  Cloudflare Tunnel (subdomain routing)           │
  └──────────────────────────────────────────────────┘
          │                        │
     DaLab Tenant            Client Alpha Tenant
     ├── Anton (team lead)   ├── "Alpha Lead" agent
     ├── Coding agents       ├── Coding agents
     ├── Channels: WA/Slack  ├── Channel: Slack
     └── Your repos/tools    └── Their repos/tools
```

### How It Works

1. **Client messages their team lead** via Slack: "Add a blog to the website"
2. **Team lead agent** (NanoClaw container) decomposes the request into tasks
3. **Team lead creates tasks in Paperclip** (their company workspace) via API
4. **Paperclip spawns coding agents** (`claude_local` adapter) to do the work
5. **Coding agents build**, push to git, update task status in Paperclip
6. **Team lead QAs the output** (build check, screenshots, visual comparison)
7. **Team lead posts preview link** to client's Slack for approval
8. **Client approves** → team lead deploys to production
9. **Your Anton monitors** all tenants, alerts you on failures or escalations

### What the Client Sees vs. Reality

| Client's experience | What's happening |
|---|---|
| "I messaged my team on Slack" | NanoClaw received message via Slack channel |
| "They said they're working on it" | Team lead created tasks in Paperclip, triggered coding agents |
| "They sent me a preview link" | Agent deployed to Vercel preview, posted URL to Slack |
| "I said ship it, and it went live" | Agent deployed to production via Vercel CLI |
| "My monthly report shows 15 tasks completed" | Paperclip audit log + cost tracking |

---

## Agent Roles & Templates

### Team Lead (every tenant gets one)

**Purpose:** Single point of contact for the client. Coordinates all work.

| Capability | How |
|---|---|
| Receive client requests | NanoClaw Slack/WhatsApp channel |
| Decompose into tasks | Brain file instructions + Claude reasoning |
| Assign to coding agents | Paperclip MCP: `paperclip_create_task`, `paperclip_assign_task` |
| Monitor progress | Paperclip MCP: `paperclip_get_status` (scheduled polling) |
| QA review | Agent-browser screenshots, `npm run build`, Lighthouse |
| Deploy previews | Vercel CLI via Bash |
| Communicate with client | NanoClaw MCP: `send_message` |
| Escalate to you | NanoClaw MCP: `send_message` to your Anton's channel |

**Brain file:** `templates/brain/team-lead.md`
**Guardrails:** Cannot deploy production without approval (tier 1-2). Must escalate unknown requests.

### Engineer (spawned by Paperclip per task)

**Purpose:** Writes code, builds features, fixes bugs.

| Capability | How |
|---|---|
| Write code | Claude Code CLI (file tools, Bash) |
| Extract designs | Figma MCP server |
| Run builds/tests | Bash (npm, git) |
| Create PRs | GitHub CLI |
| Report completion | Paperclip API (via injected skill) |

**Brain file:** `templates/brain/engineer.md`
**Guardrails:** Access only to assigned tenant's repos. No infra changes.

### Content Writer (future)

**Purpose:** Blog posts, social copy, email campaigns, website content updates.

**Brain file:** `templates/brain/content-writer.md`
**Guardrails:** All content is draft until client approves.

### Operations Assistant (future)

**Purpose:** Calendar management, CRM updates, process documentation, vendor tracking.

**Brain file:** `templates/brain/ops-assistant.md`
**Guardrails:** Read access to most systems, write access only to approved tools.

### Bookkeeper (future — requires licensed CPA partner)

**Purpose:** Transaction categorization, P&L reports, invoice reminders. NOT tax prep or financial advice.

**Brain file:** `templates/brain/bookkeeper.md`
**Guardrails:** Read-only financial data. All reports flagged "prepared by AI, review recommended."

---

## Template System

```
templates/
├── brain/
│   ├── team-lead.md          # PM/coordinator (every tenant)
│   ├── engineer.md            # Software development
│   ├── content-writer.md      # Marketing/content (future)
│   ├── ops-assistant.md       # Operations (future)
│   └── bookkeeper.md          # Financial tasks (future, needs CPA)
├── skills/
│   ├── qa-check/SKILL.md      # Standard QA flow
│   ├── deploy-preview/SKILL.md # Vercel/Netlify preview deploys
│   └── client-comms/SKILL.md  # How to communicate with clients
├── guardrails/
│   ├── tier-1.md              # New client: everything needs your approval
│   ├── tier-2.md              # Established: preview deploys, client approves prod
│   └── tier-3.md              # Trusted: autonomous with notification
├── integrations/
│   ├── github.md              # How to connect client's repos
│   ├── figma.md               # How to connect client's Figma
│   ├── vercel.md              # How to connect deployment
│   └── slack.md               # How to connect client's Slack workspace
└── onboarding/
    └── provision-tenant.sh    # Automated tenant setup
```

### Per-Tenant Customization

When onboarding a client, the template brain files get customized:

```
templates/brain/team-lead.md (generic)
  + client brand name, voice, preferences
  + client tech stack (Next.js, WordPress, etc.)
  + client deploy target (Vercel project ID, domain)
  + guardrail tier (1, 2, or 3)
  = /home/client-alpha/nanoclaw/groups/main/CLAUDE.md (customized)
```

---

## Integration Framework

Each tenant gets their own credentials, isolated via NanoClaw's per-tenant `.env`:

| Integration | MCP Server | Credentials | Status |
|---|---|---|---|
| **GitHub** | Container skill (existing) | Deploy key per repo | Exists |
| **Figma** | `figma-mcp.ts` (new) | Personal access token | Build in Phase 2 |
| **Vercel** | Bash + credential passthrough | `VERCEL_TOKEN` | Build in Phase 3 |
| **Slack** | NanoClaw channel (existing) | Bot token per workspace | Exists |
| **Paperclip** | `paperclip-mcp.ts` (new) | API key per company | Build in Phase 1 |
| **QuickBooks/Xero** | Future MCP server | OAuth tokens | Future |
| **Google Workspace** | Future MCP server | Service account | Future |

---

## Deployment Architecture

### Target: 2 Tenants on OCI VM

```
OCI VM (4 ARM cores, 24GB RAM)
│
├── Shared Services
│   ├── Paperclip (Docker Compose: app + PostgreSQL)
│   │   ├── Company: DaLab
│   │   └── Company: Client Alpha
│   ├── Cloudflare Tunnel
│   │   ├── dalab.dalab.lol → port 3100
│   │   └── alpha.dalab.lol → port 3101
│   └── Docker daemon (shared, runs agent containers)
│
├── Tenant: DaLab (/home/son/nanoclaw/)
│   ├── NanoClaw (systemd: nanoclaw-son, port 3100)
│   ├── .env (your credentials: Anthropic, GitHub, Figma, Vercel, Paperclip)
│   ├── groups/ (your groups + memory)
│   ├── store/ (your message DB)
│   └── Agent containers mount /home/son/nanoclaw/groups/...
│
├── Tenant: Client Alpha (/home/client-alpha/nanoclaw/)
│   ├── NanoClaw (systemd: nanoclaw-client-alpha, port 3101)
│   ├── .env (their credentials: Anthropic, GitHub, Figma, Vercel, Paperclip)
│   ├── groups/ (their groups + memory)
│   ├── store/ (their message DB)
│   └── Agent containers mount /home/client-alpha/nanoclaw/groups/...
│
└── Tenant isolation:
    ├── Linux users: son, client-alpha (filesystem isolation)
    ├── Separate .env files (credential isolation)
    ├── Separate NanoClaw processes (process isolation)
    ├── Docker containers per agent session (compute isolation)
    ├── Separate Paperclip companies (data isolation in PostgreSQL)
    └── Cloudflare subdomain routing (network isolation)
```

### Scaling Path

| Scale | Approach |
|---|---|
| 1-5 tenants | Same VM, separate NanoClaw processes |
| 5-10 tenants | Multiple OCI VMs (free tier = 4 ARM instances) |
| 10+ tenants | $3-6/month per VM, managed via deploy workflow |

**No Docker-in-Docker.** Linux users + Docker + Paperclip multi-tenancy is sufficient.

---

## What Needs to Be Built

### Phase 1: Core Platform (Week 1-2)

#### 1.1 Deploy Paperclip on OCI VM (~0.5 day)
- Docker Compose alongside NanoClaw
- Create DaLab company + `claude_local` coding agent
- Verify Paperclip works standalone: create task → agent completes it

#### 1.2 Paperclip MCP Server (~1-2 days)
Anton's tool for managing Paperclip.

**File:** `container/agent-runner/src/paperclip-mcp.ts` (new)
**Register:** `container/agent-runner/src/index.ts` → `buildMcpServers()`
**Auth:** `PAPERCLIP_API_URL` + `PAPERCLIP_API_KEY` via credential proxy

Tools:
- `paperclip_create_project` — Create client project
- `paperclip_create_task` — Create task from decomposed brief
- `paperclip_assign_task` — Assign to coding agent
- `paperclip_trigger_agent` — Wake an agent
- `paperclip_get_status` — Check task progress
- `paperclip_list_tasks` — List all tasks
- `paperclip_comment` — Post updates/results
- `paperclip_get_results` — Read agent output

#### 1.3 Team Lead Brain Template (~0.5 day)
**File:** `templates/brain/team-lead.md` (new)

How to decompose briefs, create tasks, monitor agents, QA output, communicate with clients, escalate to admin.

#### 1.4 Tenant Provisioning Script (~1 day)
Extend `scripts/provision-tenant.sh` to:
- Create Linux user + home directory
- Clone NanoClaw into tenant's home
- Generate `.env` with tenant-specific credentials
- Create systemd service (`nanoclaw-{tenant}`)
- Create Paperclip company via API
- Create Paperclip coding agent(s)
- Connect Slack workspace (interactive step)
- Apply brain templates with client customization
- Configure Cloudflare tunnel subdomain

**File:** `scripts/provision-tenant.sh` (extend existing)

### Phase 2: Engineering Pipeline (Week 3-4)

#### 2.1 Figma MCP Server (~1-2 days)
**File:** `container/agent-runner/src/figma-mcp.ts` (new)

Tools:
- `figma_get_file_structure` — Page/frame table of contents
- `figma_get_node_details` — Auto-layout, colors, typography, spacing
- `figma_export_image` — Screenshot for visual comparison

#### 2.2 Engineer Brain Template (~0.5 day)
**File:** `templates/brain/engineer.md` (new)

Next.js + Tailwind conventions, component patterns, Figma MCP usage, coding standards.

#### 2.3 QA Skill (~0.5 day)
**File:** `container/skills/qa-check/SKILL.md` (new)

Build check → Lighthouse → responsive screenshots (3 viewports) → visual comparison against Figma → deploy preview → post results.

#### 2.4 Deploy Credential Passthrough (~0.5 day)
**File:** `src/container-runner.ts` → extend `buildContainerArgs()` for `VERCEL_TOKEN`

### Phase 3: Second Tenant (Week 5-6)

#### 3.1 Provision Client Alpha
Run provisioning script for test client:
```bash
./scripts/provision-tenant.sh client-alpha \
  --slack-workspace "alpha-workspace" \
  --github-org "alpha-org" \
  --deploy-target vercel \
  --agents "team-lead,engineer" \
  --guardrail-tier 1
```

#### 3.2 End-to-End Test
- Connect Client Alpha's Slack workspace
- Send a request in their Slack: "Build a landing page from this Figma: [link]"
- Verify: team lead decomposes → tasks created in Paperclip → coding agents build → QA passes → preview deployed → approval requested in Slack
- Approve → production deploy
- Verify your Anton received monitoring notifications

#### 3.3 Iterate on Guardrails
- Tune escalation thresholds
- Test budget limits
- Test what happens when agents fail
- Test tenant isolation (Agent A can't see Agent B's data)

### Phase 4: Expand Roles (Week 7+)

- Content writer brain template + CMS integration
- Operations assistant brain template + Google Workspace MCP
- Bookkeeper brain template + QuickBooks MCP (requires CPA partner)

---

## Guardrail Tiers

| | Tier 1 (New Client) | Tier 2 (Established) | Tier 3 (Trusted) |
|---|---|---|---|
| Code changes | PR only, you review | PR, client approves | Direct commit, notify |
| Preview deploy | Auto, you review | Auto, client reviews | Auto, client notified |
| Production deploy | You approve | Client approves | Auto, client notified |
| Content publish | You approve | Client approves | Auto, client notified |
| Budget per month | Low cap ($50) | Medium ($200) | Higher ($500) |
| Escalation | Everything unknown → you | Complex requests → you | Only failures → you |

All tenants start at Tier 1. Promote based on trust and track record.

---

## Critical Files

| File | Change |
|------|--------|
| `container/agent-runner/src/paperclip-mcp.ts` (new) | Paperclip API MCP server |
| `container/agent-runner/src/figma-mcp.ts` (new) | Figma API MCP server |
| `container/agent-runner/src/index.ts` | Register new MCP servers in `buildMcpServers()` |
| `src/container-runner.ts` | Credential passthrough (`VERCEL_TOKEN`, `PAPERCLIP_API_KEY`) |
| `scripts/provision-tenant.sh` | Extend for full tenant setup (NanoClaw + Paperclip + channels) |
| `templates/brain/team-lead.md` (new) | Team lead brain template |
| `templates/brain/engineer.md` (new) | Engineer brain template |
| `container/skills/qa-check/SKILL.md` (new) | QA automation skill |

---

## Verification

### Phase 1 Checks
1. Paperclip runs on OCI VM, `claude_local` agent completes a test task
2. Anton creates a task in Paperclip via MCP → coding agent picks it up → completes it
3. Anton receives completion notification and reports to you via WhatsApp

### Phase 2 Checks
4. Anton extracts structure + screenshots from a Figma file
5. Coding agent builds a component matching the Figma design
6. QA skill runs Lighthouse, takes responsive screenshots, compares to Figma

### Phase 3 Checks
7. Second tenant provisioned with isolated NanoClaw + Paperclip workspace
8. Client Alpha's team lead receives Slack message → builds website → deploys preview
9. Tenant isolation verified: Alpha's agent cannot access DaLab's files/data
10. Your Anton monitors both tenants and reports status

### End-to-End Smoke Test
11. Full workflow: Slack message → brief decomposition → Figma extraction → parallel build → QA → preview deploy → approval → production deploy → notification

---

## Getting Started (Day 1)

1. SSH into OCI VM
2. Deploy Paperclip via Docker Compose
3. Create DaLab company + coding agent in Paperclip UI
4. Test: create a task manually → verify coding agent completes it
5. Build the Paperclip MCP server (`paperclip-mcp.ts`)
6. Mount it in Anton's container
7. Test: message Anton → he creates a task in Paperclip → agent picks it up
8. Once loop works → build Figma MCP → test with real design → provision second tenant
