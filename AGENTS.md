# AGENTS

This repo is docs-driven. Use this file as the directory to the source-of-truth
docs agents need before starting work.

## Required Start Rule

Before doing substantive work:

1. determine which agent owns the task from `docs/agents/README.md`
2. determine which subagents are needed from the documented agent set
3. lock the agent set before proceeding
4. perform the task using those documented agents and subagents

Do not start work as an unspecified generic agent.

## Where To Look

- `docs/agents/README.md`: current agent set, parent/subagent roles, and
  selection guidance
- `docs/agents/homelab-agent.md` and `docs/agents/subagents/*.md`: native
  input/output schemas and communication expectations for each agent
- `docs/workflows/agents.md`: required workflow for choosing and locking the
  agent set before execution
- `docs/rules/README.md`: index of repo, Kubernetes, and Terraform rules
- `docs/workflows/README.md`: index of execution workflows
- `docs/resources/README.md`: curated technology reference shelf

## Repo Notes

- Treat `docs/` as the source of truth for repeatable repo rules and workflows.
- If a stable pattern changes, update the corresponding docs as part of the
  task.
- Do not reference removed legacy wiki paths until replacement docs exist in
  `docs/`.
- For this workspace, filesystem interaction should go through the
  `mcp_filesystem_homelab` MCP server once it is available in project config.
  Use direct shell or local file-edit access only to bootstrap, repair, or
  validate that MCP path.
