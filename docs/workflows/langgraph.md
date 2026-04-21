# LangGraph Workflow

This document describes how to operate and evolve the repo-managed LangGraph and
Deep Agents scaffold under `applications/langgraph/`.

Use [docs/rules/langgraph.md](./../rules/langgraph.md) for the steady-state
rules.

## Scope

Use this workflow for:

- changes under `applications/langgraph/src/`
- changes to deployable app configs under `applications/langgraph/apps/*/`
- changes to app-local or subagent-local skills
- changes to app-local or subagent-local MCP wiring
- changes to the top-level `docker/` LangGraph dev stack

## Standard Flow

When a task changes the LangGraph implementation:

1. decide whether the change affects:
   - shared LangGraph package code
   - a deployable app boundary
   - an internal Deep Agents subagent
   - skills
   - MCP wiring
2. read `docs/rules/langgraph.md` before editing
3. keep shared code in `applications/langgraph/src/` and app
   entrypoints/configs in `applications/langgraph/apps/<app-name>/`
4. decide whether the target app should expose:
   - one graph
   - multiple sibling graphs in one deployment
   - internal Deep Agents subagents inside one graph
   - prefer a single app-level agent first; add internal subagents only when a
     narrower capability needs its own tool surface, skills, or prompt
5. if the task adds a new deployable app:
   - create its app directory
   - add `agent.py`
   - add `langgraph.json`
   - add `system_prompt.md`
   - add `.env.example`
6. if the task adds a new internal Deep Agents subagent:
   - add its task-specific config directory inside the owning app
   - add `system_prompt.md`
   - add any subagent-local skills or MCP config there
   - wire it explicitly in the parent app code
   - if the task removes an internal subagent, fold the surviving prompt and
     skill rules back into the owning app and delete the obsolete subagent
     config
7. if the task adds MCP-backed tools:
   - keep app-level MCP configs with the app
   - keep subagent-level MCP configs with the subagent
   - prefer HTTP/SSE transports for anything intended to be deployed
   - when the backing MCP server exposes a broader shared workspace than the
     target repo, add app-side wrappers or constraints so the model sees the
     intended repository root and default excludes instead of the full shared
     tree
8. if the task changes one app from a single graph to multiple sibling graphs:
   - keep those graph exports together in that app's `langgraph.json`
   - keep graph factory code in shared `applications/langgraph/src/` modules
     or the app's entrypoint as appropriate
   - prefer in-process composition before adding remote transport
9. if the task changes supervisor routing or prompt text:
   - keep code, config, file, path, filesystem, and MCP workspace questions
     routed through the `Code` specialist instead of answered directly by the
     parent
   - keep prompt text in the relevant app-local or subagent-local
     `system_prompt.md` file instead of reintroducing long inline Python prompts
   - keep the relevant contract docs under `docs/agents/` in sync
10. validate the Python structure after the change
11. update docs if the stable pattern changed
12. if the task adds a repo helper script, keep it boundary-scoped and make
    sure it only wraps the intended app's local `langgraph dev` startup, plus
    any tightly paired local frontend that belongs to the same debug workflow
13. if the task adds or changes the top-level `docker/` dev stack:
   - keep it explicitly development-only
   - mount source code from the working tree instead of replacing deployment
     sources of truth
   - document the expected ports, env file, and restart workflow
14. if the task also updates the default deployed Homelab runtime manifests:
   - keep the Kubernetes app family under `kubernetes/langgraph/`
   - keep the launched LangGraph app boundary under
     `applications/langgraph/apps/langgraph/`

## Validation

After changing the LangGraph scaffold:

1. run a syntax check such as `python3 -m compileall applications/langgraph`
2. validate any `langgraph.json` files you changed
3. if dependencies are installed, start the target app locally from its app
   directory with `langgraph dev`, or use
   `applications/langgraph/agent_server.sh` for the default
   `langgraph` backend and `applications/langgraph/chat.sh` for the
   paired local LangChain Agent Chat app when you are intentionally testing that local
   dev path
4. if the change touches supervisor routing, verify that code and filesystem
   questions still delegate to the `Code` specialist
5. if the change touches repo-backed filesystem MCP usage, verify that the
   exposed filesystem tools stay scoped to the intended repository root and
   that broad searches pick up the default excludes
6. if the change touches remote delegation, verify the relevant env values and
   graph ids before expecting A2A calls to succeed
7. if the change touches the top-level `docker/` stack, run `docker compose
   config` from `docker/` to validate the compose file

## Structure Guidance

Use this rough pattern:

- `applications/langgraph/src/`: shared package and reusable helpers
- `applications/langgraph/apps/<deployable-agent>/`: one deployable app
  boundary, which may expose one graph or multiple sibling graphs
- `applications/langgraph/apps/<deployable-agent>/subagents/<subagent>/`:
  config, skills, and MCP wiring that belong only to an internal Deep Agents
  subagent

Do not move `langgraph.json` up to the monorepo root just to make local running
feel simpler. Keep each app independently deployable.

Internal subagents are optional. The current `jira-agent` intentionally runs as
a single-layer agent and keeps its Jira operating rules at the app level.
