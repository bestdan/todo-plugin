---
description: Capture follow-up work as a structured todo file, then dispatch an agent to commit and open a PR
allowed-tools: Bash(git *), Bash(gh *), Bash(claude *), Bash(date *), Glob, Grep, Read, Agent
argument-hint: [description of the follow-up work]
---

# Add Todo

Capture follow-up work with full context, then dispatch an agent to commit the todo file on a branch from main and open a PR — without touching local state.

## Steps

### 1. Gather context

Collect automatically (run these in parallel):
- Current branch: `git rev-parse --abbrev-ref HEAD`
- Repo name: `gh repo view --json nameWithOwner --jq .nameWithOwner`
- Open PR for this branch (if any): `gh pr view --json number --jq .number 2>/dev/null`
- Current diff summary: `git diff --stat HEAD`
- Today's date: `date +%Y-%m-%d`
- Expiry date (30 days): `date -v+30d +%Y-%m-%d` (macOS) or `date -d '+30 days' +%Y-%m-%d` (Linux)

If `$ARGUMENTS` is provided, use it as the title seed. Otherwise, ask the user what follow-up work they want to capture.

### 2. Generate the slug

From the title, create a kebab-case slug:
- Lowercase, strip filler words (the, a, an, for, in, on, at, to, of)
- Max 50 chars
- Example: "Remove stale zsh alias for foobar" -> `remove-stale-zsh-alias-foobar`

### 3. Check for slug collisions

Check if a todo with this slug already exists:

```bash
find "$(git rev-parse --show-toplevel)/dev_docs/todos" -name '<slug>.md' -type f 2>/dev/null
```

If a collision is found, append `-2`, `-3`, etc. until unique.

### 4. Draft the todo

Auto-populate these fields:
- `created`: today's date (ISO format)
- `source_branch`: current branch
- `source_pr`: PR number if one exists for this branch
- `status`: `unclaimed`
- `expires`: 30 days from today
- `priority`: `low` (default, ask user if they want different)

From conversation context and diff, draft:
- `title`: from user description or `$ARGUMENTS`
- `related_files`: files from current diff or conversation that are relevant
- `tags`: infer from context (e.g., `cleanup`, `tests`, `docs`)
- **Context** section: why this work was noticed
- **Task** section: concrete steps to complete it
- **Acceptance Criteria**: definition of done

### 5. Present for review

Show the user the full draft and ask for confirmation. They can adjust priority, add/remove files, or edit the task steps.

Also ask: **"File for later, or fix now?"**
- **File for later** (default): creates the todo file on main for `/process-todo` to pick up
- **Fix now**: creates the todo file AND immediately dispatches a processing agent to do the work

### 6. Detect dispatch mode

Run these checks to determine which mode is available:

```bash
# Check gh auth first — needed by all non-local modes
gh auth status 2>&1
```

If `gh auth status` fails (token invalid, TLS errors, network issues), skip straight to Mode 3 (local).

If gh works, check for remote support:

```bash
claude --version 2>/dev/null
```

If `claude` is available, attempt remote mode. If the remote dispatch itself fails, fall through to Mode 2, then Mode 3. **The cascade must be automatic** — if one mode fails, try the next without stopping.

The user can force a mode with `--remote`, `--subagent`, or `--local`.

### 7. Dispatch

Use the detected mode to create the todo file on a branch from main and open a PR.

**All dispatch modes use an agent** (remote or sub-agent) to avoid polluting the main conversation with git plumbing. The main agent's job ends after gathering context, drafting, and getting confirmation.

#### Mode 1: Remote session (`claude --remote`)

Dispatch a remote Claude session. The remote agent runs in an isolated cloud VM with a fresh clone — zero local impact.

**Important:** Do NOT pass `--print` to `claude --remote` — it is not supported and will error.

```bash
claude --remote "You are creating a todo file for the todo plugin system.

Do the following steps exactly:

1. Create the branch: git checkout -b todo/add/<slug>
2. Create the directory if needed: mkdir -p dev_docs/todos
3. Write the following content to dev_docs/todos/<slug>.md:

<paste the full todo file content here, fenced in triple backticks>

4. Stage and commit:
   git add dev_docs/todos/<slug>.md
   git commit -m 'add todo: <slug>'
   git push -u origin todo/add/<slug>

5. Ensure the label exists, then create a PR:
   gh label create todo-add --description 'Auto-generated todo file' --color '1D76DB' 2>/dev/null
   gh pr create --base main --title 'todo: <title>' --label todo-add --body 'Adds a follow-up todo for processing by the todo plugin.

Source branch: <source_branch>
Priority: <priority>
Expires: <expires>'

6. Report the PR URL.

Do NOT modify any other files. This PR should contain exactly one new file."
```

#### Mode 2: Sub-agent with GitHub API (fallback)

When `claude --remote` is unavailable, use the Agent tool to spawn a sub-agent. The sub-agent creates the branch and file entirely through the GitHub API — zero local git impact, and the git plumbing stays out of the main context window.

Delegate to the Agent tool with this prompt:

> Create a todo file on GitHub for the todo plugin system.
>
> Repo: `<owner>/<repo>`
> Slug: `<slug>`
> Title: `<title>`
> Source branch: `<source_branch>`
> Priority: `<priority>`
> Expires: `<expires>`
>
> Todo file content (write this exactly):
> ```
> <paste full todo file content>
> ```
>
> Steps:
> 1. Get main's latest SHA: `gh api repos/<owner>/<repo>/git/refs/heads/main --jq '.object.sha'`
> 2. Create branch: `gh api repos/<owner>/<repo>/git/refs --method POST --field ref="refs/heads/todo/add/<slug>" --field sha="$main_sha"`
> 3. Create the file on the branch using the Contents API. Base64-encode the todo content inline:
>    ```
>    echo '<todo file content>' | base64 | tr -d '\n' > /dev/null  # just to show the encoding
>    gh api repos/<owner>/<repo>/contents/dev_docs/todos/<slug>.md \
>      --method PUT \
>      --field message="add todo: <slug>" \
>      --field content="$(printf '%s' '<todo file content>' | base64 | tr -d '\n')" \
>      --field branch="todo/add/<slug>"
>    ```
> 4. Ensure label exists and open PR:
>    ```
>    gh label create todo-add --description 'Auto-generated todo file' --color '1D76DB' 2>/dev/null
>    gh pr create --base main --head "todo/add/<slug>" --title "todo: <title>" --label todo-add --body "Adds a follow-up todo.
>
>    Source branch: <source_branch>
>    Priority: <priority>
>    Expires: <expires>"
>    ```
> 5. Report the PR URL.
>
> **Important:** Do not use `$TMPDIR` or temp files — the Contents API accepts base64 directly. This avoids sandbox permission issues with temp file writes in sub-agents.

#### Mode 3: Local staging (`--local`)

Last resort. Write the file directly into the current branch:

1. `mkdir -p dev_docs/todos`
2. Write the file to `dev_docs/todos/<slug>.md`
3. `git add dev_docs/todos/<slug>.md`
4. Tell the user the file is staged and will merge with their feature PR

### 8. If user chose "fix now"

After the todo file PR is dispatched, also dispatch a processing agent for this todo. Use the same mode detection logic:

- **Remote**: `claude --remote` with the full processing prompt from `/process-todo`
- **Sub-agent**: Agent tool with processing instructions

**Sequencing:** Do NOT dispatch both in parallel. The processing agent needs the todo file to exist. Dispatch the todo-add agent first. Once it completes (or if using remote, once the `claude --remote` command returns), dispatch the processing agent with `--head todo/add/<slug>` as its base branch instead of main. The processing agent should branch `todo/<slug>` from `todo/add/<slug>` so it has the todo file available even before the add-PR merges.

### 9. Confirm dispatch

Tell the user:
- What was dispatched (file only, or file + processing)
- The dispatch mode used (remote session or sub-agent)
- They can monitor with `/tasks`
- If "file for later": the todo will be on main once the PR merges, available for `/process-todo`

### Mode selection summary

**The cascade is automatic.** If a mode fails at dispatch time, fall through to the next without stopping.

```
if gh auth status fails:
    → Mode 3: Local staging (gh is broken, skip Modes 1 and 2)

if --local flag:
    → Mode 3: Local staging

if --remote flag or (claude CLI is available and no override flag):
    → Try Mode 1: Remote session
    → On failure, fall through to Mode 2

if --subagent flag or (Mode 1 failed or unavailable):
    → Try Mode 2: Sub-agent with GitHub API
    → On failure, fall through to Mode 3

→ Mode 3: Local staging (final fallback, always available)
```
