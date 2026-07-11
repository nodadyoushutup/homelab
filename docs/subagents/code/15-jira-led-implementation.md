# Jira-led implementation (Code specialist)

## Jira tools on this specialist

- The **Code** runtime loads **mcp-rag** and the **Atlassian** MCP (Jira tools).
  Local git and file edits are out of band (IDE/shell in the worktree at
  `homelab_code_repository_root`).
- Use Jira tools for **fresh** issue data. Do **not** rely on the supervisor’s
  pasted summary as the only source of truth when you know the issue key.

## Mandatory first step when the issue key is known

If the delegated task includes a **Jira issue key** (e.g. `HOME-123`) or the user
named one:

1. **Before** any local-git branch work, filesystem edits, or repo searches,
   call the appropriate **Jira MCP read** tool to **reload the issue** (fields,
   description, acceptance criteria, status). Use the live response as the
   implementation contract.
2. If the key is missing but the work is clearly ticket-driven, ask for it
   before branching.

The supervisor still runs **`rag_search`** before delegating here; your **first**
tool calls in this thread should still be **Jira read** when a key is present,
then repository work.

## Workflow after Jira is fresh

Keep all **read-before-write** rules (inspect the repo before `write_file` /
`edit_file` / `execute`).

1. **Observe git state** (status / branch).
2. **Sync `main`** (or default integration branch): fetch, checkout, pull per
   [14-local-git.md](./14-local-git.md).
3. **Create and checkout** the feature branch per [14-local-git.md](./14-local-git.md).
4. **Implement**, **commit** with the issue key in the message, **push** to
   `origin`.
5. **Return** branch name, SHA, and recommend the supervisor delegate to
   **`github`** for the PR unless the user asked for local-only work.

## Jira mutations from Code

- Prefer **read** operations here (get/search) so ticket state stays centralized
  in the **`jira`** specialist for transitions, comments, and workflow moves.
- If the task **explicitly** asks you to update Jira from implementation, use the
  Jira MCP tools carefully and report what changed.

## When this is relaxed

- **No Jira key:** normal Code behavior; no forced Jira fetch.
- **User explicitly** asked for **local-only** or **no PR:** honor that.

## Related

- [14-local-git.md](./14-local-git.md)
- `applications/langgraph/agent/system_prompt.md` (Jira-led delivery)
- `scripts/agents/homelab_jira_issue_worktree.sh` (worktree + configurable fragment)
