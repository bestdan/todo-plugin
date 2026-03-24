---
description: Capture follow-up work as a structured todo file, then send it to a remote agent to commit and open a PR
allowed-tools: Bash(git *), Bash(gh *), Bash(claude *), Bash(date *), Glob, Grep, Read
argument-hint: [description of the follow-up work]
---

# Add Todo

Capture follow-up work with full context, then dispatch a remote Claude session to commit the todo file on a branch from main and open a PR — without touching local state.

## Steps

### 1. Gather context

Collect automatically:
- Current branch: `git branch --show-current`
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

### 3. Draft the todo

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

### 4. Present for review

Show the user the full draft and ask for confirmation before proceeding. Make it clear they can adjust priority, add/remove files, or edit the task steps.

### 5. Dispatch to remote agent

After the user confirms, send the todo to a remote Claude session. The remote agent will create the branch, write the file, and open a PR — all without touching local state.

Construct the full todo file content as a string (the exact markdown with frontmatter that was shown to the user).

Then run:

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

5. Create a PR:
   gh pr create --base main --title 'todo: <title>' --label todo-add --body 'Adds a follow-up todo for processing by the todo plugin.

Source branch: <source_branch>
Priority: <priority>
Expires: <expires>'

6. Report the PR URL.

Do NOT modify any other files. This PR should contain exactly one new file."
```

### 6. Confirm dispatch

Tell the user:
- The remote session has been started
- They can monitor it with `/tasks`
- Once the auto-merge workflow approves it, the todo will land on main
- A processing agent will pick it up automatically

## Fallback modes

Try each mode in order. The user can force a specific mode with `--remote`, `--pr`, or `--local`.

### Mode 2: Local PR via GitHub API (`--pr`)

If `--remote` is unavailable but the user has `gh` CLI and internet access, create the branch and file entirely through the GitHub API — zero local git impact:

```bash
# 1. Get main's latest SHA
main_sha=$(gh api repos/{owner}/{repo}/git/refs/heads/main --jq '.object.sha')

# 2. Create branch on remote
gh api repos/{owner}/{repo}/git/refs --method POST \
  --field ref="refs/heads/todo/add/<slug>" \
  --field sha="$main_sha"

# 3. Create the todo file on that branch
# Write the todo content to a temp file first, then base64-encode it
echo '<todo file content>' > "$TMPDIR/todo-<slug>.md"
gh api repos/{owner}/{repo}/contents/dev_docs/todos/<slug>.md \
  --method PUT \
  --field message="add todo: <slug>" \
  --field content="$(base64 -i "$TMPDIR/todo-<slug>.md")" \
  --field branch="todo/add/<slug>"

# 4. Open PR
gh pr create --base main --head "todo/add/<slug>" \
  --title "todo: <title>" --label todo-add \
  --body "Adds a follow-up todo for processing by the todo plugin.

Source branch: <source_branch>
Priority: <priority>
Expires: <expires>"
```

Tell the user the PR has been created and provide the URL. If an auto-merge workflow is configured, the todo will land on main automatically.

### Mode 3: Local staging (`--local`)

If there's no internet or `gh` is unavailable, fall back to staging the file into the current branch:

1. `mkdir -p dev_docs/todos`
2. Write the file to `dev_docs/todos/<slug>.md`
3. `git add dev_docs/todos/<slug>.md`
4. Tell the user the file is staged and will merge with their feature PR

### Mode selection logic

```
if --remote flag or (claude --remote is available and no override flag):
    → Mode 1: Remote session
elif --pr flag or (gh CLI available and authenticated):
    → Mode 2: Local PR via GitHub API
else:
    → Mode 3: Local staging
```
