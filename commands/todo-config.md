---
description: Configure where /add-todo delivers todos (repo PR, GitHub issue, or Jira)
allowed-tools: Bash(git *), Bash(gh *), Bash(acli *), Bash(command *), Bash(brew *), Bash(cat *), Bash(mkdir *), Read, Write
argument-hint: [repo-pr | gh-issue | jira]
---

# Todo Config

Set up the destination handler for `/add-todo` in this repo. Writes `dev_docs/todos/.todo-config.yml`, which `/add-todo` reads to decide where a captured todo lands. The file is **repo-committed and shared by the team** — everyone in the repo files to the same destination.

See the handler definitions in `commands/add-todo.md` (the `## Handlers` section) for what each destination does.

## Steps

### 1. Show current config

```bash
cat "$(git rev-parse --show-toplevel)/dev_docs/todos/.todo-config.yml" 2>/dev/null
```

If it exists, show the user what's currently configured so they see what they're changing. If not, say there's no config yet (so `/add-todo` currently defaults to `repo-pr`).

### 2. Choose the handler

If `$ARGUMENTS` names a handler (`repo-pr`, `gh-issue`, or `jira`), use it. Otherwise ask which destination they want:

- **`repo-pr`** — commit the todo as a markdown file via PR (the default; works with `/process-todo`)
- **`gh-issue`** — create a GitHub Issue
- **`jira`** — create a Jira work item under an epic

### 3. Collect settings + verify prerequisites

Per handler. **Verify before writing — don't write a config that can't deliver.**

#### repo-pr

No prerequisites. Mention the optional auto-merge workflow (see `README.md`) for landing `todo-add` PRs automatically. Proceed to write.

#### gh-issue

1. Verify auth: `gh auth status 2>&1`. If it fails:
   - TLS/x509/certificate error → likely the sandbox blocking keychain access; tell the user to re-run outside sandbox mode.
   - Otherwise → ask the user to authenticate. `gh auth login` is interactive: have them run it via the session prefix, e.g. `! gh auth login`, then continue.
   - Do not write the config until `gh auth status` succeeds.
2. Prompt for (all optional except none are required):
   - `repo` — default the current repo (`gh repo view --json nameWithOwner --jq .nameWithOwner`)
   - `labels` — list, e.g. `[follow-up]`
   - `assignees` — list of GitHub usernames

#### jira

1. Check the CLI: `command -v acli || echo MISSING`. If missing, offer the install commands and stop until installed:

   ```bash
   brew tap atlassian/homebrew-acli && brew install acli
   ```

2. Prompt for `site` (e.g. `mycompany.atlassian.net`), then guide auth. `acli jira auth login` is interactive — have the user run it via the session prefix:

   ```bash
   ! acli jira auth login --site <site> --email <email> --token   # paste API token when prompted
   # or, for browser OAuth:
   ! acli jira auth login --web
   ```

   Verify auth succeeds (e.g. `acli jira auth status` if available) before writing.
3. Prompt for `project` (key, required), `issue_type` (default `Task`), optional `default_epic`, optional `labels`.

> **Interactive auth caveat:** never try to run `gh auth login` or `acli jira auth login` headless from inside this command — they prompt for input. Always have the user run them with the `!` session prefix, then continue once they report success.

### 4. Write the config

Ensure the directory exists and write the file:

```bash
mkdir -p "$(git rev-parse --show-toplevel)/dev_docs/todos"
```

Write `dev_docs/todos/.todo-config.yml` with the chosen handler and its block. Examples:

```yaml
# repo-pr
handler: repo-pr
```

```yaml
# gh-issue
handler: gh-issue
gh-issue:
  repo: owner/name
  labels: [follow-up]
  assignees: []
```

```yaml
# jira
handler: jira
jira:
  site: mycompany.atlassian.net
  project: PLAT
  issue_type: Task
  default_epic: PLAT-100
  labels: []
```

Omit optional keys the user didn't set.

### 5. Confirm

Tell the user:
- Which handler is now configured and where the file lives.
- That the file is repo-committed and shared — they should **commit it** so teammates pick up the same destination.
- They can now run `/add-todo`, or re-run `/todo-config` to switch handlers.
