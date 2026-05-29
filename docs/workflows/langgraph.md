# LangGraph Workflow

This document describes how to operate and evolve the repo-managed LangGraph and
Deep Agents scaffold under `applications/langgraph/`.

For how the default **`agent`** supervisor delegates to specialists and chains
results, see [`agent-orchestration.md`](./agent-orchestration.md).

## Scope

Use this workflow for:

- changes under `applications/langgraph/framework/`
- changes to deployable agent configs under `applications/langgraph/agent/`
  and `applications/langgraph/subagents/*/`
- changes to agent-local or subagent-local skills
- changes to agent-local or subagent-local MCP wiring
- changes to the top-level `docker/` LangGraph dev stack

## Standard Flow

When a task changes the LangGraph implementation:

1. decide whether the change affects:
   - shared LangGraph package code
   - a deployable agent boundary
   - an internal Deep Agents subagent
   - skills
   - MCP wiring
2. keep shared code in `applications/langgraph/framework/` and the
   default Homelab agent boundary under `applications/langgraph/agent/`,
   with specialist directories under `applications/langgraph/subagents/`
   - put reusable class-based agent builders under
     `applications/langgraph/framework/agents/`
   - put concrete runtime instantiation, MCP config, skills, and
     `langgraph.json` exports in the app or subagent directory
   - put concrete runtime prompt docs in `docs/subagents/<runtime-name>/`
3. decide whether the target app should expose:
   - one graph
   - multiple sibling graphs in one deployment
   - internal Deep Agents subagents inside one graph
   - prefer a single agent-level agent first; add internal subagents only when a
     narrower capability needs its own tool surface, skills, or prompt
   - for the default Homelab runtime, keep `agent` as the only user-facing graph
     and wire specialists as private local subagents behind that supervisor
4. if the task adds a new deployable agent:
   - create its agent directory
   - add `agent.py`
   - add `langgraph.json`
   - add object-level prompt docs under `docs/subagents/<runtime-name>/`
   - use an existing builder class from `framework/agents/`, or add a new
     reusable builder there when the behavior should be shared by multiple
     concrete agents
   - document any new settings in the homelab ``.config/docker/`` pattern (see
     ``.config/docker/.example`` when present); when asked to edit the LangGraph
     `.env`, update `<repo>/.config/docker/` itself; do not add per-agent ``.env``
     files
5. if the task adds a new internal Deep Agents subagent:
   - add its task-specific config directory inside the owning app
   - add object-level prompt docs under `docs/subagents/<runtime-name>/`
   - add any subagent-local skills or MCP config there
   - instantiate the appropriate `framework/agents/` builder in that directory's
     `agent.py`, or add a new builder if the implementation should be reusable
   - wire it explicitly in the parent app code
   - if the task removes an internal subagent, fold the surviving prompt and
     skill rules back into the owning app and delete the obsolete subagent
     config
6. if the task adds MCP-backed tools:
   - keep agent-level MCP configs with the agent
   - keep subagent-level MCP configs with the subagent
   - prefer HTTP/SSE transports for anything intended to be deployed
   - wrap expected runtime MCP tool-call failures as recoverable tool results so
     the model can retry, narrow arguments, ask for missing inputs, or report a
     concrete blocker
   - when the backing MCP server exposes a broader shared workspace than the
     target repo, add app-side wrappers or constraints so the model sees the
     intended repository root and default excludes instead of the full shared
     tree
   - keep **`mcp-rag`** in the supervisor and every specialist `mcp.json`; gate
     and memory policy live in
     `docs/workflows/rag-agent-mcp-integration-roadmap.md` and
     `applications/langgraph/framework/middleware/workflow_gates.py`
7. if the task changes one app from a single graph to multiple sibling graphs:
   - keep those graph exports together in that app's `langgraph.json`
   - keep reusable graph builder code in
     `applications/langgraph/framework/agents/`, with compatibility factories in
     `applications/langgraph/framework/agent_factories.py` only when needed
   - prefer in-process composition before adding remote transport
   - if you intentionally split a formerly local specialist into a remote app,
     add the real transport in that same task instead of leaving unused remote
     delegation scaffolding behind
8. if the task changes supervisor routing or prompt text:
   - keep routing aligned with the specialists actually wired into the runtime;
     if a capability has no specialist, report that limitation instead of
     inventing one
   - preserve the return-to-supervisor contract documented in
     [`agent-orchestration.md`](./agent-orchestration.md): every specialist call
     returns a result to `agent`, and only `agent` decides the next step
   - do not add peer-to-peer specialist handoffs; model chains as
     `agent -> specialist -> agent -> next_specialist -> agent`
   - keep prompt text in the layered prompt sources instead of reintroducing
     long inline Python prompts: base guardrails in
     `framework/agents/system_prompts/base_system_prompt.md`, reusable
     class-level guidance in framework agent prompt files, and concrete runtime
     docs under `docs/subagents/<runtime-name>/`
   - keep `docs/workflows/agents.md` and the layered prompt sources in sync
9. validate the Python structure after the change
10. update docs if the stable pattern changed
11. if the task adds a repo helper script, keep it boundary-scoped and make
    sure it only wraps the intended app's local `langgraph dev` startup, plus
    any tightly paired local frontend that belongs to the same debug workflow
12. if the task adds or changes the top-level `docker/` dev stack:
   - keep it explicitly development-only
   - mount source code from the working tree instead of replacing deployment
     sources of truth
   - for LangChain Agent Chat in Compose, prefer the baked **`runner`** image
     (`target: runner`, no app bind mount): **`docker compose build langchain-agent-chat-dev`**
     after UI or dependency changes, then **`up`**. Use host **`pnpm dev`** when actively iterating on chat UI
   - document the expected ports, env file, and restart workflow
13. if the task also updates the default deployed Homelab runtime manifests:
   - keep the Kubernetes app family under `kubernetes/langgraph/`
   - keep the launched LangGraph agent boundary under
     `applications/langgraph/agent/`

## Validation

After changing the LangGraph scaffold:

1. run a syntax check such as
   `python3 -m compileall applications/langgraph/agent applications/langgraph/subagents applications/langgraph/framework`
2. validate any `langgraph.json` files you changed
3. if dependencies are installed, start the target app locally from its app
   directory with `langgraph dev`, or use `applications/langgraph/docker/agent_server.sh`
   for the default `langgraph` backend and `applications/langgraph/docker/chat.sh` for the
   paired local LangChain Agent Chat app when you are intentionally testing that local
   dev path (ensure ``.config/docker/`` exists at the homelab repo root; do not use
   a LangGraph app-local ``.env`` file)
4. if the change touches the Docker dev stack, validate the dev pair against
   Docker endpoints only: chat at `http://localhost:3000`, chat API passthrough
   at `http://localhost:3000/api`, and LangGraph upstream
   `http://langgraph-dev:2024` inside Compose (`http://localhost:2124` from the
   host)
5. if the change touches supervisor routing, verify that only wired specialists
   are referenced by the supervisor prompt and runtime config
6. if the change touches repo-backed filesystem MCP usage, verify that the
   exposed filesystem tools stay scoped to the intended repository root and
   that broad searches pick up the default excludes
7. if the change touches supervisor or specialist delegation, verify that the
   local runtime still exposes the top-level `agent` graph, routes to the
   intended named specialist, and returns specialist output to the supervisor
   before any second specialist call
8. if the change touches the top-level `docker/` stack, run `docker compose
   config` from `docker/` to validate the compose file

## Structure Guidance

Use this rough pattern:

- `applications/langgraph/framework/`: shared Python package (`import framework`)
  and reusable helpers
- `applications/langgraph/framework/agents/`: class-based reusable builders such
  as `BaseAgent`, `CodeAgent`, `JiraAgent`, `TechLeadAgent`, and
  `HomelabSupervisorAgent`
- `applications/langgraph/agent/`: default Homelab deployable agent
  boundary, which may expose one graph or multiple sibling graphs
- `applications/langgraph/subagents/<specialist>/`: specialist skills,
  MCP wiring, and optional standalone `langgraph dev` configs for co-deployed
  specialist graphs such as Code, Jira, and Tech Lead
- `docs/subagents/<runtime-name>/`: concrete runtime prompt docs loaded into
  the final system prompt

Do not move `langgraph.json` up to the monorepo root just to make local running
feel simpler. Keep each agent independently deployable.

Internal subagents are optional. The current `code`, `jira`, and `tech_lead`
specialists intentionally run as single-layer agents and keep their operating
rules at the app level.
