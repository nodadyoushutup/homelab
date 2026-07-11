# Code Agent Runtime (homelab)

These instructions apply to the concrete `code` runtime **in this repository**.
Generic role, discovery, implementation, tool/search, validation, local-git and
GitHub handoff rules, output shape, and language conventions live in the framework
**Generic Code Agent** system prompt
(`applications/langgraph/framework/agents/system_prompts/code_system_prompt.md`).

## Homelab runtime defaults

- Active repository root: `{{ repo_root }}`.
- HTTP MCP tools from **`code_mcp_servers.json`**: **mcp-rag** (`rag_search`) and
  **Atlassian** (`HOMELAB_MCP_ATLASSIAN_URL`) for Jira reads. There is no repo
  filesystem or local-git MCP—use **rag_search** for docs/architecture and tell the
  supervisor when the user or IDE must apply file/git changes in the worktree.
- For ticket-driven implementation, **fetch the issue fresh** via Jira MCP when the
  issue key is known, **before** branch/repo work—see
  [15-jira-led-implementation.md](./15-jira-led-implementation.md).
- Do not assume GitHub or Kubernetes MCP access here. For **GitHub** pull requests,
  checks, and Actions API work, the supervisor routes to the **`github`** specialist.
- **Concurrency:** pass `homelab_code_repository_root` in thread `configurable` so
  **code** and **tech_lead** scope paths to the same Git **worktree** per lane.
  Create worktrees with `scripts/agents/homelab_jira_issue_worktree.sh`.

## Homelab operating notes

- Keep Code behavior in this app-level runtime and these docs instead of delegating
  to internal Code subagents.
- Return findings and implementation results to the supervisor; do not hand off
  to another specialist directly.
