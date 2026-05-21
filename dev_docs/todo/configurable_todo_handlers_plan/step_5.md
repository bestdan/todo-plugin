# Step 5 — Docs + deferred-MCP extension seam

← [[configurable_todo_handlers_plan]]

## Context

Final step: make the new capability discoverable, and document the seam so the deferred MCP-backed handlers (Linear, Asana, Todoist, Notion) are cheap to add later without re-architecting.

Files: `README.md`, `CLAUDE.md`, `skills/todo/SKILL.md`.

## Changes

1. **`README.md`:**
   - New "Destinations" section explaining handlers and that `repo-pr` is the default (no config = today's behavior).
   - Document `dev_docs/todos/.todo-config.yml` with an example per handler.
   - Add `/todo-config` to the command table.
   - Note the `gh-issue` / `jira` prerequisites (`gh` auth; `acli` install + auth).

2. **`CLAUDE.md`:** add handler architecture to "Key conventions" — the drafted-todo contract, config resolution rule (absent → `repo-pr`, unknown → error), and that CLI handlers run foreground while `repo-pr` owns the remote/subagent/local cascade. Add `/todo-config` to the commands table.

3. **`skills/todo/SKILL.md`:** update the "How it works → Capture" section to describe handler resolution. Note that `/process-todo` and `/list-todos` continue to operate on `repo-pr` (file-based) todos as today — read-back / lifecycle sync for external handlers is **out of scope** for this work and not changed here.

4. **Document the MCP extension seam (deferred, not implemented):** add a short "Adding a new handler" note. A future MCP handler is just another `### Handler: <name>` section plus a config block naming the registered MCP server. From research, the future common pattern is: remote Streamable HTTP + OAuth, added via `claude mcp add --transport http <name> <url>` then `/mcp`; the handler does a runtime `tools/list` and matches the create-tool by name/description rather than hardcoding (vendors rename them — e.g. Asana V1→V2, Notion v2.0). Record the verified endpoints for when it's built:
   - Linear `https://mcp.linear.app/mcp` (create tool ~`create_issue`, confirm at runtime)
   - Jira (MCP alternative to acli) `https://mcp.atlassian.com/v1/mcp/authv2` (`createJiraIssue`)
   - Asana `https://mcp.asana.com/v2/mcp` (`create_task`)
   - Todoist `https://ai.todoist.net/mcp` (`add-tasks`)
   - Notion `https://mcp.notion.com/mcp` (`notion-create-pages`)

## Acceptance

**Code-enforced:** `dprint check` on all touched markdown.

**User-run:**
- Read README "Destinations" and confirm a new user could pick a handler and run `/todo-config` from the docs alone.

## Dependencies

[[step_1]] through [[step_4]] (documents their behavior).
