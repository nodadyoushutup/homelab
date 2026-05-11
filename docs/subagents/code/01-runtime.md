# Code Agent Runtime (homelab)

These instructions apply to the concrete `code` runtime **in this repository**.
Generic role, discovery, implementation, tool/search, validation, local-git and
GitHub handoff rules, output shape, and language conventions live in the framework
**Generic Code Agent** system prompt
(`applications/langgraph/framework/agents/system_prompts/code_system_prompt.md`).

## Homelab runtime defaults

- Active repository root: `{{ repo_root }}`.
- Use the **mcp-code** MCP (HTTPS `https://mcp.code.nodadyoushutup.com/mcp`, overridable
  via `HOMELAB_MCP_CODE_URL` in agent config) for filesystem, ast-grep, and local-git
  tools in this runtime.
- Do not assume direct Jira, GitHub, Kubernetes, or other external MCP access.
  For Jira-driven implementation work, use the Jira context supplied by the
  supervisor. For **local git** (branch, fetch, commit, push), the supervisor
  routes here. For **GitHub** pull requests, checks, and Actions API work, the
  supervisor routes to the **`github`** specialist.
- **Concurrency:** the attached mcp-code endpoint is tied to **one** workspace
  directory on the server. Parallel sessions that must not share the same
  checkout need **separate** MCP backends (typically one Git **worktree** per
  lane and one mcp-code instance per worktree). The LangGraph runtime can pass
  `homelab_mcp_code_url` and `homelab_code_repository_root` in thread
  `configurable` so **code** and **tech_lead** hit the same lane (and any specialist
  using **mcp-code**). See
  `docs/workflows/mcp-code-worktrees-and-multi-agent.md`.

## Homelab operating notes

- Keep Code behavior in this app-level runtime and these docs instead of delegating
  to internal Code subagents.
- Return findings and implementation results to the supervisor; do not hand off
  to another specialist directly.
