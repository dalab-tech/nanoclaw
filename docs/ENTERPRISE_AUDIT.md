# Enterprise Readiness Audit

**Date:** 2026-03-22
**Scope:** Full source code review (~12.5K lines TypeScript, 268 passing tests)
**Reviewers:** Code quality, security, performance, and architecture analysis agents

---

## Executive Summary

NanoClaw demonstrates strong engineering for a personal tool — credential proxy isolation, directory-scoped IPC authorization, container sandboxing, SQLite WAL mode, and graceful shutdown with WIP recovery are all well-designed. Several categories of issues need attention before enterprise deployment.

**Overall Risk:** MODERATE — no critical remote code execution or authentication bypass, but container escape surface area, credential proxy exposure, and missing hardening measures require remediation.

---

## Critical Issues (Must Fix)

### C1. Shell injection in container commands
- **File:** `src/container-runtime.ts:67`
- **Description:** `stopContainer()` and `cleanupOrphans()` use string interpolation with `exec()`. Container names are sanitized at the call site, but the functions themselves accept any string.
- **Fix:** Switch to `execFile()` with argument arrays instead of shell string interpolation.

### C2. Credential proxy binds `0.0.0.0` on bare-metal Linux
- **File:** `src/container-runtime.ts:28-46`
- **Description:** When `docker0` interface is not found (rootless Docker, alternative runtimes), the proxy falls back to `0.0.0.0`, exposing the credential proxy — and your API keys — to the entire network.
- **Fix:** Never fall back to `0.0.0.0`. Fail with a clear error or bind to `127.0.0.1` with explicit documentation about configuring `--add-host` manually.

### C3. Docker socket mounted for main group
- **File:** `src/container-runner.ts:306-321`
- **Description:** The main group container gets the Docker socket mounted read-write. This is the classic Docker-in-Docker pattern that allows full host escape. Combined with `bypassPermissions`, a compromised main-group agent has root-equivalent host access.
- **Fix:** Use a Docker socket proxy (e.g., Tecnativa docker-socket-proxy) that limits API calls to specific operations. Alternatively, use rootless Docker.

### C4. Writable agent-runner source in containers
- **File:** `src/container-runner.ts:205-224`
- **Description:** Agent-runner TypeScript source is copied to a per-group writable location. A compromised agent can modify the runner source, and those modifications persist across container restarts (backdoor vector).
- **Fix:** Mount the agent-runner source read-only. If customization is needed, use a copy-on-write layer that resets on each container start.

### C5. Credential proxy has no authentication
- **File:** `src/credential-proxy.ts`
- **Description:** The proxy is a raw HTTP server with zero authentication. It relies entirely on network-level isolation. Any process on the host (or any container with host networking) can use the Anthropic API through the proxy.
- **Fix:** Add a shared secret (passed to containers via environment variable) that the proxy validates on each request.

---

## Security Findings

### High Severity

| ID | Issue | File | Recommendation |
|----|-------|------|----------------|
| S1 | `bypassPermissions` + `dangerouslySkipPermissions` in agent-runner | `container/agent-runner/src/index.ts:455-456` | Consider restricting `Bash` tool for non-main groups |
| S2 | No request body size limit on credential proxy | `src/credential-proxy.ts:48-51` | Add a cap (e.g., 10MB) to prevent memory exhaustion |

### Medium Severity

| ID | Issue | File | Recommendation |
|----|-------|------|----------------|
| S3 | Dashboard HTML served without auth | `src/channels/web.ts:104-125` | Require bearer auth for `/dashboard` page |
| S4 | `unsafe-inline` in dashboard CSP | `src/channels/web.ts` | Use nonce-based scripts instead |
| S5 | No schema validation on IPC JSON files | `src/ipc.ts:76,129` | Add Zod schema validation for all IPC message types |
| S6 | No network isolation for non-main containers | `src/container-runner.ts` | Use `--network=none` for non-main groups |
| S7 | Vulnerable rollup dependency | `package-lock.json` | Run `npm audit fix` to update rollup >= 4.59.0 |

### Low Severity

| ID | Issue | File | Recommendation |
|----|-------|------|----------------|
| S8 | Default sender allowlist permits all senders | `src/sender-allowlist.ts:17-20` | Document clearly; consider restrictive default |
| S9 | Remote control URL stored in plaintext | `src/remote-control.ts` | Ensure `data/` has 0700 permissions |
| S10 | Prompt content logged in verbose mode | `src/container-runner.ts:570-571` | Consider never logging full prompt content |
| S11 | Container input/prompt logged to disk in debug mode | `src/container-runner.ts` | Document as security consideration |

---

## Performance & Scalability Issues

### P0 — High Priority

| ID | Issue | File | Fix |
|----|-------|------|-----|
| P1 | Synchronous `fs.cpSync` blocks event loop on every container spawn | `src/container-runner.ts:181` | Use mtime/hash check to skip unchanged skills, or mount read-only |
| P2 | `loadSenderAllowlist` does synchronous file read on every message | `src/sender-allowlist.ts:33-48` | Cache with 30s TTL or `fs.watch` invalidation |

### P1 — Medium Priority

| ID | Issue | File | Fix |
|----|-------|------|-----|
| P3 | `botRepliedThreads` Set grows unbounded (memory leak) | `src/index.ts:88` | Add TTL-based eviction like Slack's `seenEvents` pattern |
| P4 | IPC polls filesystem every 1 second, O(N) per group | `src/ipc.ts` | Replace with `fs.watch` for event-driven processing |
| P5 | Container timeout resets on every output token — can run forever | `src/container-runner.ts:491` | Add hard max wall-clock time |
| P6 | Skills directories copied synchronously on every container launch | `src/container-runner.ts:174-183` | Skip copy when unchanged (mtime/hash check) |

### P2 — Lower Priority

| ID | Issue | File | Fix |
|----|-------|------|-----|
| P7 | GitHub `commentCursors` grows without pruning | `src/channels/github.ts:57` | Add periodic cleanup of old entries |
| P8 | No message retention policy — messages table grows forever | `src/db.ts` | Add archival/rotation mechanism |
| P9 | Slack `userCache`/`channelCache` have no size bounds | `src/channels/slack.ts` | Add max size cap alongside existing TTL |
| P10 | `getAllTasks()` called on every container spawn | `src/index.ts:421` | Cache tasks snapshot, regenerate only on change |
| P11 | Credential proxy buffers entire request body in memory | `src/credential-proxy.ts:48-51` | Stream bodies instead of buffering |
| P12 | WhatsApp outgoing queue unbounded during disconnection | `src/channels/whatsapp.ts:43` | Add max queue size, drop oldest when exceeded |
| P13 | Triple polling architecture (message loop + safety-net + IPC) | Multiple files | Consider event-driven alternatives where possible |

---

## Architecture Recommendations

### High Impact

#### A1. Unify channel initialization through the registry
- **Files:** `src/index.ts:83,868-940`, `src/channels/registry.ts`
- **Problem:** `index.ts` hardcodes 4 channels (WhatsApp, Slack, GitHub, Web) AND uses the registry for skill-installed channels. Two initialization paths exist.
- **Fix:** Migrate all channels to the registry pattern. Each factory already handles credential checking. Removes ~60 lines from `index.ts`.

#### A2. Add integration tests for `processGroupMessages`
- **File:** `src/index.ts:182-408`
- **Problem:** The most critical orchestration logic (trigger evaluation, multi-trigger splitting, cursor management, WIP recovery, error rollback) has zero test coverage.
- **Fix:** Create test harness using existing `_initTestDatabase` helper and mock containers.

#### A3. Make polling intervals configurable via environment variables
- **Files:** `src/config.ts`, `src/index.ts:1029`
- **Problem:** `POLL_INTERVAL` (2s), `IPC_POLL_INTERVAL` (1s), safety-net sweep (30s), `SCHEDULER_POLL_INTERVAL` (60s) are all hardcoded.
- **Fix:** Read from env vars with sensible defaults.

### Medium Impact

#### A4. Add internal health monitoring
- **Problem:** No self-check for DB connectivity, Docker availability, or channel connection health. Failures are silent.
- **Fix:** Add periodic health check that validates critical dependencies and logs/alerts on failure. Add a `/health` endpoint.

#### A5. Add container log rotation
- **File:** `src/container-runner.ts`
- **Problem:** `groups/{name}/logs/` grows without bound. Each container run creates a new log file.
- **Fix:** Implement log rotation (keep last N files or last N days).

#### A6. Version database migrations
- **File:** `src/db.ts`
- **Problem:** Schema changes use `ALTER TABLE ... ADD COLUMN` with swallowed exceptions. Partially applied migrations are undetectable.
- **Fix:** Add a `migrations` table with version tracking.

#### A7. Use JSON log output in production
- **File:** `src/logger.ts`
- **Problem:** `pino-pretty` is configured in all environments. Enterprise deployments need structured JSON for log aggregation.
- **Fix:** Use JSON output by default, pretty-print only when `LOG_LEVEL=debug` or `NODE_ENV=development`.

#### A8. Duplicate logger in mount-security
- **File:** `src/mount-security.ts:17`
- **Problem:** Creates its own pino logger instead of importing from `logger.ts`. Uncaught exceptions bypass the centralized fatal handler.
- **Fix:** Import from `src/logger.ts`.

### Lower Impact

#### A9. Redundant `storeMessage` retry
- **File:** `src/index.ts:828-843`
- **Problem:** Application-level retry is redundant with SQLite's `busy_timeout` pragma. The "message lost" log is misleading.
- **Fix:** Remove redundant retry or add dead-letter queue for truly failed writes.

#### A10. `require()` in ES module
- **File:** `src/channels/web.ts:168-169`
- **Problem:** Uses `require('fs')` and `require('path')` despite these being imported at the top. Copy-paste artifact.
- **Fix:** Use the existing imports.

#### A11. Module-level mutable state
- **File:** `src/index.ts` (multiple variables)
- **Problem:** `lastTimestamp`, `sessions`, `registeredGroups`, etc. are module-scoped mutable variables with `_reset*ForTests` escape hatches. Prevents testability and multiple instances.
- **Fix:** Extract into a `StateManager` class with clear load/save boundaries.

#### A12. Add `ContainerInput` schema version
- **Problem:** No version field in the IPC protocol between host and container, making protocol evolution harder.
- **Fix:** Add a `version` field to `ContainerInput` interface.

---

## What's Already Done Well

These areas demonstrate strong engineering and need no changes:

- **Credential proxy** — containers never see real API keys; `.env` shadow-mounted as `/dev/null`
- **Mount security** — external allowlist at `~/.config/nanoclaw/`, symlink resolution, blocked credential paths, read-only for non-main groups
- **IPC authorization** — identity derived from directory name (unforgeable), non-main groups restricted to own chat/tasks
- **Group folder validation** — strict regex, path traversal prevention, `ensureWithinBase` verification
- **SQL parameterization** — all queries use prepared statements, zero string concatenation
- **Graceful shutdown** — cursor rollback, WIP file persistence, restart notifications, channel disconnect ordering
- **Retry with exponential backoff** in GroupQueue (5 retries, base delay * 2^n)
- **Container resource limits** — CPU, memory, PIDs all configurable via env vars
- **SQLite configuration** — WAL mode, NORMAL sync, busy_timeout, Litestream backup integration
- **Web channel security** — bearer auth, Zod validation, rate limiting, 64KB input limit, security headers
- **Orphan container cleanup** at startup
- **Atomic IPC file writes** — temp-file-then-rename pattern
- **268 tests passing** covering security-critical paths (IPC auth, path traversal, credential isolation, queue concurrency)

---

## Multi-Tenant / HA Considerations (Future)

If NanoClaw is ever scaled beyond single-machine, single-user:

| Area | Current | Enterprise Requirement |
|------|---------|----------------------|
| Database | SQLite (single-writer) | PostgreSQL (multi-writer) |
| Message ingestion | Polling (2s interval) | Webhooks / event-driven |
| Work distribution | In-memory GroupQueue | Redis / SQS shared queue |
| IPC | File-based (1s polling) | gRPC / message queue |
| Container mgmt | Direct Docker API | Kubernetes / ECS |
| Channel connections | Single process owns all | Leader election per channel |
| State | Module-scoped variables | Shared DB with locking |
| Credentials | Single set per deployment | Per-tenant credential vaults |

---

## Remediation Roadmap

### Phase 1 — Immediate (before enterprise deployment)
- [ ] Fix `0.0.0.0` credential proxy fallback (C2)
- [ ] Add proxy authentication token (C5)
- [ ] Switch `exec()` → `execFile()` for container commands (C1)
- [ ] Mount agent-runner source read-only (C4)
- [ ] Add request body size limit to credential proxy (S2)

### Phase 2 — Short term (next sprint)
- [ ] Add Docker socket proxy for main group (C3)
- [ ] Add Zod schema validation to IPC (S5)
- [ ] Fix memory leaks: `botRepliedThreads`, `commentCursors` (P3, P7)
- [ ] Cache sender allowlist with TTL (P2)
- [ ] Run `npm audit fix` for rollup (S7)
- [ ] Add hard max wall-clock time for containers (P5)
- [ ] Skip skills copy when unchanged (P6)

### Phase 3 — Hardening
- [ ] Unify channel initialization through registry (A1)
- [ ] Add integration tests for orchestrator (A2)
- [ ] Make polling intervals configurable (A3)
- [ ] Add health monitoring endpoint (A4)
- [ ] Add container log rotation (A5)
- [ ] Implement versioned migrations (A6)
- [ ] JSON log output in production (A7)
- [ ] Network isolation for non-main containers (S6)
- [ ] Remove `unsafe-inline` from dashboard CSP (S4)
- [ ] Add message retention policy (P8)
