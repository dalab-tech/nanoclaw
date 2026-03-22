# Anton: Autonomous GitHub Engineer (Director Architecture)

**Date:** 2026-03-01
**Status:** Approved, ready to implement

---

## Overview

Anton watches GitHub for issue/PR assignments, delegates engineering work to `@claude` (the Claude Code GitHub Action), monitors progress, and communicates status via WhatsApp/Slack. Anton is a **director**, not an executor — `@claude` does the coding on GitHub's infrastructure.

The director follows the **compound-engineering methodology**: plan → work → review → resolve → ship. Anton encodes this methodology into the prompts it sends to `@claude`, ensuring high-quality autonomous engineering regardless of the repo.

## Prerequisites (One-Time Manual Setup)

1. **Install Claude GitHub App** on `dalab` org: [github.com/apps/claude](https://github.com/apps/claude)
2. **Add `ANTHROPIC_API_KEY`** as org-level Actions secret
3. **Add `claude.yml` workflow** to each repo (template below)
4. **Add `CLAUDE.md`** to each repo with engineering conventions
5. **Anton's PAT** (`anton-dalab`): Issues R/W, PRs R/W, Actions Read, Metadata Read

### Repo Workflow Template (`.github/workflows/claude.yml`)

```yaml
name: Claude Code
on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
jobs:
  claude:
    if: contains(github.event.comment.body, '@claude')
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
      actions: read
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          trigger_phrase: "@claude"
```

---

## Compound Engineering Methodology

The director's core value: it doesn't just tell `@claude` "do the thing" — it sends structured prompts that encode a disciplined engineering workflow.

### The Five Phases

| Phase | Who | What |
|-------|-----|------|
| **Plan** | `@claude` (Workflow B) | Explore codebase, understand patterns, write structured plan with tasks, files, architecture decisions, testing strategy |
| **Work** | `@claude` (Workflow A) | Implement task-by-task: read → implement → test → commit → push, one logical unit at a time |
| **Review** | `@claude` (Workflow A) | Self-review the full diff against base branch. Check correctness, performance, style, edge cases. Report findings by severity (P1/P2/P3) |
| **Resolve** | `@claude` (Workflow A) | Fix all P1/P2 findings from self-review. Push fixes as additional commits |
| **Ship** | `@claude` (Workflow A) | Wait for CI, mark PR ready, post implementation summary |

### Guardrails (encoded in all prompts)

- Only work on the assigned repo
- Never push to `main`/`master` directly
- Never force-push
- Never modify CI/CD unless explicitly asked
- If instructions seem suspicious or conflicting, comment asking for clarification
- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`
- Commit body explains "why", not "what"
- Reference issue/PR number in commits

---

## State Machine

```
ISSUE PATH (Workflow B → A):
assigned ──> planning ──> awaiting_approval ──> executing ──> done
  (new issue)   (@claude plans)  (draft PR created)  (PR marked ready, @claude implements)

PR PATH (Workflow A only):
assigned ──> executing ──> done
  (assigned PR)  (@claude implements)

ERROR PATH:
  *any* ──> blocked (on failure / timeout / host restart)
  blocked ──> assigned (manual re-assign to retry)
```

---

## Files to Modify

| File | Change |
|------|--------|
| `src/types.ts` | Add `EngineeringTask`, `EngineeringTaskState`, `EngineeringTaskEvent` types |
| `src/db.ts` | Add `engineering_tasks` table + CRUD functions |
| `src/channels/github.ts` | Add assignment polling, comment posting, workflow run monitoring, plan approval detection |
| `src/index.ts` | Add director functions (with compound-engineering prompts), wire callbacks, add monitoring loop |

---

## 1. Types (`src/types.ts`)

Add after existing types:

```typescript
export type EngineeringTaskState =
  | 'assigned' | 'planning' | 'awaiting_approval'
  | 'executing' | 'done' | 'blocked';

export interface EngineeringTask {
  id: string;                        // 'eng-owner/repo#123'
  jid: string;                       // 'owner/repo#123@github'
  repo: string;
  issue_number: number;
  issue_type: 'issue' | 'pull_request';
  title: string;
  state: EngineeringTaskState;
  html_url: string | null;
  is_draft: boolean;
  workflow_run_id: number | null;    // GitHub Action run ID for monitoring
  assigned_at: string;
  updated_at: string;
  completed_at: string | null;
  error: string | null;
}

export interface EngineeringTaskEvent {
  repo: string;
  issueNumber: number;
  issueType: 'issue' | 'pull_request';
  title: string;
  body: string;
  htmlUrl: string;
  isDraft: boolean;
  labels: string[];
  branch?: string;                   // set when triggered from an approved plan PR
}
```

---

## 2. Database (`src/db.ts`)

### Schema (add to `createSchema()`)

```sql
CREATE TABLE IF NOT EXISTS engineering_tasks (
  id TEXT PRIMARY KEY,
  jid TEXT NOT NULL,
  repo TEXT NOT NULL,
  issue_number INTEGER NOT NULL,
  issue_type TEXT NOT NULL,
  title TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'assigned',
  html_url TEXT,
  is_draft INTEGER DEFAULT 0,
  workflow_run_id INTEGER,
  assigned_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  error TEXT
);
CREATE INDEX IF NOT EXISTS idx_eng_tasks_state ON engineering_tasks(state);
```

### CRUD Functions

Follow existing patterns (e.g., `createTask`/`updateTask`):

- **`upsertEngineeringTask(task: EngineeringTask): void`** — INSERT OR REPLACE
- **`getEngineeringTaskByJid(jid: string): EngineeringTask | undefined`** — lookup by JID
- **`updateEngineeringTaskState(id, state, extra?): void`** — update state + optional fields (error, completed_at, workflow_run_id), always set `updated_at = now`
- **`getActiveEngineeringTasks(): EngineeringTask[]`** — state NOT IN ('done')
- **`getEngineeringTasksInState(state: string | string[]): EngineeringTask[]`** — filter by one or more states

---

## 3. GitHub Channel (`src/channels/github.ts`)

### 3a. Extend `GitHubChannelOpts`

```typescript
export interface GitHubChannelOpts {
  // ... existing fields
  onEngineeringTask?: (jid: string, event: EngineeringTaskEvent) => void;
  isEngineeringTask?: (jid: string) => boolean;
}
```

### 3b. New: `pollAssignments()` — 5-minute interval

Searches GitHub for all open issues/PRs assigned to Anton's username. For each one not already tracked, fires `onEngineeringTask`. Also calls `checkPlanApprovals()`.

```typescript
private async pollAssignments(): Promise<void> {
  const query = `assignee:${this.opts.username} is:open sort:updated`;
  const response = await this.githubFetch(
    `https://api.github.com/search/issues?q=${encodeURIComponent(query)}&per_page=100`,
  );
  const data = await response.json();

  for (const item of data.items) {
    const repoFullName = item.repository_url.replace('https://api.github.com/repos/', '');
    const chatJid = `${repoFullName}#${item.number}@github`;
    const isPR = !!item.pull_request;

    if (this.opts.isEngineeringTask?.(chatJid)) continue;  // already tracked
    if (isPR && item.draft) continue;                        // skip draft PRs

    this.opts.onEngineeringTask?.(chatJid, {
      repo: repoFullName,
      issueNumber: item.number,
      issueType: isPR ? 'pull_request' : 'issue',
      title: item.title,
      body: item.body || '',
      htmlUrl: item.html_url,
      isDraft: item.draft ?? false,
      labels: item.labels.map((l: any) => l.name),
    });
  }

  await this.checkPlanApprovals();
}
```

**Start the interval** in `connect()` or `start()`:
```typescript
setInterval(() => this.pollAssignments().catch(log), 5 * 60_000);
this.pollAssignments().catch(log);  // run immediately on startup
```

### 3c. New: `postComment()`

Used by the director to post `@claude` trigger comments.

```typescript
async postComment(repo: string, number: number, body: string): Promise<void> {
  await this.githubFetch(
    `https://api.github.com/repos/${repo}/issues/${number}/comments`,
    { method: 'POST', body: JSON.stringify({ body }) },
  );
}
```

### 3d. New: `getWorkflowRunStatus()`

Check recent Action runs triggered by issue comments (i.e., `@claude` invocations).

```typescript
async getWorkflowRunStatus(repo: string): Promise<any[]> {
  const response = await this.githubFetch(
    `https://api.github.com/repos/${repo}/actions/runs?event=issue_comment&per_page=10`,
  );
  return (await response.json()).workflow_runs;
}
```

### 3e. New: `getIssueComments()`

Fetch comments on an issue/PR (used to find @claude's plan comment).

```typescript
async getIssueComments(repo: string, number: number): Promise<any[]> {
  const response = await this.githubFetch(
    `https://api.github.com/repos/${repo}/issues/${number}/comments?per_page=100`,
  );
  return response.json();
}
```

### 3f. New: `checkPlanApprovals()`

Called during `pollAssignments()`. For tasks in `awaiting_approval` state, checks if the draft PR has been marked ready (not draft) or labeled `plan-approved`.

```typescript
private async checkPlanApprovals(): Promise<void> {
  const awaiting = getEngineeringTasksInState('awaiting_approval');
  for (const task of awaiting) {
    const response = await this.githubFetch(
      `https://api.github.com/repos/${task.repo}/pulls?state=open&per_page=10`,
    );
    const prs = await response.json();
    const planPR = prs.find((pr: any) =>
      pr.head.ref.startsWith(`anton/issue-${task.issue_number}`)
    );
    if (!planPR) continue;

    const isApproved = !planPR.draft || planPR.labels.some((l: any) => l.name === 'plan-approved');
    if (!isApproved) continue;

    // Plan approved — fire event so orchestrator triggers Workflow A
    this.opts.onEngineeringTask?.(`${task.repo}#${planPR.number}@github`, {
      repo: task.repo,
      issueNumber: planPR.number,
      issueType: 'pull_request',
      title: planPR.title,
      body: planPR.body || '',
      htmlUrl: planPR.html_url,
      isDraft: false,
      labels: planPR.labels.map((l: any) => l.name),
      branch: planPR.head.ref,
    });
    updateEngineeringTaskState(task.id, 'done', { completed_at: new Date().toISOString() });
  }
}
```

### 3g. New: Branch + Draft PR Creation Helpers

Used by `handlePlanComplete()` in the orchestrator.

```typescript
async getDefaultBranch(repo: string): Promise<string> {
  const response = await this.githubFetch(`https://api.github.com/repos/${repo}`);
  const data = await response.json();
  return data.default_branch;
}

async createBranch(repo: string, branch: string, fromRef: string): Promise<void> {
  const refResponse = await this.githubFetch(
    `https://api.github.com/repos/${repo}/git/ref/heads/${fromRef}`,
  );
  const refData = await refResponse.json();
  const sha = refData.object.sha;

  await this.githubFetch(
    `https://api.github.com/repos/${repo}/git/refs`,
    { method: 'POST', body: JSON.stringify({ ref: `refs/heads/${branch}`, sha }) },
  );
}

async createDraftPR(repo: string, opts: {
  title: string; body: string; head: string; base: string;
}): Promise<{ number: number; html_url: string }> {
  const response = await this.githubFetch(
    `https://api.github.com/repos/${repo}/pulls`,
    {
      method: 'POST',
      body: JSON.stringify({
        title: opts.title,
        body: opts.body,
        head: opts.head,
        base: opts.base,
        draft: true,
      }),
    },
  );
  return response.json();
}
```

### 3h. Modify `processNotification()`

Skip assignment notifications — they're handled by the assignment poller:

```typescript
if (notif.reason === 'assign') {
  await this.githubFetch(
    `https://api.github.com/notifications/threads/${notif.id}`,
    { method: 'PATCH' },
  );
  return;  // handled by assignment poller
}
```

---

## 4. Orchestrator (`src/index.ts`)

### 4a. `handleEngineeringTask(jid, event)` — Entry Point

Called by GitHub channel when a new assignment is discovered. Deduplicates, creates the DB record, and dispatches to the appropriate workflow.

```typescript
function handleEngineeringTask(jid: string, event: EngineeringTaskEvent): void {
  const existing = getEngineeringTaskByJid(jid);
  if (existing && existing.state !== 'done') return;  // dedup

  const task: EngineeringTask = {
    id: `eng-${event.repo}#${event.issueNumber}`,
    jid,
    repo: event.repo,
    issue_number: event.issueNumber,
    issue_type: event.issueType,
    title: event.title,
    state: 'assigned',
    html_url: event.htmlUrl,
    is_draft: event.isDraft,
    workflow_run_id: null,
    assigned_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    completed_at: null,
    error: null,
  };
  upsertEngineeringTask(task);

  if (event.issueType === 'pull_request') {
    directWorkflowA(task, event);
  } else {
    directWorkflowB(task, event);
  }
}
```

### 4b. `directWorkflowA(task, event)` — Work + Review + Resolve + Ship

This is the compound-engineering execution prompt. It encodes the full work→review→resolve→ship cycle into a single `@claude` invocation.

```typescript
async function directWorkflowA(task: EngineeringTask, event: EngineeringTaskEvent): Promise<void> {
  updateEngineeringTaskState(task.id, 'executing');
  const github = channels.find(c => c.name === 'github') as GitHubChannel;

  await github.postComment(task.repo, task.issue_number,
    `@claude You are an autonomous engineer. Implement the plan in this PR following the compound-engineering methodology below.

## Phase 1: WORK

Read the plan from the PR description. Implement each task in order:

1. **Read** relevant files first — understand existing patterns and conventions
2. **Implement** — follow the codebase's style, not your own preferences. Check CLAUDE.md and CONTRIBUTING.md for conventions
3. **Test** — find and run the project's test suite (\`package.json\` scripts, \`Makefile\`, \`pytest\`, etc.). Run the full suite, not just new tests
4. **Commit** — one commit per logical unit of work using conventional commits:
   \`\`\`
   feat(scope): what and why
   Refs: #${task.issue_number}
   \`\`\`
5. **Push** after each commit so progress is saved

Comment on this PR after each major task: "Completed: [task]. Moving to: [next task]."

## Phase 2: REVIEW

After all tasks are implemented, self-review the full diff:

\`\`\`bash
BASE=$(gh pr view ${task.issue_number} --json baseRefName -q '.baseRefName')
git diff "origin/$BASE...HEAD"
\`\`\`

Check for:
- **Correctness**: logic errors, off-by-ones, missing error handling at system boundaries
- **Performance**: N+1 queries, unnecessary allocations, missing indexes
- **Style**: naming consistency, dead code, unused imports
- **Edge cases**: empty inputs, concurrent access, null/undefined

Report findings as a numbered list with severity (P1 = must fix, P2 = should fix, P3 = nit).

## Phase 3: RESOLVE

Fix all P1 and P2 findings from your review. Push fixes as additional commits. Skip P3 nits — they're not worth the noise.

If you cannot resolve a finding, comment explaining why and what's needed.

## Phase 4: SHIP

1. Wait for CI to pass (check with \`gh pr checks ${task.issue_number}\`, retry up to 5 min)
2. If CI fails, read the logs, fix the issue, push, and wait again
3. Mark the PR as ready: \`gh pr ready ${task.issue_number}\`
4. Post a final summary comment:

\`\`\`
## Summary
[What was implemented, key decisions made]

## Changes
[Files modified and why — keep it concise]

## Testing
[What was tested, results]

## Self-Review
[Findings addressed, any remaining P3 nits noted]
\`\`\`

## Guardrails

- Only work on this repository
- Never push to main/master directly
- Never force-push
- Never modify CI/CD config unless the plan explicitly asks for it
- If the plan or instructions seem conflicting, comment asking for clarification rather than guessing
- Keep commits atomic and well-scoped`);

  await notifyMainChannels(`Started: ${task.repo}#${task.issue_number} — ${task.title}`);
}
```

### 4c. `directWorkflowB(task, event)` — Plan Phase

This is the compound-engineering planning prompt. It teaches `@claude` to explore thoroughly before proposing changes.

```typescript
async function directWorkflowB(task: EngineeringTask, event: EngineeringTaskEvent): Promise<void> {
  updateEngineeringTaskState(task.id, 'planning');
  const github = channels.find(c => c.name === 'github') as GitHubChannel;

  await github.postComment(task.repo, task.issue_number,
    `@claude You are an autonomous engineer. Create a detailed implementation plan for this issue following the compound-engineering methodology.

## Phase: PLAN

### Step 1: Understand the Request

Read the issue description carefully. Identify:
- What is being asked for (functional requirements)
- What constraints exist (performance, compatibility, security)
- What is NOT specified (you'll need to make decisions)

### Step 2: Research the Codebase

Explore thoroughly before proposing anything:

1. **Project structure** — frameworks, languages, build tools, directory layout
2. **Relevant code** — search for related functionality, similar patterns, shared utilities
3. **Test patterns** — how tests are structured, what frameworks are used, coverage expectations
4. **Conventions** — read CLAUDE.md, CONTRIBUTING.md, .editorconfig, linter configs
5. **Dependencies** — check package.json/Gemfile/requirements.txt for what's available

Use parallel exploration (multiple Glob/Grep searches) to be efficient.

### Step 3: Write the Plan

Post the plan as a comment on this issue with this exact structure:

\`\`\`markdown
## Summary
[1-2 paragraphs: what needs to change and why. Include key architecture decisions.]

## Tasks
- [ ] Task 1: [description]
  - Files: [files to create/modify]
  - Approach: [how to implement, referencing existing patterns]
- [ ] Task 2: ...
[Order tasks by dependency — earlier tasks should not depend on later ones]

## Architecture Decisions
- [Decision]: [rationale, alternatives considered]

## Testing Strategy
- [What to test, how, expected coverage]

## Risks
- [What could go wrong and how to mitigate]
\`\`\`

### Rules

- Do NOT implement anything — plan only
- Reference specific files, functions, and line numbers you found during research
- When you find existing patterns in the codebase, explain how the plan follows them
- If the issue is ambiguous, document your interpretation and note alternatives
- Keep the plan actionable — another engineer (or agent) should be able to execute it without re-reading the codebase`);

  await notifyMainChannels(`Planning: ${task.repo}#${task.issue_number} — ${task.title}`);
}
```

### 4d. `monitorEngineeringTasks()` — 60-Second Polling Loop

Checks GitHub Action runs for active tasks. On completion, transitions state and notifies.

```typescript
async function monitorEngineeringTasks(): Promise<void> {
  const active = getEngineeringTasksInState(['planning', 'executing']);
  const github = channels.find(c => c.name === 'github') as GitHubChannel;
  if (!github?.isConnected()) return;

  for (const task of active) {
    const runs = await github.getWorkflowRunStatus(task.repo);
    const completedRun = runs.find((r: any) =>
      r.status === 'completed' && r.updated_at > task.updated_at
    );
    if (!completedRun) continue;

    if (completedRun.conclusion === 'success') {
      if (task.state === 'planning') {
        await handlePlanComplete(task);
      } else {
        updateEngineeringTaskState(task.id, 'done', {
          completed_at: new Date().toISOString(),
        });
        await notifyMainChannels(`Done: ${task.repo}#${task.issue_number} — ${task.title}`);
      }
    } else {
      updateEngineeringTaskState(task.id, 'blocked', {
        error: `Action run failed: ${completedRun.conclusion}`,
      });
      await notifyMainChannels(
        `Blocked: ${task.repo}#${task.issue_number} — action ${completedRun.conclusion}`,
      );
    }
  }
}
```

### 4e. `handlePlanComplete(task)` — Create Draft PR from Plan

After @claude posts a plan comment on the issue, Anton:
1. Fetches the plan comment
2. Creates a branch `anton/issue-{N}`
3. Creates a draft PR with the plan as the body
4. Comments on the original issue with a link
5. Transitions to `awaiting_approval`

```typescript
async function handlePlanComplete(task: EngineeringTask): Promise<void> {
  const github = channels.find(c => c.name === 'github') as GitHubChannel;

  // Find @claude's plan comment (most recent from a claude-like user)
  const comments = await github.getIssueComments(task.repo, task.issue_number);
  const planComment = comments
    .filter((c: any) => c.user.login.includes('claude'))
    .sort((a: any, b: any) => b.id - a.id)[0];

  if (!planComment) {
    updateEngineeringTaskState(task.id, 'blocked', {
      error: 'No plan comment found from @claude',
    });
    return;
  }

  // Create branch from default branch
  const defaultBranch = await github.getDefaultBranch(task.repo);
  const branch = `anton/issue-${task.issue_number}`;

  try {
    await github.createBranch(task.repo, branch, defaultBranch);
  } catch (e: any) {
    // Branch may already exist (retry scenario) — continue
    if (!e.message?.includes('already exists')) throw e;
  }

  // Create draft PR with plan as body
  const pr = await github.createDraftPR(task.repo, {
    title: `[Plan] ${task.title}`,
    body: `## Implementation Plan\n\nFrom issue #${task.issue_number}\n\n${planComment.body}`,
    head: branch,
    base: defaultBranch,
  });

  // Comment on original issue
  await github.postComment(task.repo, task.issue_number,
    `Plan ready for review: ${pr.html_url}\n\nMark the PR as **ready for review** when you approve the plan.`,
  );

  updateEngineeringTaskState(task.id, 'awaiting_approval', {
    html_url: pr.html_url,
  });
  await notifyMainChannels(
    `Plan ready: ${task.repo}#${task.issue_number} — ${pr.html_url}`,
  );
}
```

### 4f. `notifyMainChannels(message)` — WhatsApp/Slack Notifications

```typescript
async function notifyMainChannels(message: string): Promise<void> {
  for (const [jid, group] of Object.entries(registeredGroups)) {
    if (group.folder === MAIN_GROUP_FOLDER) {
      const channel = findChannel(channels, jid);
      if (channel?.isConnected()) {
        await channel.sendMessage(jid, message).catch(() => {});
      }
    }
  }
}
```

### 4g. Wiring in `main()`

```typescript
// When constructing GitHubChannel:
const github = new GitHubChannel({
  ...channelOpts,
  onEngineeringTask: handleEngineeringTask,
  isEngineeringTask: (jid) => {
    const t = getEngineeringTaskByJid(jid);
    return t != null && t.state !== 'done';
  },
});

// Start monitoring loop (60s):
setInterval(() => monitorEngineeringTasks().catch(log), 60_000);

// On startup, mark stale executing/planning tasks as blocked:
for (const t of getEngineeringTasksInState(['executing', 'planning'])) {
  updateEngineeringTaskState(t.id, 'blocked', { error: 'Host restarted' });
}
```

---

## End-to-End Flow

### Issue → Plan → Approval → Work → Review → Resolve → Ship

1. Human creates issue on `dalab/some-repo`, assigns `anton-dalab`
2. **Assignment poll** (5 min) detects new assignment
3. Anton creates DB record (`assigned`), transitions to `planning`
4. Anton posts `@claude` comment with **compound-engineering PLAN prompt**
5. GitHub Action triggers, @claude:
   - Reads the issue
   - Explores codebase structure, patterns, conventions
   - Posts structured plan comment (summary, tasks, architecture decisions, testing, risks)
6. **Monitor loop** (60s) detects Action run completed
7. Anton fetches plan comment, creates branch `anton/issue-N`, creates **draft PR** with plan as body
8. Anton comments on issue: "Plan ready for review: {PR link}"
9. Anton notifies WhatsApp/Slack: "Plan ready: repo#N — {PR link}"
10. Human reviews plan, edits if needed, marks PR as **ready for review**
11. **Assignment poll** detects `awaiting_approval` → approved transition
12. Anton fires new engineering task event for the PR (Workflow A)
13. Anton posts `@claude` comment with **compound-engineering WORK+REVIEW+RESOLVE+SHIP prompt**
14. GitHub Action triggers, @claude:
    - **WORK**: Implements tasks in order (read → implement → test → commit → push per task)
    - **REVIEW**: Self-reviews full diff (correctness, performance, style, edge cases)
    - **RESOLVE**: Fixes P1/P2 findings
    - **SHIP**: Waits for CI, marks PR ready, posts summary
15. **Monitor loop** detects Action run completed successfully
16. Anton marks task `done`, notifies: "Done: repo#N — title"

### PR → Work → Review → Resolve → Ship (Direct)

1. Human creates PR with plan in body, assigns `anton-dalab`
2. **Assignment poll** detects new PR assignment
3. Anton creates DB record (`assigned`), transitions to `executing`
4. Anton posts `@claude` comment with **compound-engineering WORK+REVIEW+RESOLVE+SHIP prompt**
5. @claude works through all four phases autonomously
6. **Monitor loop** detects completion
7. Anton marks task `done`, notifies WhatsApp/Slack

---

## Error Handling

### Action run fails (`conclusion !== 'success'`)
- Task transitions to `blocked` with error message
- Anton notifies WhatsApp/Slack: "Blocked: repo#N — action failed"
- Human can re-assign to retry

### No plan comment found after planning
- Task transitions to `blocked` with "No plan comment found from @claude"
- Likely means the Action ran but @claude didn't post (timeout, error)
- Human can check the Action logs and re-assign

### Host restarts during active tasks
- On startup, all `executing`/`planning` tasks transition to `blocked`
- The @claude Action may still be running on GitHub's infrastructure
- Human can check and re-assign if needed

### Stale `awaiting_approval` tasks
- These persist until the human acts (marks PR ready or closes it)
- No timeout — the plan PR is a durable artifact
- If the issue is closed, the next assignment poll won't pick it up (query filters `is:open`)

---

## Verification Checklist

1. Install Claude GitHub App on test repo
2. Add `ANTHROPIC_API_KEY` as org/repo secret
3. Add `claude.yml` workflow to test repo
4. Create issue: "Add a greeting module", assign to `anton-dalab`
5. Verify: Anton comments `@claude` with PLAN prompt (within 5 min)
6. Verify: @claude explores codebase and posts structured plan comment
7. Verify: Anton creates draft PR with plan body, notifies WhatsApp/Slack
8. Mark PR as ready for review
9. Verify: Anton detects approval, comments `@claude` with WORK+REVIEW+RESOLVE+SHIP prompt
10. Verify: @claude implements task-by-task with progress comments
11. Verify: @claude self-reviews diff and fixes findings
12. Verify: @claude marks PR ready and posts summary
13. Verify: Anton detects completion, notifies "Done"
