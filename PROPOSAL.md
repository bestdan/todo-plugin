# Proposal: Todo Loop Framework

**Author:** Dan Egan
**Date:** 2026-03-23
**Status:** Draft

---

## Problem

During development across personal projects, I frequently discover incidental work: stale config, tech debt, test gaps, dead code. Today this work has two outcomes, both bad:

1. **Scope creep** -- the fix gets jammed into the current branch and PR, muddying the diff.
2. **Lost context** -- a mental note or GitHub issue gets created, stripped of code-level context, and rots.

The moment of discovery is the moment of highest context. I need a way to capture that context, keep moving on the current PR, and have the follow-up work happen automatically.

## Proposal

A repo-native system with three parts:

1. **`dev_docs/todos/`** -- a directory of structured markdown files, each describing one unit of follow-up work.
2. **`/add-todo`** -- a Claude Code skill that creates a todo file from the current session context.
3. **`/process-todo`** -- a Claude Code skill (run manually or via GitHub Actions) that claims unclaimed todos, executes them in isolated worktrees, and opens PRs. 

The todo file deletion merges with the feature PR. The consumer picks it up from `main`, does the work, and opens a PR that also deletes the todo file. Self-cleaning.

This lives in the dotfiles repo as reusable skills. Each project that opts in just needs a `dev_docs/todos/` directory.

---

## Todo File Format

**Location:** `dev_docs/todos/<content-slug>.md`

```markdown
---
title: Remove stale zsh alias for deprecated tool
priority: low
status: unclaimed
created: 2026-03-23
source_branch: bestdan/feat/shell-cleanup
source_pr: 42
related_files:
  - zsh/profiles/default/aliases.zsh
  - zsh/profiles/betterment/aliases.zsh
expires: 2026-04-22
tags:
  - cleanup
  - zsh
---

## Context

While working on the shell cleanup branch, I noticed `alias foobar` references
a tool I uninstalled months ago. The alias is defined in both profiles.

## Task

1. Remove the `foobar` alias from both profile alias files
2. Check for any other references to `foobar` in the repo
3. Verify shell loads cleanly: `source ~/.zshrc`

## Acceptance Criteria

- No remaining references to `foobar`
- Shell loads without errors
```

### Field Reference

| Field           | Required | Description                                             |
| --------------- | -------- | ------------------------------------------------------- |
| `title`         | yes      | Imperative description, < 80 chars                      |
| `priority`      | yes      | `low` / `medium` / `high`                               |
| `status`        | yes      | `unclaimed` / `claimed` / `blocked`                     |
| `created`       | yes      | ISO date                                                |
| `source_branch` | yes      | Branch where todo was identified                        |
| `source_pr`     | no       | PR number if already open                               |
| `related_files` | yes      | Paths the consumer should read for context              |
| `expires`       | yes      | ISO date. Default: 30 days from creation.               |
| `tags`          | no       | Freeform tags for filtering (e.g., `cleanup`, `tests`)  |

### Body Sections

- **Context** (required) -- Why this exists. What you saw. Written as if explaining to someone who has never seen this code.
- **Task** (required) -- Concrete steps. Specific enough for an agent to execute.
- **Acceptance Criteria** (optional) -- Definition of done. Useful for verification.

### Why markdown with frontmatter?

Frontmatter gives machines structured data for filtering, sorting, and claiming. The markdown body gives Claude Code (or me) the rich context needed to actually do the work.

---

## `/add-todo` Skill

### Workflow

1. **Gather context automatically**
   - Current branch name, current diff, current repo
   - Open PR number (if any) via `gh pr view`
   - If the user provided a description, use it as the title seed

2. **Generate slug**
   - Derive a short kebab-case slug from the title (e.g., `remove-stale-foobar-alias`)
   - Strip filler words, keep it scannable in a directory listing
   - Append `-2`, `-3` if collision

3. **Draft and confirm**
   - Auto-populate: `created`, `source_branch`, `source_pr` (if a PR exists for the current branch), `status: unclaimed`, `expires` (30 days), `priority: low`
   - Fill `related_files` from current diff or conversation context
   - Draft Context and Task from conversation
   - Present to user for review before writing

4. **Dispatch to remote agent**
   - Run `claude --remote` with a self-contained prompt that instructs the remote agent to:
     1. Create branch `todo/add/<slug>` from main
     2. Write the todo file to `dev_docs/todos/<slug>.md`
     3. Commit, push, and open a PR labeled `todo-add`
   - The remote agent operates on a fresh clone in a cloud VM -- zero local impact
   - The user keeps working uninterrupted on their feature branch

5. **Auto-merge lands the todo on main**
   - A GitHub Action (see Auto-Merge below) verifies the PR only touches `dev_docs/todos/` and merges it
   - The todo is now on main, decoupled from the feature branch timeline

### Why decouple from the feature branch?

The old design staged the todo file into the feature PR. Problems:
- Todo blocked until the feature PR merges (could be days/weeks)
- Feature PR reviewer sees unrelated todo file in the diff
- If feature branch is abandoned, the todo is lost

The remote agent approach means the todo reaches main within minutes, regardless of what happens to the feature branch.

### Fallback modes

Three tiers, tried in order. The user can force a specific mode with `--remote`, `--pr`, or `--local`.

1. **Remote session** (default) -- `claude --remote` dispatches a cloud agent. Zero local impact.
2. **Local PR via GitHub API** (`--pr`) -- uses `gh api` to create the branch and file on the remote, then `gh pr create`. Still zero local git impact — no checkout, no staging, no branch switch. Requires `gh` CLI and internet.
3. **Local staging** (`--local`) -- writes the file and `git add`s it into the current branch. The todo merges with the feature PR. Use when offline or for testing.

---

## `/process-todo` Consumer

### Where it runs

Three modes, in order of preference:

1. **Remote sessions (recommended):** `/process-todo` dispatches each todo to its own `claude --remote` session. Each runs in an isolated cloud VM with a fresh clone.
2. **Scheduled remote tasks:** Use Claude's web UI or `/schedule` to set up recurring processing. Replaces GitHub Actions -- no YAML, no secrets management.
3. **Local (fallback):** `/process-todo --local` processes in the current session. Useful for testing.

### Processing Steps

Each dispatched remote agent:

1. **Claim** -- Create branch `todo/<slug>`, set `status: claimed` in the file, commit and push. If push fails (branch exists), another agent claimed it -- stop.

2. **Execute** -- Read the todo's Context, Task, and `related_files`. Do the work. Run tests and linting if available.

3. **Validate** -- Tests pass (if they exist). No new lint errors. Acceptance criteria met.

4. **Open PR** -- Title: `chore(todo): <title>`. The PR includes deletion of the todo file. Label: `todo-loop`.

### Parallel processing

Each `claude --remote` creates its own isolated session. Process multiple todos simultaneously:

```
/process-todo --all
```

This dispatches one remote session per unclaimed todo. Each gets its own VM, its own clone, its own branch. No filesystem races, no worktree management, no cleanup.

### Failure Handling

If the consumer can't complete the task:

- Set `status: blocked` in the todo
- Add a `## Consumer Notes` section with what was attempted and what went wrong
- Push the branch but do NOT open a PR
- **Notify via Slack** (see Slack Integration below)

### Remote session note

Remote sessions don't have access to locally-installed plugins. The `/process-todo` command handles this by embedding all processing instructions directly in the `claude --remote` prompt. The remote agent doesn't need to know about the plugin -- it just follows inline instructions.

---

## Auto-Merge for Todo Additions

Todo-add PRs only create markdown files in `dev_docs/todos/`. They're safe to auto-merge.

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

The safety check verifies only `dev_docs/todos/**` files are in the diff, even though the label triggers it.

**Branch protection note:** `GITHUB_TOKEN` can't approve its own PR if reviews are required. Options: (a) don't require reviews for PRs that only touch `dev_docs/todos/`, (b) use a PAT or GitHub App token, or (c) CODEOWNERS with no required reviewer for that path.

---

## Slack Integration

Notifications for key lifecycle events, sent to a configurable Slack channel (or DM) via a webhook or bot token.

**When to notify:**

- **Todo blocked:** Consumer couldn't complete the task. Message includes the todo title, link to the branch, and the reason from `## Consumer Notes`.
- **Todo expired:** Pruning job is about to delete an unclaimed todo. Last chance to renew or act on it.
- **PR opened:** Optional. A lightweight "heads up, review this when you have a moment" for auto-generated PRs.

**Configuration:** Each repo can specify a Slack webhook URL or channel ID in a config file (e.g., `dev_docs/todos/.config.yml`):

```yaml
slack:
  webhook_url: "${SLACK_TODO_WEBHOOK}"  # env var, resolved at runtime
  # or
  channel_id: "C0123ABCDEF"
  notify_on:
    - blocked
    - expired
    # - pr_opened  # opt-in
```

For personal use, a single Slack webhook posting to a `#todo-loop` channel (or DM) is enough. The webhook URL lives in environment variables or a secrets manager, never committed to the repo.

**MVP:** Skip Slack entirely. Add it in v1 when there are enough todos flowing through to warrant push notifications over just checking GitHub.

---

## Folder Structure

Todo files can be organized into subfolders under `dev_docs/todos/` for repos with enough volume to warrant it:

```
dev_docs/todos/
  remove-stale-foobar-alias.md
  cleanup/
    dead-import-in-utils.md
    unused-config-key.md
  tests/
    add-missing-zsh-profile-test.md
```

**Rules:**

- Scanning is always recursive (`dev_docs/todos/**/*.md`), so subfolder organization is optional and purely for human readability.
- The slug remains globally unique across all subfolders. The `/add-todo` skill checks for collisions across the entire tree.
- Subfolders are freeform -- no enforced taxonomy. Common patterns: by tag (`cleanup/`, `tests/`), by area (`zsh/`, `git/`), or flat (no subfolders at all).
- The `/add-todo` skill defaults to writing files at the root (`dev_docs/todos/<slug>.md`). A `--dir` flag or tag-based heuristic can place files in subfolders if they exist.

---

## Race Conditions

With `claude --remote`, each agent gets its own isolated cloud VM with a fresh clone. Filesystem races are impossible. The only contention point is `git push`:

1. Branch names are deterministic: `todo/<slug>`
2. `git push` is atomic -- the second push fails
3. On push failure, the agent skips this todo and moves to the next unclaimed one

**Worst case:** wasted compute (an agent did the work but can't push). No data corruption, no duplicate PRs. The cloud VM is discarded after the session ends.

This is simpler than the worktree-based approach, which had to manage filesystem locks, shared git state, and cleanup.

---

## Failure Modes

### Stale todos -- code changed since the todo was written

The consumer reads `related_files` fresh, not from a snapshot. If the task is already done (e.g., grep for a reference returns nothing), the consumer marks the todo complete and deletes it without a PR. The Context section should describe _what_ and _why_, not just line numbers, so the consumer can find relevant code even if it moved.

**Mitigation:** `expires` field (30-day default) provides a hard deadline. Stale todos get pruned.

### The "self-cleaning" property and reverts

If a fix PR gets reverted, the todo file is gone. Recovery requires re-creating it manually. For personal projects this is acceptable -- reverts are rare and I have git history. If this becomes a real problem, switching to GitHub Issues as the backing store is the right fix.

### Todo graveyard -- accumulation without execution

The `expires` field with a 30-day default. A pruning job (or manual review) deletes expired todos. If I'm not processing todos, the system self-cleans rather than accumulating guilt.

### Context loss between writing and execution

`related_files` ensures the consumer reads actual code. `source_branch` lets it read the branch diff for additional context. If context is genuinely insufficient, the consumer sets `status: blocked` with notes.

---

## Lifecycle

```
unclaimed --> claimed --> PR opened --> merged (todo file deleted)
    |             |
    |             +--> blocked (needs manual intervention)
    |
    +--> expired (auto-pruned after 30 days)
```

### Expiration

Options for handling expiration, in order of simplicity:

1. **Manual:** Periodically run `fd .md dev_docs/todos/ | xargs grep -l "expires:"` and delete expired ones.
2. **GitHub Action:** Weekly cron that opens PRs to delete expired todos.
3. **Hook:** A pre-push or CI check that warns about expired todos.

Start with option 1. Move to 2 if accumulation becomes a problem.

---

## Why Not GitHub Issues?

|                | GitHub Issue                              | Todo File                                 |
| -------------- | ----------------------------------------- | ----------------------------------------- |
| **Context**    | Paraphrased description, maybe a link     | Lives in the repo, references exact files |
| **Execution**  | Human reads issue, re-discovers context   | Agent reads files, does work, opens PR    |
| **Expiration** | Never -- issues rot in backlogs           | 30-day default, auto-pruned               |
| **Overhead**   | Create, label, track                      | `/add-todo` -- one command                |
| **Portability**| Tied to one repo's issue tracker          | Same format works in any repo             |

GitHub Issues are better for: multi-step projects, things that need discussion, work that spans multiple repos. Todo files are for small, concrete, code-level follow-ups.

---

## Distribution

The todo-loop system is packaged as a **Claude Code plugin** (`bestdan/todo-plugin`):

```bash
claude plugin marketplace add bestdan/todo-plugin
claude plugin install todo@todo-plugin
```

This installs on any machine and provides `/add-todo`, `/process-todo`, and `/list-todos` commands plus a skill that auto-detects todo-related intent.

### Cross-Repo Design

- **Plugin** provides the commands and skill -- installed once, available in any repo
- **Todo files** live in each project's own `dev_docs/todos/` directory -- repo-specific context
- **Auto-merge workflow** (`auto-merge-todos.yml`) is per-repo, for repos that want automatic todo landing
- **Format is identical** across repos. The plugin doesn't assume anything about the host repo beyond "it has a `dev_docs/todos/` directory"
- **Remote sessions** are dispatched per-repo -- the `claude --remote` prompt includes the repo context

---

## Rollout

### MVP (this week)

- Todo file format as specified
- Plugin repo (`bestdan/todo-plugin`) with `/add-todo`, `/process-todo`, `/list-todos`
- `/add-todo` dispatches remote agent to create todo file on a branch from main
- `/process-todo --local` for testing locally
- Try it in the dotfiles repo first

### v1 (when MVP proves useful)

- `/process-todo` dispatches remote agents (one per todo, parallel)
- `/process-todo --all` for batch processing
- Auto-merge workflow for todo-add PRs
- `todo-loop` and `todo-add` GitHub labels
- Slack webhook notifications for blocked todos

### v2 (if warranted)

- Scheduled remote tasks via Claude web UI (replaces GitHub Actions cron)
- Expiration pruning via scheduled task or GitHub Action
- Slack notifications for expired todos and (optionally) PR opens
- Tags-based filtering (`/process-todo --tag cleanup`)
- Todo templates for common patterns (alias cleanup, dead code removal, test gap)

---

## Counter-Arguments

### You're building a task queue in git

Valid. `dev_docs/todos/` with status fields is a job queue on top of version control. The `claude --remote` approach mitigates the worst parts: no local git state manipulation, no worktree management, no merge surface from status changes on your working branch. Each agent operates on its own fresh clone. If this scales to team use, GitHub Issues with labels is the better backing store.

### The 30-day expiration means nothing important should go here

Correct. This is by design. Important work goes in a project tracker or GitHub Issue. This is for the small stuff that's worth doing but not worth tracking formally. If it expires, it wasn't important enough to do in 30 days, and that's fine.

### The review cost might exceed the value

For personal projects, I can auto-merge low-risk todo PRs (flag cleanup, dead code removal) after CI passes. No review bottleneck. For work repos, this is a real concern addressed by starting with low-risk todo types only.

### Just use a TODO comment in the code

TODO comments are invisible after the PR merges. They don't expire, don't get executed, and have no structured context. They're fine for "someone should think about this someday" but not for "here's exactly what to do and why."

### `claude --remote` adds latency and cost

Each remote session spins up a cloud VM, clones the repo, and runs Claude. For `/add-todo`, this is overkill for writing one markdown file -- the GitHub API approach (create file via `gh api`) would be faster and cheaper. But the remote session approach is simpler to implement, more flexible (the agent can handle edge cases), and consistent with `/process-todo`. If the latency or cost becomes a problem, `/add-todo` can switch to direct API calls as an optimization.

---

## Open Questions

1. **Scope boundaries** -- What's too big for a todo? Rule of thumb: if the Task section exceeds ~10 steps, it should be a GitHub Issue or project ticket instead.

2. **Which repos opt in first?** -- Start with dotfiles (low risk, familiar). Then evaluate for work repos if the pattern proves useful.

3. **Remote session cost** -- Each `claude --remote` consumes API tokens and compute. `/add-todo` sessions are cheap (write one file). `/process-todo` sessions vary by task complexity. Monitor and set a monthly budget.

4. **Plugin availability in remote sessions** -- Remote VMs don't have locally-installed plugins. The current design embeds instructions in the prompt. If the prompt gets too large, consider having repos include a `dev_docs/todos/PROCESSING.md` that the remote agent reads instead.
