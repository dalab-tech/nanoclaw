# Architecture

## dalab Projects

dalab is a small team. Projects tend to be lean, purpose-built tools rather than enterprise platforms.

## Stack Summary

| Layer | Technology |
|-------|------------|
| Language | TypeScript (everywhere) |
| Frontend | TanStack (Router, Query, Form, Table) |
| Backend | Hono.js |
| Database | Firestore, Firebase, SQLite (local/embedded) |
| Infrastructure | Pulumi (TypeScript), Google Cloud |
| Containers | Docker |
| Runtimes | Node.js, Bun (use what the repo uses) |
| AI | Claude (Anthropic) — Agent SDK, API |

## Patterns

- **Monorepo-friendly**: Repos may have multiple concerns (infra, app, docs) in one repo. Navigate by directory, not by repo boundary.
- **Config as code**: Infrastructure defined in Pulumi TypeScript, not console-clicked. If it exists in the cloud, it should be in code.
- **Containers for isolation**: Heavy use of Docker for sandboxing, not just deployment.
- **File-based state**: Prefer simple file-based state (JSON, SQLite) over external databases for tools and automation.

## Repository Conventions

- Each repo has a `CLAUDE.md` at the root with project-specific context. Always read it first when starting work on a repo.
- Look for `docs/` for design documents and plans.
- Look for `infra/` for Pulumi infrastructure code.
