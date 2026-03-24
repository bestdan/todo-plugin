---
description: Manage the todo queue — scan, prioritize, check for stale claims, and dispatch implementation
allowed-tools: Bash(git *), Bash(gh *), Bash(claude *), Bash(find *), Bash(grep *), Glob, Grep, Read, Write, Edit
argument-hint: [--all | --check | --prune] or empty for next unclaimed
---

# Manage Todo

Orchestrate the todo queue. Scans for unclaimed work, guards against duplicate dispatches, and kicks off `/implement-todo` for each selected item.

Designed to be safe for scheduled/cron execution — multiple runs will not create duplicate PRs.

## Modes

- `/manage-todo` — dispatch the highest priority unclaimed todo (safe for scheduled jobs)
- `/manage-todo --all` — dispatch all unclaimed todos in sequence
- `/manage-todo --check` — dry-run: show what would be dispatched without dispatching
- `/manage-todo --prune` — clean up expired todos (status → expired, log it)

## Steps

### 1. Scan for todos

```bash
find "$(git rev-parse --show-toplevel)/dev_docs/todos" -name '*.md' -type f 2>/dev/null
```

Parse YAML frontmatter from each file. Build the full inventory with `title`, `priority`, `status`, `created`, `expires`, `slug` (filename without `.md`).

### 2. Check for expired todos

For each todo where `expires` < today and `status` is `unclaimed`:
- Mark as expired in the inventory
- If `--prune` was passed, update the file: set `status: expired` and commit

### 3. Filter to actionable todos

From the inventory, select todos where `status: unclaimed`. Sort by:
1. Priority: `high` > `medium` > `low`
2. Age: oldest `created` date first

If no unclaimed todos exist, report the queue status and stop:
```
Todo queue is empty.
  - 0 unclaimed
  - 2 claimed (in progress)
  - 1 blocked
```

### 4. Dedup check — guard against duplicate dispatches

This is the critical step for scheduled job safety. For each candidate todo, check if an agent is already working on it:

```bash
git ls-remote --heads origin "todo/<slug>" 2>/dev/null
```

If the branch exists, that todo is already being worked on — skip it. Also check for an open PR:

```bash
gh pr list --head "todo/<slug>" --state open --json number --jq '.[0].number' 2>/dev/null
```

Remove any already-in-progress todos from the candidate list.

### 5. Select todos to dispatch

- Default: pick the single highest priority candidate after dedup filtering
- With `--all`: select all remaining candidates
- With `--check`: show the list and stop (dry-run)

If `--check`, display:
```
Would dispatch 2 todos:
  1. fix-broken-import (high, created 2026-03-20) — ready
  2. remove-stale-alias (low, created 2026-03-23) — ready

Skipped (already in progress):
  - add-missing-test — branch todo/add-missing-test exists
```

### 6. Dispatch

For each selected todo, dispatch using `/implement-todo <slug>`.

When dispatching multiple todos (`--all`), run them in sequence so the user can see each dispatch. Each remote session runs independently in its own cloud VM.

### 7. Report

Summary of what happened:

```
Dispatched 2 todos:
  - fix-broken-import (high) — remote session started
  - remove-stale-alias (low) — remote session started

Skipped (already in progress):
  - add-missing-test — branch exists

Queue status: 0 unclaimed, 3 claimed, 1 blocked
Monitor with /tasks.
```

## Scheduled job safety

This command is designed to be called repeatedly from a scheduled Claude Code web job without creating duplicate work:

1. **Branch-exists check** (`git ls-remote`): If `todo/<slug>` branch exists, skip that todo. This catches in-progress work from previous runs.
2. **Open PR check** (`gh pr list`): If a PR is already open for that branch, definitely skip.
3. **`implement-todo` also guards**: Even if `manage-todo`'s check races with another instance, `implement-todo` will fail-fast if `git push` fails on branch creation.

Three layers of dedup: queue-level scan → branch-exists check → push-time atomic guard.

### Example scheduled job config

A scheduled Claude Code web job running `/manage-todo` every 8 hours is safe:
- Run 1 (0:00): Picks up `fix-import`, dispatches it. Branch `todo/fix-import` created.
- Run 2 (8:00): Sees `todo/fix-import` branch exists, skips it. Picks up next unclaimed todo if any.
- Run 3 (16:00): `fix-import` PR merged, branch deleted. If new todos were added, picks one up.
