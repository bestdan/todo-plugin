---
description: Implement a single todo — claim it, do the work, and open a PR
allowed-tools: Bash(git *), Bash(gh *), Bash(claude *), Bash(find *), Bash(grep *), Glob, Grep, Read, Write, Edit
argument-hint: <slug> [--local]
---

# Implement Todo

Claim and implement a single todo file. This command is designed to be called directly or by `/manage-todo`.

## Modes

- `/implement-todo <slug>` — dispatch a remote agent to implement this todo
- `/implement-todo <slug> --local` — implement locally in the current session

A slug is required. To pick from the queue automatically, use `/manage-todo` instead.

## Steps

### 1. Find and validate the todo

Look up the todo file:

```bash
find "$(git rev-parse --show-toplevel)/dev_docs/todos" -name '<slug>.md' -type f 2>/dev/null
```

Read the file and parse its YAML frontmatter. Validate:
- File exists — if not, stop with "Todo `<slug>` not found."
- Status is `unclaimed` — if `claimed`, stop with "Todo `<slug>` is already claimed." If `blocked`, stop with "Todo `<slug>` is blocked — check its Consumer Notes."

### 2. Check for an existing branch (dedup guard)

Before doing any work, check if someone else already started on this todo:

```bash
git ls-remote --heads origin "todo/<slug>" 2>/dev/null
```

If the branch exists, stop with: "Branch `todo/<slug>` already exists — another agent is working on this. Skipping."

This prevents duplicate work when multiple scheduled jobs or parallel agents pick up the same todo.

### 3. Check dispatch prerequisites

```bash
gh auth status 2>&1
```

If this fails:
1. Check if the error mentions TLS/x509/certificate — likely sandbox issue.
2. Tell the user: "gh is failing due to sandbox TLS restrictions. Falling back to local processing."
3. Fall back to `--local` mode.

### 4. Dispatch

Read the full todo file content (frontmatter + body), then dispatch.

The remote session prompt must be self-contained because the remote VM won't have this plugin installed.

**Important:** Do NOT pass `--print` to `claude --remote` — it is not supported.

```bash
claude --remote "You are implementing a todo for the todo plugin system.

## The todo file

The file is at dev_docs/todos/<slug>.md with this content:

<paste full todo file content>

## Instructions

### Phase 1: CLAIM (do this first, push immediately)

Create the branch and claim the todo before doing any other work:

   git checkout -b todo/<slug>
   # Edit dev_docs/todos/<slug>.md: change status: unclaimed -> status: claimed
   git add dev_docs/todos/<slug>.md
   git commit -m 'claim todo: <slug>'
   git push -u origin todo/<slug>

If push fails because the branch already exists, STOP immediately — another agent claimed it. Do not continue.

This early push is critical: it prevents other agents from picking up the same todo.

### Phase 2: EXECUTE

Read the Context and Task sections. Read all files listed in related_files. Do the work described in the Task section.

### Phase 3: VALIDATE

Look for test infrastructure (Makefile, justfile, package.json). Run tests if available. Check acceptance criteria from the todo.

### Phase 4: FINALIZE

1. Delete the todo file:
   git rm dev_docs/todos/<slug>.md

2. Commit and push:
   git add only the files you changed (do NOT use git add -A — it may pick up untracked artifacts)
   git commit -m 'chore(todo): <title from frontmatter>

   Automated follow-up from todo <slug>.md.
   Source branch: <source_branch>'
   git push

3. Open PR:
   gh label create todo-loop --description 'Auto-generated from todo-loop' --color '0E8A16' 2>/dev/null
   gh pr create --title 'chore(todo): <title>' --label todo-loop --body '## Summary

   Automated follow-up from todo <slug>.md, created during branch <source_branch>.

   <bulleted list of what you did>

   ## Original Context

   > <quote the Context section from the todo>

   ## Test Plan

   - [ ] Tests pass
   - [ ] No new lint errors
   - [ ] Acceptance criteria met

   ---
   Source todo: dev_docs/todos/<slug>.md (deleted in this PR)'

## If you cannot complete the task

1. Edit the todo: change status to 'blocked'
2. Add a '## Consumer Notes' section explaining what you tried and what went wrong
3. Commit and push, but do NOT open a PR"
```

### 5. Report

Tell the user:
- The slug and title
- That a remote session has been started
- They can monitor with `/tasks`

## Local mode (`--local`)

When `--local` is specified or remote dispatch is unavailable:

1. Create branch `todo/<slug>` from current HEAD
2. Update the todo file status to `claimed`, commit and push immediately (dedup guard)
3. If push fails because the branch exists, stop — another agent claimed it
4. Execute the work, validate, delete the todo, commit, push, and open PR
5. Return to the original branch with `git checkout -`
