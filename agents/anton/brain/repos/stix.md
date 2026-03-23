# STIX — AI Video Production Platform

## What It Is

STIX transforms raw source videos into branded promotional videos using a 5-stage AI agent pipeline. Multi-tenant SaaS with real-time UI, 87+ MCP tools, and agent-native architecture.

**URL:** https://stix.dalab.lol
**Repo:** `dalab-tech/stix` (pnpm monorepo, Turborepo for build orchestration)

## Tech Stack

| Layer | Technology |
|-------|------------|
| Frontend | React 19, TanStack Router (file-based), TanStack Query, Vite 7 |
| Styling | Tailwind CSS 4, DaisyUI 5 |
| Backend | Hono 4.6, Bun runtime |
| Job orchestration | Inngest (durable step functions, fan-out, retries) |
| Database | Firestore (NoSQL, native vector search) |
| Storage | Google Cloud Storage (video assets, scenes, renders) |
| LLM | Firebase Genkit with Dotprompt files. Anthropic Claude (default), Gemini, GPT-4o |
| Embeddings | Voyage AI (semantic scene search) |
| MCP | 87+ tools via `/mcp/tools/:toolName` endpoint |
| Infrastructure | Pulumi (TypeScript), Google Cloud (Cloud Run, Secret Manager, Artifact Registry) |
| CI/CD | GitHub Actions with Workload Identity Federation (keyless OIDC) |
| Testing | Bun test (backend), Vitest (frontend) |
| Package manager | pnpm 10 with workspaces |

## Monorepo Structure

```
stix/
├── stix-spa/           # Frontend SPA (React + TanStack)
├── stix-api/           # Backend API worker (Hono + Bun on Cloud Run)
│   ├── src/api/        # HTTP routes (19 modules)
│   ├── src/agents/     # 5-stage pipeline agents
│   ├── src/mcp/        # MCP tool definitions (87+ tools)
│   ├── src/db/         # Firestore wrapper
│   ├── src/tools/      # Low-level utilities (ffmpeg, transcription, vision)
│   ├── src/llm/        # Genkit initialization, prompt schemas
│   ├── src/inngest/    # Job orchestration step functions
│   └── prompts/        # Genkit Dotprompt files
├── packages/
│   ├── stix-types/     # Zod schemas + TypeScript types (shared)
│   ├── stix-remotion/  # Remotion video composition components
│   └── eslint-config/  # Shared ESLint rules
├── infra/              # Pulumi IaC (GCP resources)
├── docs/               # Architecture, guides, ADRs, plans
├── CLAUDE.md           # Coding rules (always read first)
├── AGENTS.md           # Agent navigation guide
└── .claude/agent-team.md  # Team orchestration rules (6 zones)
```

## 5-Agent Video Pipeline

```
Raw Videos → [Ingest] → [Understanding] → [Planner] → [Composition] → [Render]
             FFmpeg      Transcription     LLM script   Vector search   Remotion
             scene-detect vision-analyze   generation   scene matching  FFmpeg
```

Orchestrated by Inngest with parallel fan-out for stages 1-2, sequential for 3-5. Each stage is a durable step function with automatic retries.

## Critical Coding Rules

These are enforced by ESLint and CLAUDE.md. Violating them will break CI.

### Data Access (Hybrid Pattern)
- **Reads**: Firebase Client SDK (real-time `onSnapshot`)
- **Writes**: HTTP API via Hono RPC (`useApi(workspaceId)`)
- **Never** use bare `fetch()` for `/api/*` routes — use `useApi()` or `useGlobalApi()`
- **Never** use `c.req.json()` in routes — use `zValidator('json', Schema)` + `c.req.valid('json')`

### Firestore
- No `undefined` in writes — use `removeUndefined()` or conditional spread
- No `null` for absent fields — omit them entirely
- Always `makeDocId(workspaceId, EntityType)` for document IDs
- Always `fieldOf<T>()` for `where()`/`orderBy()` type safety
- Always `Schema.parse(convertTimestamps(doc.data()))` — never `as Type`

### TypeScript
- No `any` — use `unknown` + narrowing
- No `as` type casts without exhausting proper typing first
- All data parsing via Zod schemas in `packages/stix-types`

### LLM Calls
- All via Genkit Dotprompt (`.prompt` files in `stix-api/prompts/`)
- Define schemas in `prompt-schemas.ts`
- Tool-loop agents MUST set `maxTurns` (prevent runaway)
- Critical agents: `getCriticalMiddleware()`, others: `[getRetryMiddleware()]`

### MCP Tools
- Use `defineMcpTool()` for auto-registration
- Import tool file in `mcp/server.ts` (side-effect import)
- Include `workspaceId` parameter for multi-tenant isolation

## Multi-Tenancy

Every entity has a `workspaceId` field. Enforced at:
- Firestore security rules (170+ lines)
- API middleware (Bearer token → custom claims → workspaceId)
- Document ID format: `{workspaceId}__{entityType}-{localId}`
- Roles: viewer < member < admin < owner

## Agent Team Zones (for parallel work)

```
Zone 1: Frontend UI       (stix-spa/src/)
Zone 2: API Routes         (stix-api/src/api/) ⚠ SINGLE OWNER
Zone 3: Agents & Pipeline  (stix-api/src/agents/, tools/)
Zone 4: MCP & Data         (stix-api/src/mcp/, db/) ⚠ SINGLE OWNER
Zone 5: Supporting          (llm/, inngest/, slack/, config/)
Zone 6: Types & Infra       (packages/, infra/, docs/) — COMPLETE FIRST
```

Zones 2 and 4 are conflict zones — never assign to multiple teammates.

## Key Commands

```bash
pnpm install             # Install all dependencies
pnpm dev                 # Start all packages in dev mode
cd stix-api && pnpm test # Run backend tests
cd stix-api && pnpm ci   # typecheck + lint + test
cd infra && pnpm run sync # Sync secrets and env to cloud/local
```

## Deployment

| Target | Trigger | Branch |
|--------|---------|--------|
| SPA (Firebase Hosting) | Push to `main` | `main` |
| API (Cloud Run) | Push to `main` (dev), `release` (prod) | `main`, `release` |
| Infrastructure | Push to `release` or manual | `release` |

## Testing Philosophy

Only test what creates real value:
- Test: critical paths, complex algorithms, concurrency, state machines
- Skip: trivial getters, simple CRUD, config objects, one-liners

## Secrets

- Production: GCP Secret Manager
- Local dev: `infra/.secrets.local.json` (never committed, never pasted in terminal)
- Sync: `cd infra && pnpm run sync-secrets-to-cloud`
