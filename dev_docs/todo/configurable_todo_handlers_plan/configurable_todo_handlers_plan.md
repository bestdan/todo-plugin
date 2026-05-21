# Configurable destination handlers for `/add-todo`

## Goal

Let `/add-todo` deliver a captured todo to whatever system the user tracks work in, instead of always committing a markdown file via PR. The capture step (gather context → draft → review) stays unchanged; only the final delivery step becomes pluggable via a **handler** selected from repo config.

## Scope (v1)

Three handlers, all CLI/git-based — **no MCP dependency**:

- **`repo-pr`** — current behavior (markdown file in `dev_docs/todos/` landed via a `todo-add` PR). Default when no config exists, so nothing breaks for existing users.
- **`gh-issue`** — create a GitHub Issue via `gh issue create`.
- **`jira`** — create a Jira work item via the official Atlassian CLI (`acli jira workitem create`).

Selection via a repo-committed config file: `dev_docs/todos/.todo-config.yml`. A new `/todo-config` command writes it and verifies prerequisites.

## Non-goals (v1)

- MCP-backed handlers (Linear, Asana, Todoist, Notion). Deferred to a later phase — see [[step_5]] for the seam that keeps them cheap to add.
- Per-user config override (`~/.claude/todo-config.yml`). v1 is repo-committed only.
- Read-back / lifecycle sync for external trackers. `/process-todo` and `/list-todos` stay exactly as today (`repo-pr` file-based); processing/listing external destinations is explicitly out of scope.
- Changing the draft/capture UX or the todo file format.

## Approach

Introduce a **handler** indirection between capture and delivery. `add-todo.md` keeps steps 1–5 (gather → slug → draft → review) verbatim, then:

1. Reads `dev_docs/todos/.todo-config.yml` (absent → `repo-pr`).
2. Resolves the named handler.
3. Maps the drafted todo (`title`, body, `priority`, `tags`, `source_branch`, `source_pr`) to that backend's create call.
4. Delivers and reports back the artifact URL (PR / issue / work-item).

The existing remote→subagent→local dispatch cascade is **not deleted** — it moves *inside* the `repo-pr` handler, which is the only handler that needs git plumbing. `gh-issue` and `jira` are single foreground CLI calls.

**Main tradeoff considered:** route GitHub Issues through the GitHub MCP server vs. `gh issue create`. Chose `gh` — it's already a plugin dependency, needs no OAuth/MCP setup, and is one command. Same reasoning drove the v1 decision to use `acli` for Jira rather than the Atlassian MCP server: CLI handlers need no MCP server registration or `/mcp` OAuth dance, so v1 ships with zero new runtime infrastructure.

## Steps

1. [[step_1]] — Define the handler abstraction + config schema; extract current behavior into the `repo-pr` handler (pure refactor, no behavior change).
2. [[step_2]] — Add the `gh-issue` handler.
3. [[step_3]] — Add the `jira` handler (via `acli`).
4. [[step_4]] — Add the `/todo-config` setup command.
5. [[step_5]] — Docs, and define the deferred-MCP extension seam.

## Open questions

Resolved with the user in the planning review:

- **Auth failure → stop, don't fall back.** A handler whose backend auth fails stops with guidance; it never silently reverts to `repo-pr`, since the destination was chosen deliberately.
- **Jira tickets go under an epic.** The `jira` handler queries the project's open epics and places the new ticket under the chosen one (`--parent`); see [[step_3]].
- **Process/list for external handlers — out of scope.** `/process-todo` and `/list-todos` are unchanged.

Remaining (need the user's authenticated work machine, non-blocking for the design):

- **`acli` JSON shapes** for `workitem create --json` and `workitem search` (epic list) — the field holding the issue key/URL and the search result structure aren't shown in public docs. The user will confirm these on their work computer; [[step_3]] keeps parsing tolerant until then.
- **`acli` not installed locally** (confirmed absent here) — the `jira` handler and `/todo-config` detect this and guide install rather than failing opaquely.
