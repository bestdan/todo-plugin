# Step 3 — `jira` handler (via `acli`)

← [[configurable_todo_handlers_plan]]

## Context

Jira work items are created with the official Atlassian CLI, `acli` (the Rovo/Atlassian CLI, **not** the old go-jira community `jira` CLI). Verified against official docs (developer.atlassian.com/cloud/acli):

- Auth: `acli jira auth login --site <site>.atlassian.net --email <email> --token` (token via stdin), or `--web` for interactive OAuth.
- Create: **`acli jira workitem create`** (note: "issue" was renamed to "work item").
- Flags: `-p/--project`, `-t/--type` (Epic|Story|Task|Bug), `-s/--summary`, `-d/--description` (plain text or ADF), `--description-file`, `-a/--assignee` (supports `@me`), `-l/--label`, `--parent`, `--json`.
- Install (macOS): `brew tap atlassian/homebrew-acli && brew install acli`.

**Epic placement (required):** before creating the work item, the handler must discover the available epics in the configured project and place the new ticket under the right one (via `--parent <EPIC-KEY>`). See "Epic selection" below.

**Known unknowns (handle defensively):**
- `acli` is **not installed** on the target machine (confirmed). The handler must detect absence and guide install rather than erroring opaquely.
- `--json` is documented but the docs do not show which field carries the created issue key/URL, nor the exact shape of `workitem search` output. Parse JSON if it looks like JSON; otherwise scrape the issue key from stdout. **The user will confirm the real JSON shapes on their work machine where `acli` is authenticated** — leave the parsing tolerant until then.

## Changes

1. **Config block**:
   ```yaml
   handler: jira
   jira:
     site: mycompany.atlassian.net   # used by /todo-config for auth; informational here
     project: PLAT                   # required
     issue_type: Task                # default Task
     default_epic: PLAT-100          # optional; skips the epic prompt
     labels: []                      # optional
   ```

2. **`### Handler: jira` section** in `add-todo.md`:
   - Preflight: `command -v acli` — if missing, stop with: "Jira handler needs the Atlassian CLI. Install: `brew tap atlassian/homebrew-acli && brew install acli`, then run `/todo-config` to authenticate." Also run `acli jira auth status` if such a check exists; if not authenticated, point to `/todo-config`.
   - **Epic selection (before create):** query open epics in the project and have the user pick the parent.
     ```bash
     acli jira workitem search --jql 'project = "<project>" AND issuetype = Epic AND statusCategory != Done' --json
     ```
     (Confirm the exact `search` subcommand/flag and JSON field names on the work machine — `acli jira workitem search` vs `list` and the JQL flag spelling are unverified from docs.) Present the epic keys + summaries; let the user choose one, or choose "none" to create the ticket with no parent. Pass the chosen key as `--parent <EPIC-KEY>`. Optionally allow `jira.default_epic` in config to skip the prompt.
   - Map the drafted todo:
     - `--summary` ← `title`
     - description ← `body` + source footer. **Use `--description-file`** with the body written to a temp file (the markdown body is multi-line and may contain quotes/backticks; a file avoids shell-quoting and ADF-escaping pitfalls).
     - `--project` ← `jira.project`
     - `--type` ← `jira.issue_type` (default `Task`)
     - `--parent` ← chosen epic key (omit if "none")
     - `--label` ← each `jira.labels`
   - Command:
     ```bash
     acli jira workitem create \
       --project "<project>" --type "<issue_type>" \
       --summary "<title>" --description-file "$TMPBODY" --json
     ```
   - Parse the result for the issue key; construct/return the URL `https://<site>/browse/<KEY>`. If `--json` parsing fails, scrape the `KEY-123` pattern from stdout.
   - `allowed-tools` in `add-todo.md` frontmatter must add `Bash(acli *)`.

3. Foreground, current session — no git plumbing, no `repo-pr` cascade.

## Acceptance

**Code-enforced:** `dprint check` on touched markdown.

**User-run:**
- On a machine without `acli`, run `/add-todo` with `handler: jira` and confirm the install-guidance message appears (no crash).
- After `brew install acli` and `acli jira auth login`, run `/add-todo "verify jira handler"`; confirm it lists the project's open epics, lets you pick a parent, and creates a work item under that epic with summary, full description (incl. source footer), and labels, and that `/add-todo` reports the browse URL.
- Confirm choosing "none" creates a top-level ticket with no parent.
- Confirm the multi-line markdown body survives intact in the Jira description (the `--description-file` path).

## Dependencies

[[step_1]]. Independent of [[step_2]].
