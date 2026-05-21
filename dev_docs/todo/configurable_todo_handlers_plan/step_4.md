# Step 4 — `/todo-config` setup command

← [[configurable_todo_handlers_plan]]

## Context

Users shouldn't hand-write `dev_docs/todos/.todo-config.yml` or remember per-backend auth steps. A new `/todo-config` command interviews the user, verifies prerequisites, and writes the config. New file: `commands/todo-config.md` (same markdown-with-frontmatter form as the other commands; register it in `CLAUDE.md` and `README.md` command tables).

## Changes

1. **`commands/todo-config.md`** frontmatter:
   - `description`: Configure where /add-todo delivers todos (repo-pr, GitHub issue, or Jira).
   - `allowed-tools`: `Bash(git *)`, `Bash(gh *)`, `Bash(acli *)`, `Bash(command *)`, `Bash(brew *)`, `Read`, `Write`.
   - `argument-hint`: `[repo-pr | gh-issue | jira]`

2. **Flow:**
   - If `$ARGUMENTS` names a handler, use it; else show current config (if any) and prompt for the destination.
   - Show current `.todo-config.yml` if present so the user sees what they're changing.
   - Per handler, collect settings and verify prerequisites:
     - **repo-pr** — no prerequisites; write `handler: repo-pr`. (Mention the optional auto-merge workflow from the README.)
     - **gh-issue** — run `gh auth status`; if it fails, surface the sandbox/TLS guidance. Prompt for repo (default current), labels, assignees.
     - **jira** — check `command -v acli`; if missing, offer the install commands (`brew tap atlassian/homebrew-acli && brew install acli`). Prompt for site, then guide auth: `acli jira auth login --site <site> --email <email> --token` (token via stdin) or `--web`. Prompt for project and default issue type.
   - **Verify before writing:** for `gh-issue`, a successful `gh auth status`; for `jira`, a successful `acli` auth check. Don't write a config that can't deliver.
   - Write `dev_docs/todos/.todo-config.yml` (create `dev_docs/todos/` if needed). Tell the user the file is repo-committed and shared by the team — they should commit it.

3. **Interactive auth caveat:** `acli jira auth login` and `gh auth login` are interactive. The command should not try to run them headless inside the agent — instead instruct the user to run them via the `! <command>` session prefix, then continue.

## Acceptance

**Code-enforced:** `dprint check` on the new markdown.

**User-run:**
- Run `/todo-config gh-issue`, answer the prompts, and confirm `.todo-config.yml` is written with a valid `gh-issue` block and that `/add-todo` then routes to a GitHub issue.
- Run `/todo-config jira` without `acli` installed and confirm it offers install + auth guidance and does not write a half-broken config.
- Run `/todo-config` with no args and confirm it shows current config and lets you switch handlers.

## Dependencies

[[step_1]] (config schema). Best landed after [[step_2]] and [[step_3]] so it can configure all three, but only hard-depends on step 1.
