# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin (`bestdan/todo-plugin`) that captures follow-up work during development and processes it via remote Claude sessions. No build system, no tests, no dependencies — it's pure markdown that Claude Code interprets as commands and skills.

## Plugin structure

- `.claude-plugin/plugin.json` — plugin identity (name, version, author)
- `.claude-plugin/marketplace.json` — marketplace listing
- `commands/` — slash commands (markdown files with frontmatter declaring allowed tools)
- `commands/handlers/` — one markdown file per `/add-todo` delivery handler (`repo-pr.md`, `gh-issue.md`, `jira.md`). Loaded lazily by `/add-todo` after handler resolution so users only pay for the prose of the handler they've configured. Adding a new handler = new file here + add the name to the valid-values list in `add-todo.md` step 6.
- `skills/todo/SKILL.md` — auto-trigger skill that activates when users mention follow-up work

## Commands

| Command | File | What it does |
|---------|------|-------------|
| `/add-todo` | `commands/add-todo.md` | Captures a todo, then delivers it via the configured handler (default `repo-pr`) |
| `/process-todo` | `commands/process-todo.md` | Claims and executes unclaimed todos via remote agents |
| `/list-todos` | `commands/list-todos.md` | Shows all todos with status, priority, tags |

## Key conventions

- **Handler abstraction:** `/add-todo` separates capture from delivery. After drafting, it resolves a *handler* from `dev_docs/todos/.todo-config.yml` and hands it a normalized drafted todo (`title`, `body`, `priority`, `size`, `tags`, `slug`, `created`, `expires`, `source_branch`, `source_pr`, `related_files`). Each handler must return the created artifact's URL.
- **Config resolution:** file absent or no `handler:` → `repo-pr` (preserves original behavior). Unknown handler value → stop with an error pointing to `/todo-config`; never silently fall back. Valid: `repo-pr`, `gh-issue`, `jira`.
- `repo-pr` is the only handler that does git plumbing and uses the remote/subagent/local cascade; CLI handlers (`gh-issue`, `jira`) are single foreground calls.
- Todo files live in `dev_docs/todos/` in the **target repo** (not this plugin repo). Scanning is always recursive (`**/*.md`). The `repo-pr` handler is file-based; `/process-todo` and `/list-todos` only operate on it.
- Branch naming: `todo/add/<slug>` for adding todos, `todo/<slug>` for processing them.
- `repo-pr` dispatch modes in priority order: `--remote` (cloud VM) → `--subagent` (GitHub API, zero local impact) → `--local` (stage into current branch).
- PR labels: `todo-add` for addition PRs, `todo-loop` for processing PRs.
- Frontmatter fields: `title`, `priority` (low/medium/high), `size` (small/medium/large), `status` (unclaimed/claimed/blocked), `created`, `source_branch`, `source_pr`, `related_files`, `expires` (30-day default), `tags`.
- Remote sessions don't have plugins installed — all instructions must be embedded inline in the `claude --remote` prompt.

## Editing commands/skills

Each command file is a self-contained markdown document with YAML frontmatter:
- `description` — shown in command listings
- `allowed-tools` — permissions the command gets (e.g., `Bash(git *)`, `Bash(gh *)`)
- `argument-hint` — help text for arguments

The body is natural language instructions that Claude follows step-by-step. Changes to command behavior = changes to the markdown prose.
