---
date: 2026-03-22
topic: multi-agent-support
---

# Multi-Agent Support for NanoClaw

## Problem Frame

NanoClaw currently maps 1 process = 1 agent identity (one trigger word, one brain, one persona). To deploy nanoclaw for companies — where each company is a tenant with agents per user, per workspace, or per function — a single process must support multiple distinct agents sharing the same channels and infrastructure.

## Requirements

- R1. **Agent definitions via directory convention.** Each agent is defined as a directory under a configurable `agents/` path (e.g., `agents/anton/`, `agents/hr-bot/`). Each agent directory contains:
  - `agent.yaml` — agent name, trigger word, and per-agent config overrides
  - `brain/` — identity, instructions, and context files (mounted into containers as `/workspace/extra/brain/`)
  - `groups/` — per-agent group memory (CLAUDE.md files, isolated from other agents)

- R2. **Multi-agent routing.** The message loop matches incoming messages against all registered agent trigger patterns (not just one). When a message matches an agent's trigger, that specific agent's config (brain, name, memory namespace) is used for the container invocation. Multiple agents can be triggered by different messages in the same polling cycle.

- R3. **Shared channel connections.** All agents within a tenant share the same channel connections (WhatsApp, Slack, GitHub, web). One WhatsApp session, one Slack bot, etc. Agents are distinguished by trigger words, not by separate connections.

- R4. **Multiple agents per group.** A group can be registered to multiple agents. Each agent responds independently to its own trigger word within that group. Example: in an "Engineering" group, `@Anton` triggers the general assistant and `@Ops` triggers the incident bot.

- R5. **Fully isolated agent memory.** Each agent has its own:
  - Group folder namespace (e.g., `groups/anton/main/`, `groups/hr-bot/main/`)
  - Claude sessions (per agent, per group)
  - Conversation cursor tracking (per agent, per group)
  - Scheduled tasks (scoped to the agent that created them)

- R6. **Per-agent admin group.** Each agent has its own main group with elevated privileges. The main group for agent X only has admin access to agent X's groups and tasks, not other agents'.

- R7. **Backward compatibility.** A nanoclaw instance with no `agents/` directory and a single `ASSISTANT_NAME` env var continues to work exactly as today — single-agent mode. Multi-agent activates only when agent definitions are present.

- R8. **Monorepo deployment.** The deploy workflow clones/pulls this repo directly. Agent definitions, infrastructure, and platform code all deploy with one `git pull`.

- R9. **Scale target: 10-20 agents per instance.** The architecture should comfortably support 10-20 agents sharing a single nanoclaw process, with `MAX_CONCURRENT_CONTAINERS` scaled accordingly.

## Success Criteria

- A single nanoclaw process can run 2+ agents with different trigger words, brains, and isolated memory
- Agents in the same group respond independently to their own triggers without interfering
- Adding a new agent requires only creating an agent directory and restarting — no code changes
- Existing single-agent deployments continue working without configuration changes

## Scope Boundaries

- **Not in scope:** Agent-to-agent communication or coordination. Agents are fully independent.
- **Not in scope:** Per-agent channel configuration (e.g., agent X only on Slack, agent Y only on WhatsApp). All agents share all channels. Can be added later.
- **Not in scope:** Runtime agent hot-loading. Adding/removing agents requires a process restart.
- **Not in scope:** Per-agent resource limits (CPU, memory). All agents share the tenant's container resource config.
- **Not in scope:** UI or dashboard for managing agents. Configuration is file-based.

## Key Decisions

- **Shared channels, not per-agent channels:** Avoids multiplying WhatsApp sessions and Slack bots. Agents distinguished by trigger words. Rationale: simpler ops, fewer API connections, natural UX (users mention the agent they want in the same chat).
- **Directory convention over config file or database:** Matches the monorepo structure (`agents/anton/`), easy to version control and deploy. Rationale: file-based config is the nanoclaw philosophy ("small enough to understand").
- **Fully isolated memory over shared:** Prevents agents from interfering with each other's context. Rationale: at company scale, agent independence is more important than coordination. Coordination can be added later if needed.
- **First-match trigger resolution:** When a message mentions multiple agent triggers, only the first match (at the start of the message) activates. Trigger must appear at message start (`^@Name\b`), not anywhere in the body. Rationale: predictable UX, avoids duplicate responses, matches existing behavior.
- **Fork modification, not adapter layer:** This is a fundamental architecture change to the routing and identity system. Wrapping nanoclaw externally would add more complexity than modifying it directly. Rationale: the fork already diverges from upstream; this is the kind of change that justifies a fork.
- **Merged monorepo:** Anton's infra, agents, and scripts live in the nanoclaw fork. Upstream directories (`src/`, `container/`, `docs/`) sync cleanly because the added directories (`infra/`, `agents/`, `scripts/`, `config/`) don't exist upstream.

## Dependencies / Assumptions

- The `agents/` directory structure is already created with `agents/anton/brain/` and `agents/anton/groups/main/CLAUDE.md`
- `registered_groups.json` will need to be extended to associate groups with specific agents (or multiple agents)

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] What is the exact schema for `agent.yaml`? Should it support config overrides like `containerConfig`, `maxConcurrentContainers`, or custom env vars per agent?
- [Affects R2][Resolved] Trigger collision: first match wins, trigger must be at start of message. Decided during brainstorm.
- [Affects R4][Technical] How should `registered_groups.json` change to support multi-agent group registration? Array of agent names per group entry, or separate entries per agent-group pair?
- [Affects R5][Technical] How should the group folder namespace work on disk? `groups/{agent}/{group}/` or `groups/{group}/{agent}/`? The former groups by agent, the latter by group.
- [Affects R5][Needs research] How does the GroupQueue need to change? Currently keyed by `chatJid` — should it be keyed by `agentName:chatJid` to allow concurrent agent invocations in the same group?
- [Affects R6][Technical] How should the IPC watcher distinguish which agent a task or message belongs to?

## Next Steps

-> `/ce:plan` for structured implementation planning
