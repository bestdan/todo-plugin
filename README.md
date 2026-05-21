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
| `/add-todo`      | Capture follow-up work — delivers it via the configured handler     |
| `/process-todo`  | Process unclaimed todos — dispatches remote agents to do the work   |
| `/list-todos`    | Show all todos with status, priority, and tags                      |
| `/todo-config`   | Configure where `/add-todo` delivers todos (repo PR, GitHub, Jira)  |

## How it works

### Capture: `/add-todo`

While on a feature branch, run `/add-todo Remove the stale foobar alias`. The plugin:

1. Gathers context (branch, diff, PR number)
2. Drafts a structured todo with frontmatter + markdown
3. Shows you the draft for review
4. Resolves the configured **handler** and delivers the todo to it, reporting back the artifact URL

Capture is destination-agnostic — where the todo lands is decided by the handler (see [Destinations](#destinations)). With no config, the default `repo-pr` handler reproduces the original behavior below.

### Destinations

`/add-todo` delivers each todo via a **handler** named in a repo-committed config file, `dev_docs/todos/.todo-config.yml`. Run `/todo-config` to set it up. No config → `repo-pr`.

| Handler    | Lands as                              | Prerequisites                          |
| ---------- | ------------------------------------- | -------------------------------------- |
| `repo-pr`  | Markdown file via a `todo-add` PR (default) | `gh` auth (falls back to local staging) |
| `gh-issue` | A GitHub Issue                        | `gh` auth                              |
| `jira`     | A Jira work item under an epic        | `acli` installed + authenticated       |

```yaml
# dev_docs/todos/.todo-config.yml — pick one handler
handler: gh-issue
gh-issue:
  repo: owner/name      # optional; defaults to current repo
  labels: [follow-up]   # optional
  assignees: []         # optional
```

```yaml
handler: jira
jira:
  site: mycompany.atlassian.net
  project: PLAT            # required
  issue_type: Task         # default Task
  default_epic: PLAT-100   # optional; skips the epic prompt
  labels: []
```

The file is committed and shared by the team, so everyone in the repo files to the same place. Unknown handler value → `/add-todo` stops and points you to `/todo-config` (no silent fallback). `/process-todo` and `/list-todos` operate only on file-based `repo-pr` todos; with the external handlers, tracking lives in GitHub or Jira.

#### `repo-pr` handler (default)

Dispatches a **remote Claude session** (`claude --remote`) that:
- Creates branch `todo/add/<slug>` from main
- Writes the todo file to `dev_docs/todos/<slug>.md`
- Opens a PR labeled `todo-add`

**Zero local impact.** No files staged, no branches touched. You keep working. The todo lands on main via auto-merge, completely decoupled from your feature PR.

**Fallback modes** (`repo-pr` only): `--remote` (cloud VM) → `--subagent` (creates PR via GitHub API without touching local git) → `--local` (stages into current branch). Force a mode with the corresponding flag. The `gh-issue` and `jira` handlers are single foreground calls and don't use this cascade.

#### Adding a new handler

A handler is a `### Handler: <name>` section in `commands/add-todo.md` plus a config block. The deferred MCP-backed destinations (Linear, Asana, Todoist, Notion) follow one common pattern: a remote Streamable-HTTP MCP server added with `claude mcp add --transport http <name> <url>` then authenticated with `/mcp`. The handler should look up the create-tool at runtime (`tools/list`) and match by name/description rather than hardcoding it, since vendors rename tools. Verified endpoints for when these are built:

| Destination | MCP endpoint                                  | Create tool (verify at runtime)  |
| ----------- | --------------------------------------------- | -------------------------------- |
| Linear      | `https://mcp.linear.app/mcp`                  | `create_issue`                   |
| Jira (MCP)  | `https://mcp.atlassian.com/v1/mcp/authv2`     | `createJiraIssue`                |
| Asana       | `https://mcp.asana.com/v2/mcp`                | `create_task`                    |
| Todoist     | `https://ai.todoist.net/mcp`                  | `add-tasks`                      |
| Notion      | `https://mcp.notion.com/mcp`                  | `notion-create-pages`            |

The flow above is the default `repo-pr` handler. Configure a different destination with `/todo-config` — `gh-issue` and `jira` deliver via a single foreground call (no branch, no PR, no fallback cascade).

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
