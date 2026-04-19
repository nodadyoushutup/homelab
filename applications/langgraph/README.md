# LangGraph Project

This directory is now the source-of-truth home for the homelab LangGraph
project and its repo-owned container wrapper.

It contains the LangGraph and Deep Agents implementation we have been
workshopping:

- `controller-agent`: user-facing coordinator
- `code-agent`: repository analysis specialist
- `jira-agent`: Jira specialist with internal Deep Agents subagents for create
  and edit flows

## Layout

```text
applications/langgraph/
├── apps/
│   ├── controller-agent/
│   ├── code-agent/
│   └── jira-agent/
├── src/
│   └── homelab_langgraph/
├── Dockerfile
├── pyproject.toml
└── requirements.txt
```

Each deployable agent app has its own:

- `langgraph.json`
- `system_prompt.md`
- `.env` or `.env.example`
- optional `mcp.json`
- app-local skills

The Jira app also has subagent-local:

- `system_prompt.md` files loaded as runtime prompt text by the Jira app
- `.env` files loaded as config by the Jira app
- `mcp.json` files loaded as config by the Jira app
- skills directories referenced only by that internal subagent

## Current Intent

The primary local development path is one LangGraph development server that
hosts multiple graphs from the `controller-agent` app boundary, paired with a
local LangChain Agent Chat dev server that proxies into that same local backend.

What is already in place:

- a single-deployment `langgraph.json` in `apps/controller-agent` that
  exports the supervisor, code, and Jira graphs from one server
- shared Python package for reusable helpers
- supervisor-local delegation to compiled specialist graphs in the same
  deployment
- Jira internal subagents with distinct tools, skills, and config surfaces
- Markdown-backed `system_prompt.md` files for deployable agents and internal subagents
- MCP loading support from app-local and subagent-local `mcp.json` files
- a repo-owned Docker wrapper in `Dockerfile` that packages this project and
  runs `langgraph dev`

What is still expected before real deployment:

- replace `.env.example` files with real `.env` files or deployment secrets
- replace `.mcp.json.example`-style placeholders with real `mcp.json` configs
- install dependencies
- run `./agent_server.sh` from `applications/langgraph/` for the default
  `controller-agent` backend, and run `./chat.sh` from the same directory for
  the paired LangChain Agent Chat local dev path, or run `langgraph dev` from an app
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

- `langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload --n-jobs-per-worker 8`

The homelab hostname `https://langgraph.nodadyoushutup.com` is intended to
front that Kubernetes deployment.

The deployment serves:

- `controller_agent`
- `code_agent`
- `jira_agent`

The split specialist app directories still exist as the source of truth for
their local skills, MCP config, and env defaults, but the main local bring-up
path is now a single deployment.

For quick local iteration, use [`agent_server.sh`](./agent_server.sh) for the
backend and [`chat.sh`](./chat.sh) for the frontend. They run independently in
the foreground so each terminal shows the live logs directly while you manage
restarts yourself. By default, `agent_server.sh` starts the `controller-agent`
app boundary on `0.0.0.0:2124` with `8` jobs per worker, and `chat.sh` starts
the local LangChain Agent Chat app on `0.0.0.0:3000` pointing at
`http://127.0.0.1:2124`.

Helpful overrides:

- `AGENT_SERVER_PORT`: backend port override
- `AGENT_SERVER_NO_RELOAD=1`: disable backend hot reload
- `AGENT_SERVER_N_JOBS_PER_WORKER`: backend concurrency override
- `AGENT_SERVER_CLEAR_PORT=0`: skip automatic backend port cleanup
- `LANGCHAIN_AGENT_CHAT_PORT`: frontend port override
- `LANGCHAIN_AGENT_CHAT_ASSISTANT_ID`: frontend default graph id override
- `LANGCHAIN_AGENT_CHAT_LANGGRAPH_API_URL`: frontend proxy upstream override
- `LANGCHAIN_AGENT_CHAT_CLEAR_PORT=0`: skip automatic frontend port cleanup

Compatibility note:
- `agent_server.sh` still accepts the previous `LANGGRAPH_DEBUG_*` variables as
  fallbacks.
- `chat.sh` still accepts the previous `LANGCHAIN_AGENT_CHAT_DEBUG_*` and
  `CHAT_UI_DEBUG_*` variables as
  fallbacks.

The container image uses the same `8` jobs-per-worker default through
`LANGGRAPH_N_JOBS_PER_WORKER`, so you can tune the deployed runtime without
rebuilding the image.

If you need a different app boundary, run `langgraph dev` directly from that
app directory instead of reusing the shared helper.

## Docker Dev Stack

For fast host-local development with bind-mounted source code, use the
top-level [`docker/`](./../../docker/README.md) directory. That stack is a
development-only exception to the normal app-boundary layout:

- `docker/docker-compose.yml` starts one LangGraph dev container plus one chat
  UI dev container
- local Docker images are built from this repo for the dev stack
- LangGraph code is mounted from the host `applications/langgraph` directory to
  `/app/langgraph` inside the container so restarts pick up live code
- the LangGraph code mount overrides the baked app path inside that container
- the LangGraph dev container otherwise uses the image's own default `WORKDIR`
  and `CMD`, so it stays close to the published runtime shape
- the chat UI image is built from the local
  `applications/langchain-agent-chat` source tree and serves the built Next.js
  app from the image
- chat UI `NEXT_PUBLIC_*` values are compiled at build time, so changing the
  public browser URL requires rebuilding `chat-ui-dev`
- chat UI proxy traffic to LangGraph uses the Compose service DNS name plus the
  container port, currently `http://langgraph-dev:2024`

Use this when you want quick containerized restarts on your host machine. Do
not treat it as the source of truth for deployment packaging.

## Container And Publish Notes

Build context:

- `applications/langgraph/`

Dockerfile path:

- `applications/langgraph/Dockerfile`

Published image:

- `harbor.nodadyoushutup.com/controller-agent/controller-agent:<tag>`

The image name remains `controller-agent` for now because the Kubernetes app,
Harbor project, and pull-secret wiring already target that published path.
