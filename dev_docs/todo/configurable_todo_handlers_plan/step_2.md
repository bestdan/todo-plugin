# Step 2 — `gh-issue` handler

← [[configurable_todo_handlers_plan]]

## Context

GitHub Issues are reachable with the `gh` CLI, already a dependency of this plugin (used throughout `add-todo.md` / `process-todo.md`). No MCP server, no extra auth — if `gh auth status` works, this handler works. This is the cheapest external destination and proves the handler contract from [[step_1]].

## Changes

1. **Config block** in `dev_docs/todos/.todo-config.yml`:
   ```yaml
   handler: gh-issue
   gh-issue:
     repo: bestdan/todo-plugin   # optional; defaults to current repo (gh infers it)
     labels: [follow-up]         # optional; created if missing
     assignees: []               # optional
   ```

2. **`### Handler: gh-issue` section** in `add-todo.md`:
   - Preflight: `gh auth status`. On failure, surface the same TLS/sandbox guidance already used elsewhere in the command, and stop (do **not** silently fall back to `repo-pr` — destination was explicitly chosen).
   - Map the drafted todo:
     - `--title` ← `title`
     - `--body` ← `body` + a footer block: `Source branch: <source_branch>` / `Source PR: #<source_pr>` (omit lines that are empty).
     - `--label` ← each `gh-issue.labels` entry (ensure each exists: `gh label create <l> 2>/dev/null` before use).
     - `--assignee` ← each `gh-issue.assignees` entry.
     - `--repo` ← `gh-issue.repo` if set.
   - Command (write body via stdin/heredoc to avoid quoting issues):
     ```bash
     gh issue create --repo "<repo>" --title "<title>" --label "<label>" --body "$BODY"
     ```
   - `gh issue create` prints the new issue URL to stdout — capture and return it as the handler's artifact URL.

3. This handler runs in the **foreground in the current session** (single API call, no git plumbing) — it does not use the `repo-pr` remote/subagent cascade.

## Acceptance

**Code-enforced:** `dprint check` on touched markdown.

**User-run:**
- With `handler: gh-issue` configured, run `/add-todo "verify gh-issue handler"`; confirm an issue is created in the configured repo with the title, full body, footer link, and labels, and that `/add-todo` reports the issue URL.
- Temporarily break auth (e.g. `GH_TOKEN=bad`) and confirm the handler stops with the auth guidance rather than creating nothing silently or falling back to a PR.
- Confirm no `dev_docs/todos/*.md` file is created and no branch/PR is opened (this handler does not touch git).

## Dependencies

[[step_1]] (handler contract + config resolution).
