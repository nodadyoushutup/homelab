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
  Kubernetes-hosted `mcp-atlassian` service.
- That service currently runs with the upstream full tool surface enabled for
  the configured Jira credentials and project scope. Jira issue creation,
  updates, transitions, comments, and related mutations may be available
  through the current MCP path.
- Because the service is not read-only, treat every mutating Jira tool call as
  a deliberate action against the live workspace rather than a harmless
  exploratory query.
- When a Jira tool argument is optional, omit it rather than sending an empty
  string.
- When a Jira tool argument is documented as a JSON string, pass valid JSON
  only when that field is actually needed.
- For pure status changes, prefer `jira_transition_issue` with only the
  required transition arguments unless Jira explicitly requires extra fields.
- If a status change also needs a note, prefer a separate `jira_add_comment`
  call instead of the transition-comment field.
- For `jira_add_comment`, do not set the optional `public` flag unless the
  issue is confirmed to be a JSM service-desk request and that visibility mode
  is actually intended.

## Scope and Query Rules

- Keep Jira queries as narrow as the task allows.
- Prefer an issue key, project key, board id, sprint id, or clear text query
  over broad project-agnostic searches.
- Respect `jira_projects_filter` when the service is intentionally scoped to a
  subset of projects.
- For net-new issue creation, use the runtime's configured default Jira project
  when the user does not specify one, and only ask for a project when live Jira
  metadata or task context makes the default ambiguous or invalid.
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
- Keep repo-specific Jira custom field meanings and usage rules in the
  `jira-custom-fields` skill under `applications/langgraph/apps/jira-agent/skills/`.
- Keep repo-specific Jira required field rules and stage-gate logic in the
  `jira-required-fields` skill under `applications/langgraph/apps/jira-agent/skills/`.
- Keep repo-specific stage-aware workflow guidance in the `jira-workflow` skill
  under `applications/langgraph/apps/jira-agent/skills/`.
- Do not allow a ticket to progress out of `REQUIREMENTS` until all required
  Jira fields are filled and a hard verification check confirms that state.
- Jira agents should identify the current workflow stage before acting and tie
  each Jira action to completing, unblocking, or advancing that stage.
- Jira agents should prefer using live Jira state plus the workflow skill to
  infer the next likely stage instead of asking generic readiness questions.
- When a stage is complete, Jira agents should invite the next workflow step in
  their recommended follow-up actions.
- The current issue-type selection pattern in this repo is:
- `Story` for requested code work or new feature work where there is no broken behavior to fix
- `Bug` for fixing broken behavior
- `Task` for simple one-off work, including the special case where a user explicitly wants a lighter quick-task path instead of the fuller lifecycle
- `Subtask` as a rare child-work issue under an existing parent when explicit checklist-like tracking is desired
- The current `Bug` lifecycle in this repo starts with a brief baseline summary
  in `TO DO`, expands the issue description in `REQUIREMENTS`, may add
  replicate findings as comments, adds cited implementation guidance and test
  planning in `TECH LEAD`, and then hands implementation to the technical
  execution path.
- For `Bug` issues, the Jira description should use stable sections such as
  `Overview`, `Scope`, `Requirements`, `Acceptance Criteria`, `Tech Lead
  Notes`, and `Test Plans` as the ticket matures.
- For `Bug` issues, format `Requirements` as ordered `REQ-*` items and
  `Acceptance Criteria` as ordered `AC-*` items so later work can refer to them
  precisely.
- The current `Story` lifecycle in this repo should be treated the same as the
  `Bug` lifecycle for baseline capture, requirements expansion, technical
  validation, implementation handoff, and description structure.
- The main functional difference is that `Story` does not include the
  `REPLICATE` stage.
- The current `Task` lifecycle in this repo should use the same baseline
  capture and requirements-expansion model as `Story` and `Bug`, but it may
  move directly from `REQUIREMENTS` to `DONE` once the work is performed.
- The current `Subtask` lifecycle in this repo is intentionally minimal and is
  best treated as `TO DO`, `DONE`, or `CANCELED` under a parent issue.
- The current delivery shortcut allows code to land directly on `main` while
  Jira still moves through the later workflow stages as a temporary operating
  convention.
- When a stable Jira operating pattern changes, update this file and
  [`docs/workflows/jira.md`](./../workflows/jira.md) in the same task.
