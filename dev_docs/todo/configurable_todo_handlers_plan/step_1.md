# Step 1 — Handler abstraction + config schema + `repo-pr` handler

← [[configurable_todo_handlers_plan]]

## Context

`commands/add-todo.md` currently hardcodes delivery: steps 6–9 detect a dispatch mode (remote / subagent / local) and create a markdown file in `dev_docs/todos/` via a `todo-add` PR. This step introduces the handler indirection **without changing any observable behavior** — the default path must remain identical to today.

Relevant files:
- `commands/add-todo.md` — steps 1–5 stay; steps 6–9 become "resolve handler → delegate".
- `skills/todo/SKILL.md` — describes the capture/dispatch flow; gains a "handlers" concept.
- `CLAUDE.md` — documents conventions.

This plugin is markdown-only: a "handler" is a documented section of prose the command follows, not a code module. The abstraction is a **stable contract** (inputs the handler receives, what it must return) plus one section per handler.

## Changes

1. **Define the drafted-todo contract** in `add-todo.md` after step 5. After review, the command holds a normalized object every handler consumes:
   - `title` (imperative, < 80 chars)
   - `body` (the Context / Task / Acceptance markdown)
   - `priority` (`low` | `medium` | `high`)
   - `tags` (list)
   - `slug`, `created`, `expires`
   - `source_branch`, `source_pr` (rendered into a footer link block on external backends)
   Every handler must **return the delivered artifact's URL** (PR, issue, or work-item) for the final report.

2. **Define the config schema.** New file read at delivery time: `dev_docs/todos/.todo-config.yml`.
   ```yaml
   handler: repo-pr   # repo-pr | gh-issue | jira
   # handler-specific blocks added in later steps
   ```
   Resolution rule: file absent OR `handler:` missing → `repo-pr`. Unknown handler name → stop and tell the user to fix config or run `/todo-config`.

3. **Replace steps 6–9** with:
   - **Step 6: Resolve handler.** `cat "$(git rev-parse --show-toplevel)/dev_docs/todos/.todo-config.yml" 2>/dev/null`; parse `handler:`; default `repo-pr`.
   - **Step 7: Delegate to the handler section** (below).
   - **Step 8: Report** the returned artifact URL and which handler ran.

4. **Move existing dispatch logic into a `### Handler: repo-pr` section** — verbatim relocation of today's remote→subagent→local cascade, the "fix now" branching, and the mode-selection summary. The CLI handlers added later are single foreground calls and do not use this cascade.

5. Update `argument-hint` / `allowed-tools` only if needed (no new tools yet — `repo-pr` uses the same `git`/`gh`/`claude`/`Agent` set).

## Acceptance

**Code-enforced:** No automated test harness exists in this repo (pure markdown). Lint = `dprint check` on touched markdown.

**User-run:**
- With no `.todo-config.yml` present, run `/add-todo "test handler refactor"` and confirm the flow is byte-for-byte the same experience as before (drafts, asks file-vs-fix-now, dispatches a `todo-add` PR). This is the regression gate for the refactor.
- Create `.todo-config.yml` with `handler: repo-pr` and confirm identical behavior.
- Create `.todo-config.yml` with `handler: bogus` and confirm `/add-todo` stops with a clear "unknown handler" message instead of silently defaulting.

## Dependencies

None. Must land before steps 2–4.
