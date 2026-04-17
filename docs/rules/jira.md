# Jira Rules

This document defines the steady-state rules for how this repo uses Jira for
issue lookup, workflow analysis, and linked engineering context. Use
[`docs/workflows/jira.md`](./../workflows/jira.md) for the operator flow.

## Scope

This document applies to:

- Jira access through the `mcp-atlassian` server
- Jira-backed analysis performed by repo agents and subagents
- Jira references that inform engineering planning, coordination, and status
  analysis in this repo

## Source of Truth

- Treat Jira as the source of truth for issue metadata, status history,
  assignees, due dates, worklogs, transitions, and linked development panels.
- Treat repo code and docs as the source of truth for implementation details.
  Use Jira to understand planning and workflow state, not to replace file-backed
  analysis.

## Access Rules

- The current steady-state Jira integration in this repo goes through the
  Swarm-hosted `mcp-atlassian` service.
- That service currently runs with the upstream full tool surface enabled for
  the configured Jira credentials and project scope. Jira issue creation,
  updates, transitions, comments, and related mutations may be available
  through the current MCP path.
- Because the service is not read-only, treat every mutating Jira tool call as
  a deliberate action against the live workspace rather than a harmless
  exploratory query.

## Scope and Query Rules

- Keep Jira queries as narrow as the task allows.
- Prefer an issue key, project key, board id, sprint id, or clear text query
  over broad project-agnostic searches.
- Respect `jira_projects_filter` when the service is intentionally scoped to a
  subset of projects.
- If a task spans both Jira and Confluence, keep the Jira and Confluence parts
  conceptually separate even though they share the same MCP server.

## Analysis Rules

- Prefer direct issue reads when you already have the issue key.
- Use JQL search when the issue key is unknown but the task has enough context
  to constrain the search.
- Use changelog, SLA, dates, development info, watchers, and worklog reads only
  when they materially answer the question.
- Distinguish confirmed Jira facts from inferences about delivery risk or team
  intent.

## Coordination Rules

- When Jira findings affect code, infrastructure, or workflow behavior, carry
  that context into the technical task rather than treating Jira as a separate
  silo.
- When a stable Jira operating pattern changes, update this file and
  [`docs/workflows/jira.md`](./../workflows/jira.md) in the same task.
