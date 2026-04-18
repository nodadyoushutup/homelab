# Agents

This directory defines agent roles, reusable subagents, and the native
input/output schemas they use to collaborate.

## Design principles

- Always choose the agent intentionally at prompt time.
- Parent agents own role-specific behavior, prioritization, and decision-making.
- Subagents own narrow capabilities and should remain reusable across parent agents.
- Subagents should not assume who called them. They should rely on the incoming
  task input schema, not parent-specific hidden context.
- Each agent or subagent should document its own accepted input schema and
  emitted output schema in its own file.
- Callers should adapt to the callee's documented schema instead of relying on
  a repo-wide shared protocol file.

## Current agent set

- Parent agent: `Homelab`
- Subagent: `Code`
- Subagent: `Confluence`
- Subagent: `Kubernetes`
- Subagent: `Pipeline`
- Subagent: `Terraform`
- Subagent: `Jira`

## File map

- `homelab-agent.md`: the current top-level supervisor definition for the
  Homelab agent, including its native input/output schema
- `subagents/code-subagent.md`: reusable code capability definition, including
  its native input/output schema
- `subagents/confluence-subagent.md`: reusable Confluence discovery and
  operations capability definition, including its native input/output schema
- `subagents/kubernetes-subagent.md`: reusable Kubernetes analysis capability
  definition, including its native input/output schema
- `subagents/pipeline-subagent.md`: reusable pipeline inspection and execution
  capability definition, including its native input/output schema
- `subagents/terraform-subagent.md`: reusable Terraform analysis capability
  definition, including its native input/output schema
- `subagents/jira-subagent.md`: reusable Jira discovery and operations
  capability definition, including its native input/output schema

## Required creation artifacts

When adding a new repo-managed agent or subagent, create the Python
implementation and the Markdown contract docs in the same change.

Required parent-agent artifacts:

- repo-managed Python implementation under `applications/langgraph/`
- `docs/agents/<agent-name>-agent.md`
- matching updates in this file for the current agent set, file map, and
  runtime prompt source

Required subagent artifacts:

- repo-managed Python implementation under `applications/langgraph/`
- `docs/agents/subagents/<subagent-name>-subagent.md`
- matching updates in this file for the current agent set, file map, and
  runtime prompt source

Do not treat a new agent or subagent as part of the supported agent set until
both the Python file and the Markdown file exist.

## Runtime Prompt Source

These files are the source-of-truth prompt docs for repo-managed agent
runtimes.

Current intent:

- keep `homelab-agent.md` as the instruction contract for the parent `Homelab`
  agent
- keep `subagents/code-subagent.md` as the instruction contract for the `Code`
  subagent
- keep `subagents/confluence-subagent.md` as the instruction contract for the
  `Confluence` subagent
- keep `subagents/kubernetes-subagent.md` as the instruction contract for the
  `Kubernetes` subagent
- keep `subagents/pipeline-subagent.md` as the instruction contract for the
  `Pipeline` subagent
- keep `subagents/terraform-subagent.md` as the instruction contract for the
  `Terraform` subagent
- keep `subagents/jira-subagent.md` as the instruction contract for the `Jira`
  subagent
- use each agent's own documented schema as the source of truth for how that
  agent accepts input and returns output

When the runtime wiring changes, update these docs first so the prompt text and
repo behavior stay aligned.

## Current handoff model

For now, do not assume Redis-backed shared memory or any other shared agent
state layer.

Current expectation:

- every agent call must include the context needed for that specific task
- every agent and subagent doc must define the input shape it accepts and the
  output shape it returns
- callers should read the target agent or subagent doc and shape the call to
  match that documented schema
- parent agents should use subagent output schemas to decide the next call,
  the next tool action, or the final user response
- every agent should check the relevant `docs/` material before falling back to
  broad repo search

This keeps runtime orchestration simple while the agent set is still evolving.

## Selection workflow

Before starting work, explicitly choose the agent that should own the task.

If the prompt does not name an agent, select one intentionally before execution rather than defaulting to an unnamed general agent.

Use [docs/workflows/agents.md](./../workflows/agents.md) for the operational
selection flow and lock-in rule.

Required behavior:

- choose the owning parent agent before implementation or investigation starts
- choose any needed subagents from the documented subagent set based on
  capability
- lock that agent set before proceeding
- if the task changes materially, explicitly re-evaluate and re-lock the agent set

Current default choices:

- Use `Homelab` when the task needs implementation, debugging, code changes, repo navigation, or orchestration of technical subtasks.
- Use `Code` only as a delegated capability through a parent agent, or directly
  when the only goal is source-of-truth analysis without implementation.
- Use `Confluence` only as a delegated capability through a parent agent, or directly when the goal is Confluence-backed document or page work, including discovery, creation, editing, comments, and related coordination.
- Use `Kubernetes` only as a delegated capability through a parent agent, or directly when the only goal is Kubernetes-backed manifest and delivery analysis without implementation.
- Use `Pipeline` only as a delegated capability through a parent agent, or directly when the goal is repo-managed pipeline inspection or bounded pipeline execution through the configured pipeline tools.
- Use `Terraform` only as a delegated capability through a parent agent, or directly when the only goal is Terraform-backed infrastructure analysis without implementation.
- Use `Jira` only as a delegated capability through a parent agent, or directly
  when the goal is Jira-backed issue or workflow work, including discovery,
  creation, editing, comments, transitions, and related coordination.

## Architecture rule

Parent agents may use any compatible subagent. Subagents must be designed so they can be mixed and matched across different parent agents without rewriting their core instructions.
