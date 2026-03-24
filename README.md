# Todo — Claude Code Plugin

Capture follow-up work with full context during development, then process it automatically via remote Claude sessions.

## Problem

During feature work you notice incidental things: stale flags, dead code, missing tests. Today this either scope-creeps your PR or gets lost. Todo Loop captures that context at discovery time and dispatches remote agents to process it.

## Install

```bash
claude plugin marketplace add bestdan/todo-plugin
claude plugin install todo@todo-plugin
```

Or from a local clone:

```bash
git clone https://github.com/bestdan/todo-plugin.git
claude plugin install todo --plugin-dir ./todo-plugin
```

## What you get

### Skill

Claude automatically recognizes when you mention follow-up work, deferred cleanup, or TODO items during a session and offers to capture them as structured todo files.

### Commands

| Command          | Description                                                         |
| ---------------- | ------------------------------------------------------------------- |
| `/add-todo`      | Capture follow-up work — dispatches a remote agent to commit it     |
| `/process-todo`  | Process unclaimed todos — dispatches remote agents to do the work   |
| `/list-todos`    | Show all todos with status, priority, and tags                      |

## How it works

### Capture: `/add-todo`

While on a feature branch, run `/add-todo Remove the stale foobar alias`. The plugin:

1. Gathers context (branch, diff, PR number)
2. Drafts a structured todo file with frontmatter + markdown
3. Shows you the draft for review
4. Dispatches a **remote Claude session** (`claude --remote`) that:
   - Creates branch `todo/add/<slug>` from main
   - Writes the todo file
   - Opens a PR labeled `todo-add`

**Zero local impact.** No files staged, no branches touched. You keep working. The todo lands on main via auto-merge, completely decoupled from your feature PR.

**Fallback modes:** `--remote` (cloud VM) → `--pr` (creates PR via GitHub API without touching local git) → `--local` (stages into current branch). Force a mode with the corresponding flag.

### Process: `/process-todo`

```bash
/process-todo              # highest priority unclaimed todo
/process-todo <slug>       # specific todo
/process-todo --all        # all unclaimed todos in parallel
/process-todo --local      # process locally instead of remote
```

Each todo gets its own remote Claude session running in an isolated cloud VM. The remote agent:

1. Claims the todo (creates branch `todo/<slug>`, sets status to `claimed`)
2. Reads the Context, Task, and related files
3. Does the work
4. Deletes the todo file
5. Opens a PR labeled `todo-loop`

Monitor all sessions with `/tasks`.

### List: `/list-todos`

Quick status check on all todos in the current repo. Filter by status: `/list-todos unclaimed`.

## Todo file format

Files live in `dev_docs/todos/` (supports subdirectories). Markdown with YAML frontmatter:

```markdown
---
title: Remove stale zsh alias for foobar
priority: low
status: unclaimed
created: 2026-03-23
source_branch: bestdan/feat/shell-cleanup
source_pr: 42
related_files:
  - zsh/profiles/default/aliases.zsh
expires: 2026-04-22
tags:
  - cleanup
---

## Context

Why this exists and what you noticed.

## Task

1. Concrete step one
2. Concrete step two

## Acceptance Criteria

- Tests pass
- No remaining references to foobar
```

## Auto-merge for todo additions

Todo-add PRs only create markdown files in `dev_docs/todos/`. They're safe to auto-merge. Add this workflow to repos that use the todo plugin:

```yaml
# .github/workflows/auto-merge-todos.yml
name: Auto-merge todo additions
on:
  pull_request:
    types: [labeled, opened, synchronize]

jobs:
  auto-merge:
    if: contains(github.event.pull_request.labels.*.name, 'todo-add')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify only todo files changed
        run: |
          files=$(gh pr diff ${{ github.event.pull_request.number }} --name-only)
          for f in $files; do
            if [[ ! "$f" =~ ^dev_docs/todos/ ]]; then
              echo "PR touches files outside dev_docs/todos/: $f"
              exit 1
            fi
          done
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Approve and merge
        run: |
          gh pr review ${{ github.event.pull_request.number }} --approve
          gh pr merge ${{ github.event.pull_request.number }} --squash --auto
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **Warning:** `GITHUB_TOKEN` cannot approve its own PR if branch protection requires reviews. You'll need either a PAT/GitHub App token for the approve step, or a CODEOWNERS rule that doesn't require review for `dev_docs/todos/`.

## Scheduled processing (optional)

Instead of GitHub Actions, you can schedule recurring remote tasks from the Claude web UI or CLI. This replaces the need for a `process-todo.yml` workflow:

1. Visit [claude.ai/code](https://claude.ai/code)
2. Schedule a recurring task for your repo
3. Prompt: "Scan dev_docs/todos/ for unclaimed todos. For each, create a branch todo/<slug>, claim it, do the work, delete the todo file, and open a PR."

Or use `/schedule` from the CLI to set up recurring processing.

## Architecture

```
You (feature branch)           Remote agent 1              Remote agent 2
     |                              |                           |
  /add-todo "fix X"                 |                           |
     |                              |                           |
  draft, review, confirm            |                           |
     |                              |                           |
  claude --remote ──────────> create todo/add/fix-x             |
     |                        write file, open PR               |
  keep working                      |                           |
     |                        auto-merge lands on main          |
     |                              |                           |
  /process-todo                     |                           |
     |                              |              claude --remote ──> claim, execute,
     |                              |                           |     open fix PR
  monitor with /tasks               |                           |
```

Each remote session is isolated. No worktrees, no local state, no race conditions on the filesystem.

## Update

```bash
claude plugin update todo
```

## License

MIT
