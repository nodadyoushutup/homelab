# LangGraph Project

This directory is now the source-of-truth home for the homelab LangGraph
project and its repo-owned container wrapper.

It contains the LangGraph and Deep Agents implementation we have been
workshopping:

- `controller-agent`: user-facing coordinator
- `code-analysis-agent`: repository analysis specialist
- `jira-agent`: Jira specialist with internal Deep Agents subagents for create
  and edit flows

## Layout

```text
applications/langgraph/
├── apps/
│   ├── controller-agent/
│   ├── code-analysis-agent/
│   └── jira-agent/
├── src/
│   └── homelab_langgraph/
├── Dockerfile
├── pyproject.toml
└── requirements.txt
```

Each deployable agent app has its own:

- `langgraph.json`
- `.env` or `.env.example`
- optional `mcp.json`
- app-local skills

The Jira app also has subagent-local:

- `.env` files loaded as config by the Jira app
- `mcp.json` files loaded as config by the Jira app
- skills directories referenced only by that internal subagent

## Current Intent

The primary local development path is one LangGraph development server that
hosts multiple graphs from the `controller-agent` app boundary.

What is already in place:

- a single-deployment `langgraph.json` in `apps/controller-agent` that
  exports the supervisor, code-analysis, and Jira graphs from one server
- shared Python package for reusable helpers
- supervisor-local delegation to compiled specialist graphs in the same
  deployment
- Jira internal subagents with distinct tools, skills, and config surfaces
- MCP loading support from app-local and subagent-local `mcp.json` files
- a repo-owned Docker wrapper in `Dockerfile` that packages this project and
  runs `langgraph dev`

What is still expected before real deployment:

- replace `.env.example` files with real `.env` files or deployment secrets
- replace `.mcp.json.example`-style placeholders with real `mcp.json` configs
- install dependencies
- run `./debug.sh` from `applications/langgraph/` for the default
  `controller-agent` local dev path, or run `langgraph dev` from an app
  directory when you want a different app boundary

## Model And API Key Defaults

The scaffold now defaults all LangGraph apps to `openai:gpt-5.4`.

Set `OPENAI_API_KEY` in each deployable app's `.env` file, or inject it through
your deployment environment. The app-local `langgraph.json` files already point
the runtime at each app's `.env`, so adding the key there is the simplest local
setup path.

## Runtime

The primary runtime path is now the Kubernetes `controller-agent` deployment.
That workload builds this directory into an image and starts the server with
the Docker `CMD` from [`Dockerfile`](./Dockerfile):

- `langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload`

The homelab hostname `https://langgraph.nodadyoushutup.com` is intended to
front that Kubernetes deployment.

The deployment serves:

- `controller_agent`
- `code_analysis_agent`
- `jira_agent`

The split specialist app directories still exist as the source of truth for
their local skills, MCP config, and env defaults, but the main local bring-up
path is now a single deployment.

For quick local iteration, use [`debug.sh`](./debug.sh) from this directory.
It starts the `controller-agent` app boundary on `0.0.0.0:2124` by default,
keeps browser launch disabled, and leaves hot reload on unless
`LANGGRAPH_DEBUG_NO_RELOAD=1` is set.

If you need a different app boundary, run `langgraph dev` directly from that
app directory instead of reusing the shared helper.

## Container And Publish Notes

Build context:

- `applications/langgraph/`

Dockerfile path:

- `applications/langgraph/Dockerfile`

Published image:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`

The image name remains `controller-agent` for now because the Kubernetes app,
Harbor project, and pull-secret wiring already target that published path.
