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
  LangGraph app boundary, exposed through one user-facing graph named `agent`.
  Do not maintain repo-specific remote `call_*_agent` wrappers unless a future
  task explicitly reintroduces a remote boundary.
- The current Homelab runtime is hub-and-spoke: `agent` chooses the subagent,
  receives the subagent response, and decides the next step. Subagents may
  recommend another subagent, but they must not transfer directly to one.
- Subagents should not assume who called them. They should rely on the incoming
  task input schema, not parent-specific hidden context.
- Each agent or subagent should document its own accepted input schema and
  emitted output schema in its own file.
- Callers should adapt to the callee's documented schema instead of relying on
  a repo-wide shared protocol file.

## Current runtime set

- Parent agent: `Homelab`
- Subagent: `Code`
- Subagent: `Git`
- Subagent: `Jira`
- Subagent: `Tech Lead`

## File map

- `homelab-agent/homelab-agent.md`: the current top-level supervisor definition
  for the Homelab agent, including its native input/output schema
- `../subagents/code/*.md`: runtime Code repository analysis and implementation
  prompt docs, including its native input/output schema
- `../subagents/git/*.md`: runtime Git + GitHub workflow prompt docs, including
  its native input/output schema
- `../subagents/jira/*.md`: runtime Jira discovery and operations prompt docs,
  including its native input/output schema
- `../subagents/tech-lead/*.md`: runtime Tech Lead technical review prompt docs,
  including its native input/output schema

## Required creation artifacts

When adding a new repo-managed runtime agent or subagent, create the concrete
Python instantiation and the Markdown contract docs in the same change.
Reusable builder classes under `applications/langgraph/framework/agents/` are
implementation scaffolding; they are not part of the supported runtime set
until an app or subagent directory instantiates and exports them.

Required parent-agent artifacts:

- repo-managed Python instantiation under a concrete `applications/langgraph/`
  app directory, optionally backed by a reusable builder class in
  `applications/langgraph/framework/agents/`
- `docs/agents/<agent-name>-agent/<agent-name>-agent.md`
- matching updates in this file for the current agent set, file map, and
  runtime prompt source

Required subagent artifacts:

- repo-managed Python instantiation under a concrete `applications/langgraph/`
  subagent directory, optionally backed by a reusable builder class in
  `applications/langgraph/framework/agents/`
- `docs/subagents/<runtime-name>/*.md`
- matching updates in this file for the current agent set, file map, and
  runtime prompt source

Do not treat a new agent or subagent as part of the supported agent set until
both the Python file and the Markdown file exist.

## Runtime Prompt Source

The runtime prompt source for repo-managed LangGraph agents is assembled in
layers.

Current prompt-source pattern:

- shared guardrails for every agent and subagent live in
  `applications/langgraph/framework/agents/system_prompts/base_system_prompt.md`
- reusable class-level guidance lives with the reusable builder, for example
  `applications/langgraph/framework/agents/system_prompts/jira_system_prompt.md`
- concrete runtime object-level prompt docs live in
  `docs/subagents/<runtime-name>/*.md`
- nested internal subagent prompts, when used, should live under the owning
  specialist's object-level docs or an equivalent `docs/subagents/<runtime-name>/`
  directory
- Python wiring under `applications/langgraph/framework/agents/` should load
  those Markdown layers and pass the resulting text into the runtime's
  `system_prompt` argument

These docs remain the human-readable runtime contracts and schema references.

Current intent:

- keep `homelab-agent/homelab-agent.md` as the instruction contract for the
  parent `Homelab` agent
- keep `../subagents/code/*.md` as the instruction contract for the single-layer
  `Code` subagent
- keep `../subagents/git/*.md` as the instruction contract for the single-layer
  `Git` subagent
- keep `../subagents/jira/*.md` as the instruction contract for the single-layer
  `Jira` subagent
- keep `../subagents/tech-lead/*.md` as the instruction contract for the
  single-layer `Tech Lead` subagent
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
- subagent outputs must return to the parent agent before any further specialist
  call; a subagent-to-subagent handoff is only a recommendation in the output,
  not a direct transfer
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
- The default Homelab app exposes `agent` as the supported graph. Specialist
  runnables are private implementation details of that supervisor unless a
  future task explicitly creates a separate deployment boundary.
- `Code`, `Git`, `Jira`, and `Tech Lead` remain reusable specialist capabilities for
  their respective domains.
- If runtime routing changes materially, update both the Python wiring under
  `applications/langgraph/` and the matching contract docs in this directory.

## Architecture rule

Parent agents may use any compatible subagent. Subagents must be designed so they can be mixed and matched across different parent agents without rewriting their core instructions.
