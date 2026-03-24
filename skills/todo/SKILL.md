---
name: todo
description: Capture and process follow-up work discovered during development. Use when a user notices incidental work (stale config, tech debt, dead code, test gaps) they want to defer without losing context. Provides the todo file format, creation workflow, and processing logic via remote Claude sessions.
---

# Todo Loop — Capture and Process Follow-Up Work

Repo-native system for capturing follow-up work with full context and processing it automatically via remote Claude sessions.

## When to use

- User notices incidental work during a feature branch (stale flags, dead code, missing tests)
- User says "todo", "follow-up", "we should come back to this", "add a todo for this"
- User runs `/add-todo` or `/process-todo`

## How it works

### Capture (`/add-todo`)

1. Gathers context from the current session (branch, diff, PR, conversation)
2. Drafts a structured todo file, presents it for user review
3. Dispatches a remote Claude session (`claude --remote`) to:
   - Create a branch from main (`todo/add/<slug>`)
   - Write the todo file to `dev_docs/todos/<slug>.md`
   - Open a PR labeled `todo-add`
4. An auto-merge workflow merges the PR (it only touches `dev_docs/todos/`)
5. The todo lands on main, decoupled from the feature branch

**Zero local impact.** No files written, no branches created, no staging. The user keeps working uninterrupted.

**Fallback modes** (automatic cascade): `--remote` (cloud VM) → `--subagent` (GitHub API via sub-agent, zero local git impact) → `--local` (stage into current branch). If `gh auth status` fails, skip straight to `--local`. Do NOT pass `--print` to `claude --remote`.

### Process (`/process-todo`)

1. Scans `dev_docs/todos/**/*.md` for unclaimed todos
2. For each selected todo, dispatches a remote Claude session that:
   - Claims the todo (branch `todo/<slug>`, sets `status: claimed`)
   - Does the work described in the Task section
   - Deletes the todo file
   - Opens a PR labeled `todo-loop`
3. Multiple todos can be dispatched in parallel — each gets its own cloud VM

### List (`/list-todos`)

Quick status check. Shows all todos with priority, status, tags, and expiry.

## Todo file format

Files live in `dev_docs/todos/` (supports subdirectories). Markdown with YAML frontmatter.

```markdown
---
title: Imperative description under 80 chars
priority: low
status: unclaimed
created: 2026-03-23
source_branch: bestdan/feat/example
source_pr: 42
related_files:
  - path/to/relevant/file.ts
  - path/to/another/file.ts
expires: 2026-04-22
tags:
  - cleanup
---

## Context

Why this exists. What you saw. Written for someone who has never seen this code.

## Task

1. Concrete step one
2. Concrete step two
3. Run tests

## Acceptance Criteria

- No remaining references to X
- Tests pass
```

### Field reference

| Field           | Required | Description                                             |
| --------------- | -------- | ------------------------------------------------------- |
| `title`         | yes      | Imperative description, < 80 chars                      |
| `priority`      | yes      | `low` / `medium` / `high`                               |
| `status`        | yes      | `unclaimed` / `claimed` / `blocked`                     |
| `created`       | yes      | ISO date                                                |
| `source_branch` | yes      | Branch where todo was identified                        |
| `source_pr`     | no       | PR number if already open                               |
| `related_files` | yes      | Paths the consumer should read for context              |
| `expires`       | yes      | ISO date. Default: 30 days from creation.               |
| `tags`          | no       | Freeform tags for filtering (e.g., `cleanup`, `tests`)  |

### Body sections

- **Context** (required) — Why this exists. What you saw.
- **Task** (required) — Concrete steps. Specific enough for an agent to execute.
- **Acceptance Criteria** (optional) — Definition of done.

## Lifecycle

```
unclaimed --> claimed --> PR opened --> merged (todo file deleted)
    |             |
    |             +--> blocked (needs manual intervention)
    |
    +--> expired (auto-pruned after 30 days)
```

## Branch naming

Two namespaces to avoid collisions:

- `todo/add/<slug>` — the PR that adds the todo file (auto-merged)
- `todo/<slug>` — the PR that does the work and deletes the todo file

## Scanning

Always scan recursively: `dev_docs/todos/**/*.md`. Subdirectories are optional organizational structure.

## Race conditions

Each remote session gets its own isolated VM with a fresh clone. Filesystem races are impossible. The only contention point is `git push`:

1. Branch names are deterministic: `todo/<slug>`
2. `git push` is atomic — second push fails
3. On push failure, skip this todo and move to the next unclaimed one

## Remote session notes

Remote sessions (`claude --remote`) run in cloud VMs and don't have access to locally-installed plugins. The `/add-todo` and `/process-todo` commands handle this by embedding all necessary instructions directly in the remote prompt. The remote agent doesn't need to know about this plugin — it just follows the instructions in its prompt.
