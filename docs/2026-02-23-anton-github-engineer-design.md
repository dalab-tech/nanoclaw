# Anton: Autonomous GitHub Engineer

## Overview

Anton is an autonomous AI engineer that operates as a member of the `dalab` GitHub organization. It monitors assigned issues and PRs, executes plans, writes code, and reports progress — all without human intervention beyond the initial assignment and plan approval.

Anton runs on the existing Oracle Cloud ARM instance via nanoclaw. It polls GitHub for assignments, spins up isolated Docker containers to do work, and communicates via messaging channels (WhatsApp and Slack).

## Workflows

### Workflow A — Execute a Plan

You create a PR with a detailed plan in the body. Assign Anton. Anton executes.

```
You create PR with plan → Assign to anton-dalab → Poller detects →
Container clones repo → Anton executes plan → Commits + pushes →
Comments on PR → Messages you → Marks PR ready for review
```

### Workflow B — Plan First, Then Execute

You create an issue with high-level intent. Assign Anton. Anton writes a plan, waits for approval, then executes.

```
You create issue → Assign to anton-dalab → Poller detects →
Container clones repo → Anton explores codebase → Writes plan as draft PR →
Messages you "plan ready" → You review and approve (remove draft / add label) →
Next poll detects approval → Workflow A kicks in
```

Both workflows converge: Anton working through an approved plan in a PR.

## GitHub Account & Auth

### Account Setup

- Create GitHub account: `anton-dalab` (clearly labeled as a bot in bio)
- Add to `dalab` org as a **member** (not owner)
- Create GitHub Team: `anton-repos` with **write** permission
- Add allowed repos to the team (start with `stix-sandbox`)
- To grant Anton access to a new repo, just add it to the `anton-repos` team

### Authentication

Fine-grained PAT generated from `anton-dalab`, scoped to the `dalab` org:

| Permission | Level | Purpose |
|---|---|---|
| Issues | Read & Write | Read assignments, comment |
| Pull requests | Read & Write | Create, update, comment |
| Contents | Read & Write | Push branches |
| Metadata | Read | Required baseline |

PAT stored in `/home/anton/.anton/.env` on the instance as `GITHUB_TOKEN`. Set to expire every 90 days.

No org-level permissions needed. The team boundary controls which repos Anton can access.

### Instance Users

The Oracle Cloud instance has dedicated users for separation of concerns:

| User | Purpose | Home |
|---|---|---|
| `son` | Human admin — SSH access, sudo, instance management | `/home/son/` |
| `anton` | Bot persona — runs its own nanoclaw instance, deploy key, task state | `/home/anton/` |
| `ubuntu` | OCI default — anti-idle cron only | `/home/ubuntu/` |

Both `son` and `anton` have sudo, docker access, and SSH authorized keys. Each persona (like `anton`) runs its own nanoclaw instance as a systemd template service (`nanoclaw@anton`). This enables multiple personas on one host — to add another, create the user, clone nanoclaw, configure its `.env`, and enable `nanoclaw@<name>`.

## Polling Loop

A lightweight script runs every 5 minutes via systemd timer. No AI tokens consumed.

### Discovery

Single GitHub API call:
```
GET /search/issues?q=assignee:anton-dalab+is:open+sort:updated
```

Returns all open issues and PRs assigned to Anton across all repos it has access to.

### State Tracking

Local file `/home/anton/.anton/active-tasks.json` tracks known assignments. The poller compares API results against this file to detect:

- **New issue assigned** → trigger Workflow B (plan creation)
- **New PR assigned** → trigger Workflow A (execute plan)
- **Draft PR approved** (draft status removed or `anton:execute` label added) → trigger Workflow A on existing Workflow B plan

### Behavior

- One task at a time. If Anton is already working, new assignments queue.
- Anton finishes the current task before picking up the next.
- Queue is processed in assignment order (oldest first).

## Agent Execution

When the poller triggers work, it invokes nanoclaw's agent in an isolated Docker container.

### Container Environment

The container receives:
- Repo URL, branch name, issue/PR number as environment variables
- GitHub PAT mounted as a secret
- Fresh filesystem (full isolation from host)

### Execution Flow

1. Clone the repo, check out the relevant branch (or create one for issues)
2. Read the plan from the PR body (Workflow A) or explore the codebase and write one (Workflow B)
3. Run Claude Code with `--dangerously-skip-permissions` — full autonomy inside the container
4. Commit and push after each meaningful chunk of work
5. Comment on the PR with progress after each push
6. Send messaging alert at key moments (started, progress, blocked, done)
7. When done: mark PR as ready for review, comment with summary

### Plan Creation (Workflow B)

When Anton creates a plan from an issue, the draft PR body follows a consistent format:

- Summary of the change
- Files to create/modify
- Step-by-step approach
- Open questions (if any)

Branch naming: `anton/issue-{number}-{slug}` (e.g., `anton/issue-42-add-dark-mode`)

Anton comments on the original issue linking to the draft PR.

### Blocker Handling

If Anton gets stuck (ambiguous spec, failing CI it can't fix, unclear requirements):
1. Commits whatever progress it has
2. Comments on the PR explaining the blocker
3. Messages you via WhatsApp/Slack
4. Stops working on this task, moves to the next queued task (if any)

## Container Security

The container is ephemeral and fully isolated. This makes `--dangerously-skip-permissions` safe — worst case, Anton wrecks its own container.

### Allowed

| Capability | Detail |
|---|---|
| Claude Code (`--dangerously-skip-permissions`) | Full autonomy — no permission prompts |
| Outbound network | Research docs, APIs, install packages |
| Git push | Only to its assigned task branch |

### Denied

| Restriction | Detail |
|---|---|
| Host filesystem | No mounts to host, nanoclaw, or other repos |
| Inbound network | No ports exposed from container |
| Other repos | Can only access the cloned task repo |
| Nanoclaw data | Cannot read/write nanoclaw's own config or state |

### Resource Limits

| Resource | Limit | Rationale |
|---|---|---|
| CPU | 2 OCPU | Leave 2 OCPU for nanoclaw + OS on 4 OCPU instance |
| Memory | 8 GB | Leave 16 GB for host on 24 GB instance |
| Time | 2 hours | Prevents runaway agents; Anton commits progress and stops |

If the time limit is hit, Anton commits what it has, comments on the PR with progress, messages you, and stops. You can re-assign to continue.

### Blast Radius

Worst case: one PR gets bad commits. You review before merging — no unreviewed code reaches main.

## Messaging Channels

Anton communicates through two channels. Both are supported; users choose their preferred channel.

### WhatsApp (via nanoclaw — existing)

Nanoclaw already handles WhatsApp. Anton's GitHub integration hooks into this existing channel.

### Slack (planned)

> **Note:** Slack support is a future addition. When implemented, messaging Anton in a Slack channel will be visible to the team. Anton replies in-thread to keep channels clean. The same commands and alerts work in both WhatsApp and Slack.

Slack adds team visibility — anyone in the channel can see what Anton is working on and its progress without needing WhatsApp access.

### Automated Alerts

Sent to your configured channel(s) at key moments:

| Event | Message |
|---|---|
| New assignment | "Picked up: stix-sandbox#42 — starting work" |
| Progress | "Progress: stix-sandbox#42 — auth middleware done, moving to tests" |
| Blocked | "Blocked: stix-sandbox#42 — CI failing on unrelated test, need guidance" |
| Plan ready | "Plan ready for review: stix-sandbox#50 (draft)" |
| Done | "Done: stix-sandbox#42 — PR ready for review" |

### Commands

You can message Anton directly (WhatsApp or Slack):

| Command | Action |
|---|---|
| `work on stix-sandbox#42` | Manually trigger a task (skips waiting for next poll) |
| `status` | What Anton is working on, what's queued |
| `stop` | Abort current task, commit progress, comment on PR |

In Slack, these are sent as messages in a channel or DM. Anton replies in-thread.

## Implementation Phases

### Phase 1 — GitHub Account Setup (manual, one-time)

- Create `anton-dalab` GitHub account
- Add to `dalab` org, create `anton-repos` team
- Add `stix-sandbox` to the team
- Generate fine-grained PAT, store in nanoclaw `.env`

### Phase 2 — Polling Loop

- Script/module that runs every 5 minutes via systemd timer
- Calls GitHub search API for assigned issues/PRs
- Maintains `/home/anton/.anton/active-tasks.json` for state
- Detects new assignments and draft-to-ready transitions
- Triggers agent execution

### Phase 3 — Agent Execution Wrapper

- Script that nanoclaw calls to run a GitHub task
- Builds/runs Docker container with: repo URL, branch, PR/issue number, PAT
- Container runs Claude Code with `--dangerously-skip-permissions` + network
- Resource limits (2 OCPU, 8GB, 2-hour timeout)
- On completion: push commits, comment on PR, send alert

### Phase 4 — Messaging Commands

- Add message patterns to nanoclaw's router: `work on`, `status`, `stop`
- Route to the same execution path as the poller
- Abstract messaging layer to support both WhatsApp and Slack

### Phase 5 — Plan Creation Flow (Workflow B)

- Agent prompt/instructions for reading an issue and producing a structured plan
- Logic to open draft PRs and detect approval (draft removal or label)
- Link back to original issue

### Phase 6 — Slack Integration

- Add Slack bot to nanoclaw
- Thread-based replies in channels
- Same commands and alerts as WhatsApp
- Team-visible progress
