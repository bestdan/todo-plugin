# Handler: jira

Creates a Jira work item via the Atlassian MCP server (`mcp__claude_ai_Atlassian__*`). Foreground call, no git plumbing, no CLI install. The new ticket is placed under a selected epic.

Config block in `dev_docs/todos/.todo-config.yml`:

```yaml
handler: jira
jira:
  site: mycompany.atlassian.net   # used as cloudId and to build the browse URL
  project: PLAT                   # required — project key
  issue_type: Task                # default Task
  default_epic: PLAT-100          # optional; skips the epic prompt (explicit key, not a name)
  labels: []                      # optional — passed via additional_fields.labels
```

`site` is passed directly as `cloudId` to the MCP tools (they accept either a UUID or a site URL/hostname).

## Steps

1. **Preflight.** Confirm the Atlassian MCP is reachable and the configured site is accessible:

   Call `mcp__claude_ai_Atlassian__getAccessibleAtlassianResources` (no args).
   - If the tool errors or returns no resources, **stop** with: "Jira handler needs the Atlassian MCP. Install/connect it in Claude Code settings, then re-run." Do not fall back to another handler.
   - If the response does not include a resource whose `url` matches `https://<jira.site>`, **stop** with: "Configured Jira site `<site>` is not in your accessible Atlassian resources." (List the URLs that were returned.)

2. **Select the epic.** If `jira.default_epic` is set, use it and skip the prompt. Otherwise list the project's open epics for the user to pick (or choose "none" for a top-level ticket):

   Call `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with:
   - `cloudId`: `<jira.site>`
   - `jql`: `project = "<project>" AND issuetype = Epic AND statusCategory != Done ORDER BY updated DESC`
   - `fields`: `["summary", "status"]`
   - `maxResults`: 50

   The response wraps issues as `issues.nodes[]`; each node has `key`, `fields.summary`, `fields.status.name`, and a ready-made `webUrl`. Present each as a numbered list (`key — summary [status]`); capture the chosen `<EPIC-KEY>`.

3. **Compose the description.** Use the drafted todo's `body` plus a source footer (omit empty lines):

   ```
   <body>

   ---
   Source branch: <source_branch>
   Source PR: #<source_pr>
   ```

4. **Create the work item.** Call `mcp__claude_ai_Atlassian__createJiraIssue` with:
   - `cloudId`: `<jira.site>`
   - `projectKey`: `<project>`
   - `issueTypeName`: `<issue_type>` (default `Task`)
   - `summary`: the drafted `title`
   - `description`: the composed description from step 3
   - `contentFormat`: `"markdown"`
   - `parent`: the chosen `<EPIC-KEY>` (omit entirely if the user picked "none")
   - `additional_fields`: `{ "labels": <jira.labels list> }` (omit if no labels configured)

5. **Return the URL.** The response wraps the new issue as `issues.nodes[0]`. Return `issues.nodes[0].webUrl` directly as this handler's artifact URL for `/add-todo` step 8. (Fallback: build `https://<jira.site>/browse/<issues.nodes[0].key>` if `webUrl` is missing.)

This handler does **not** create any `dev_docs/todos/*.md` file, branch, or PR.
