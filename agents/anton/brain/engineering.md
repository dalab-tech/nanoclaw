# Engineering Standards

## Tech Stack

- **Language**: TypeScript first. Always.
- **Runtimes**: Node.js and Bun. Use what the repo uses.
- **Frontend**: TanStack (Router, Query, Form, Table)
- **Backend**: Hono.js
- **Database**: Firestore (primary), Firebase services, SQLite (for local/embedded state)
- **Infrastructure**: Pulumi (TypeScript). Google Cloud.
- **Containers**: Docker for isolation and deployment.
- **AI**: Claude (Anthropic) — Agent SDK, API

## Code Style

- **Minimal abstractions**. Prefer inline code over premature extraction. Three similar lines of code is better than a helper function used once.
- Don't add features, refactor code, or make "improvements" beyond what was asked. A bug fix doesn't need surrounding code cleaned up.
- Don't add error handling for scenarios that can't happen. Trust internal code and framework guarantees.
- Only validate at system boundaries (user input, external APIs).
- No unnecessary comments or docstrings. Code should be self-evident. Only comment when the "why" isn't obvious.
- Avoid backwards-compatibility shims. If something is unused, delete it.

## Commits

- Descriptive commit messages in plain language. No rigid format.
- Message should explain what changed and why.
- Good: "Add webhook retry with exponential backoff"
- Good: "Fix race condition in container cleanup"
- Bad: "feat(webhook): add retry logic"
- Bad: "update stuff"

## Pull Requests

- Feature-complete PRs. One PR per feature, even if it's substantial.
- PR description should explain: what changed, why, and how to test.
- Break into multiple PRs only when the feature naturally decomposes into independent, separately-shippable pieces.

## Testing

- Test business logic and algorithms.
- Skip tests for simple CRUD, glue code, or straightforward wiring.
- When writing tests, test behavior (what it does) not implementation (how it does it).
- If a bug is fixed, add a test that would have caught it.

## Dependencies

- Prefer small, focused packages over large frameworks.
- Evaluate before adding: is this dependency worth the maintenance burden?
- Pin versions. No floating ranges in production code.
