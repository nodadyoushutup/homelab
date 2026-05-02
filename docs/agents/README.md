# LangGraph Agent Contracts

This directory defines the runtime contracts for the repo-managed LangGraph
agents under `applications/langgraph/`.

These docs describe runtime behavior, delegation boundaries, and native
input/output schemas. They are not a repo-wide contributor startup checklist.

## Design principles

- Route work intentionally inside the runtime instead of relying on unnamed
  generic behavior.
- Parent agents own role-specific behavior, prioritization, and decision-making.
- Subagents own narrow capabilities and should remain reusable across parent agents.
- The current Homelab runtime uses named in-process subagents inside one
  LangGraph app boundary. Do not maintain repo-specific remote `call_*_agent`
  wrappers unless a future task explicitly reintroduces a remote boundary.
- Subagents should not assume who called them. They should rely on the incoming
  task input schema, not parent-specific hidden context.
- Each agent or subagent should document its own accepted input schema and
  emitted output schema in its own file.
- Callers should adapt to the callee's documented schema instead of relying on
  a repo-wide shared protocol file.

## Current runtime set

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

The runtime prompt source for repo-managed LangGraph agents lives alongside the
agents themselves.

Current prompt-source pattern:

- agent-level prompt text should live in
  `applications/langgraph/src/agents/<agent-name>/system_prompt.md`
- internal subagent prompt text should live in
  `applications/langgraph/src/agents/<agent-name>/subagents/<subagent-name>/system_prompt.md`
- Python wiring under `applications/langgraph/src/base/` should load those Markdown
  files and pass the resulting text into the runtime's `system_prompt`
  argument

These docs remain the human-readable runtime contracts and schema references.

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
- keep `subagents/jira-subagent.md` as the instruction contract for the
  single-layer `Jira` subagent
- use each agent's own documented schema as the source of truth for how that
  agent accepts input and returns output

When the runtime wiring changes, update these docs first so the prompt text and
runtime behavior stay aligned.

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

## Runtime routing expectations

Use [docs/workflows/agents.md](./../workflows/agents.md) when you are updating
the LangGraph runtime contracts or their implementation.

Current expectations:

- `Homelab` is the coordinating supervisor for runtime orchestration.
- `Homelab` should delegate to local named specialists through the runtime's
  native subagent surface instead of a repo-specific remote call wrapper.
- `Code` is the mandatory specialist for code, config, repository structure,
  file paths, filesystem visibility, MCP workspace inspection, and
  implementation questions.
- `Confluence`, `Kubernetes`, `Pipeline`, `Terraform`, and `Jira` remain
  reusable specialist capabilities for their respective domains.
- If runtime routing changes materially, update both the Python wiring under
  `applications/langgraph/` and the matching contract docs in this directory.

## Architecture rule

Parent agents may use any compatible subagent. Subagents must be designed so they can be mixed and matched across different parent agents without rewriting their core instructions.
