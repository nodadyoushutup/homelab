# AGENTS

This repo is docs-driven. Use this file as the directory to the source-of-truth
docs to check before doing substantive work.

## Where To Look

- `docs/rules/README.md`: index of repo, Kubernetes, and Terraform rules
- `docs/workflows/README.md`: index of execution workflows
- `docs/resources/README.md`: curated technology reference shelf
- `docs/rules/langgraph.md`: LangGraph app boundaries, MCP rules, and runtime
  composition rules
- `docs/workflows/langgraph.md`: LangGraph implementation workflow
- `docs/agents/README.md`: LangGraph runtime contract index
- `docs/agents/homelab-agent.md` and `docs/agents/subagents/*.md`: LangGraph
  runtime instruction and I/O contracts for deployed agents

## Repo Notes

- Treat `docs/` as the source of truth for repeatable repo rules and workflows.
- If a stable pattern changes, update the corresponding docs as part of the
  task.
- Do not use a repo-wide workflow that requires choosing or locking a local
  agent before starting work. Agent-specific behavior lives in the LangGraph
  runtime contracts under `docs/agents/` and `applications/langgraph/`.
- Do not reference removed legacy wiki paths until replacement docs exist in
  `docs/`.
- For this workspace, filesystem interaction should go through the
  `mcp_filesystem` MCP server once it is available in project config.
  Use direct shell or local file-edit access only to bootstrap, repair, or
  validate that MCP path.
