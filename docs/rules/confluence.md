# Confluence Rules

This document defines the steady-state rules for how this repo uses Confluence
for page lookup, documentation analysis, and linked Atlassian context. Use
[`docs/workflows/confluence.md`](./../workflows/confluence.md) for the
operator flow.

## Scope

This document applies to:

- Confluence access through the `mcp-atlassian` server
- Confluence-backed analysis performed by repo agents and subagents
- Confluence references that inform engineering implementation, operations, and
  documentation analysis in this repo

## Source of Truth

- Treat Confluence as the source of truth for published page content, page
  hierarchy, labels, comments, attachments, and page history that the current
  space exposes.
- Treat repo code and docs as the source of truth for implementation details.
  Use Confluence to understand documented operating context, not to replace
  file-backed analysis.

## Access Rules

- The current steady-state Confluence integration in this repo goes through the
  Swarm-hosted `mcp-atlassian` service.
- That service currently runs with the upstream full tool surface enabled for
  the configured Confluence credentials and space scope. Confluence page
  creation, edits, comments, labels, and attachment mutations may be available
  through the current MCP path.
- Because the service is not read-only, treat every mutating Confluence tool
  call as a deliberate action against the live workspace rather than a harmless
  exploratory query.

## Scope and Query Rules

- Keep Confluence queries as narrow as the task allows.
- Prefer a page id, content id, space key, exact title, or constrained text
  search over broad space-agnostic queries.
- Respect `confluence_spaces_filter` when the service is intentionally scoped
  to a subset of spaces.
- If a task spans both Jira and Confluence, keep the Jira and Confluence parts
  conceptually separate even though they share the same MCP server.

## Analysis Rules

- Prefer direct page reads when you already have the page id or an exact title
  plus space key.
- Use search when the page id is unknown but the task has enough context to
  constrain the search.
- Use page children, comments, labels, attachments, history, diff, or views
  only when they materially answer the question.
- Distinguish confirmed Confluence facts from inferences about document quality,
  recency, or team intent.

## Coordination Rules

- When Confluence findings affect code, infrastructure, or workflow behavior,
  carry that context into the technical task rather than treating Confluence as
  a separate silo.
- When a stable Confluence operating pattern changes, update this file and
  [`docs/workflows/confluence.md`](./../workflows/confluence.md) in the same
  task.
