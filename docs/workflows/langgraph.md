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
5. if the task adds a new deployable app:
   - create its app directory
   - add `agent.py`
   - add `langgraph.json`
   - add `.env.example`
6. if the task adds a new internal Deep Agents subagent:
   - add its task-specific config directory inside the owning app
   - add any subagent-local skills or MCP config there
   - wire it explicitly in the parent app code
7. if the task adds MCP-backed tools:
   - keep app-level MCP configs with the app
   - keep subagent-level MCP configs with the subagent
   - prefer HTTP/SSE transports for anything intended to be deployed
8. if the task changes one app from a single graph to multiple sibling graphs:
   - keep those graph exports together in that app's `langgraph.json`
   - keep graph factory code in shared `applications/langgraph/src/` modules
     or the app's entrypoint as appropriate
   - prefer in-process composition before adding remote transport
9. validate the Python structure after the change
10. update docs if the stable pattern changed

## Validation

After changing the LangGraph scaffold:

1. run a syntax check such as `python3 -m compileall applications/langgraph`
2. validate any `langgraph.json` files you changed
3. if dependencies are installed, start the target app locally from its app
   directory with `langgraph dev`, or use `applications/langgraph/run.sh up`
   when the change spans multiple app boundaries
4. if the change touches remote delegation, verify the relevant env values and
   graph ids before expecting A2A calls to succeed

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
