# Agent Workflow

This document defines how work must choose and use agents in this repo.

Use [`docs/agents/README.md`](./../agents/README.md) for the current agent set
and role definitions. Use the selected agent and subagent docs for their native
input/output schemas.

## Required Startup Flow

Before execution starts:

1. read `docs/agents/README.md`
2. identify the owning parent agent for the task
3. identify any subagents that are needed based on their documented capability
4. lock the agent set before starting implementation or investigation
5. proceed using that agent set

Do not begin work as an unspecified generic agent.

## Selection Rules

- If the prompt explicitly names an agent and that agent exists in
  `docs/agents/README.md`, use it as the owner unless the request conflicts with
  the documented role.
- If the prompt does not name an agent, choose one intentionally from the
  documented agent set before doing any substantive work.
- Choose subagents from the documented subagent list based on the capability
  needed, not on hidden caller assumptions.

## Lock-In Rule

Agent selection is not an afterthought.

- The owning parent agent must be chosen first.
- Any subagents to be used for the task must be identified before proceeding.
- Once that agent set is locked in, execution should continue through those
  documented agents and subagents.

If the task changes enough that the chosen agent set is no longer appropriate,
re-evaluate and explicitly re-lock the agent set.

## Creation Rule

When the work creates a new parent agent or subagent, treat the repo-managed
Python file and the Markdown contract doc as one unit of work.

Required steps:

1. create the Python implementation under the active runtime path in
   `applications/langgraph/`
2. create the matching Markdown instructions/schema file in `docs/agents/` or
   `docs/agents/subagents/`
3. update `docs/agents/README.md` so the new agent is part of the documented
   agent set, file map, and runtime prompt source
4. only then treat the new agent or subagent as selectable in this workflow

Do not create a doc-only agent or a Python-only agent.

## Delegation Rule

- Parent agents own behavior, prioritization, and final decisions.
- Subagents own narrow reusable capabilities.
- Subagents should not depend on a specific parent unless a human explicitly
  asks for a parent-specific variant.
- When one agent delegates work to another, shape the input to match the
  callee's documented input schema and consume the callee's documented output
  schema.
