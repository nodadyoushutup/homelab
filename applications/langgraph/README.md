# LangGraph Project

This directory is now the source-of-truth home for the homelab LangGraph
project and its repo-owned container wrapper.

It contains the LangGraph and Deep Agents implementation we have been
workshopping:

- `agent`: user-facing coordinator and the only supported entrypoint in the
  default Homelab runtime
- `code`: single-layer Code specialist for repository analysis, filesystem
  inspection, and implementation work
- `jira`: single-layer Jira specialist for discovery and issue lifecycle
  work
- `tech_lead`: single-layer Tech Lead specialist for technical review, code
  impact, workflow impact, and implementation guidance
- `github`: single-layer GitHub specialist for PRs, checks, reviews, and GitHub
  Actions API work (GitHub MCP + shared `mcp-rag`)

## Layout

```text
applications/langgraph/
├── agent/
│   ├── mcp.json
│   ├── agent.py
│   ├── langgraph.json
│   └── system_prompt.md
├── subagents/
│   ├── code/
│   ├── github/
│   ├── jira/
│   └── tech-lead/
├── docker/
│   ├── Dockerfile
│   ├── agent_server.sh
│   ├── chat.sh
│   └── .dockerignore
├── framework/
│   ├── agents/
│   │   ├── base.py
│   │   ├── code.py
│   │   ├── git.py
│   │   ├── jira.py
│   │   ├── supervisor.py
│   │   └── tech_lead.py
│   ├── __init__.py
│   ├── agent_factories.py
│   ├── configuration.py
│   ├── mcp_support.py
│   └── middleware/
│       └── workflow_gates.py
├── .dockerignore -> docker/.dockerignore
├── pyproject.toml
└── requirements.txt
```

Each deployable agent app has its own:

- `langgraph.json`
- `system_prompt.md`
- optional `mcp.json`
- agent-local skills

Reusable class-based builders live under `framework/agents/`. Concrete app and
subagent directories instantiate those classes and keep ownership of runtime
prompts, MCP config, skills, and graph exports. `framework/agent_factories.py`
remains as a thin compatibility layer around the shared builder classes.

Secrets and shared model defaults live only in the homelab root file
`.secrets/.env`. When someone says to edit the LangGraph `.env`, update that
exact file. Do not add `applications/langgraph/agent/.env` (or other per-app
dotenv files); if an old `agent/.env` is still on disk, move any variables into
`.secrets/.env` and remove it so nothing shadows the central file via the
process environment.

## Current Intent

The primary local development path is one LangGraph development server that
hosts the top-level `agent` graph from the Homelab agent boundary, paired with
a local LangChain Agent Chat dev server that proxies into that same local
backend.

What is already in place:

- a single-deployment `langgraph.json` in `agent/` that exposes only the
  top-level `agent` graph
- shared Python package for reusable helpers and class-based agent builders
- supervisor-local delegation to compiled specialist subagents in the same
  deployment
- a single-layer Code specialist with repo-scoped filesystem MCP tooling
- a single-layer Jira specialist that keeps create and edit rules in one app
- a single-layer Tech Lead specialist with repo-scoped filesystem MCP tooling
- Markdown-backed `system_prompt.md` files for deployable agents
- MCP loading support from agent-local **`mcp.json`** files (**supervisor** uses
  `agent/mcp.json` for homelab-wide **mcp-rag**; **every** specialist includes
  **`mcp-rag`** in **`subagents/<name>/mcp.json`**)
- Workflow middleware (**`framework/middleware/workflow_gates.py`**): supervisor
  requires **`rag_search`** before `task` to **`code`**, rejects **`general-purpose`**
  delegation, and the Code specialist requires read/search tools before
  **`write_file`** / **`edit_file`** / **`execute`** (disable with
  **`HOMELAB_DISABLE_WORKFLOW_GATES=1`** only for break-glass)
- a repo-owned Docker wrapper in `Dockerfile` that packages this project and
  runs `langgraph dev`

What is still expected before real deployment:

- keep `.secrets/.env` at the homelab repo root filled in for local runs, or use
  cluster secrets in Kubernetes instead of that file
- replace `.mcp.json.example`-style placeholders with real `mcp.json` configs
- install dependencies
- run `./docker/agent_server.sh` from `applications/langgraph/` for the default
  `agent` backend, and run `./docker/chat.sh` from the same directory for
  the paired LangChain Agent Chat local dev path, or run `langgraph dev` from an agent
  directory when you want a different agent boundary

## Model And API Key Defaults

The scaffold now defaults all LangGraph apps to `openai:gpt-5.4`.

Set `OPENAI_API_KEY` and related keys in `.secrets/.env` at the homelab repo root,
or inject them through your deployment environment (for example the
`langgraph-app-env` ExternalSecret in Kubernetes). Local `docker compose` and
`docker/agent_server.sh` both read that file. Direct `langgraph dev` runs load
the same file through `framework.configuration.merged_settings`, which also
exports missing keys into the process environment for provider SDKs.

## Runtime

The primary runtime path is now the Kubernetes `langgraph` deployment.
That workload builds this directory into an image and starts the server with
the Docker `CMD` from [`Dockerfile`](./Dockerfile):

- `langgraph dev --host 0.0.0.0 --port 2024 --no-browser --no-reload --n-jobs-per-worker 8`

The homelab hostname `https://langgraph.nodadyoushutup.com` is intended to
front that Kubernetes deployment. See [`docker/README.md`](./docker/README.md)
for build context and ignore-file notes.

The deployment serves:

- `agent`

The split specialist agent directories exist as the source of truth for their
local skills, MCP config, and prompt docs, but they are private local subagents
behind the supervisor in the default Homelab runtime. Specialist output always
returns to `agent`; specialists do not directly hand off to one another.

For quick local iteration, use [`docker/agent_server.sh`](./docker/agent_server.sh) for the
backend and [`docker/chat.sh`](./docker/chat.sh) for the frontend. They run independently in
the foreground so each terminal shows the live logs directly while you manage
restarts yourself. By default, `docker/agent_server.sh` starts the `agent`
boundary on `0.0.0.0:2124` with `8` jobs per worker, and `docker/chat.sh` starts
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
- `HOMELAB_SECRETS_ENV`: absolute path to the dotenv file to use instead of
  `<repo>/.secrets/.env` (same variable as ``framework.configuration``)

Compatibility note:
- `docker/agent_server.sh` still accepts the previous `LANGGRAPH_DEBUG_*` variables as
  fallbacks.

The container image uses the same `8` jobs-per-worker default through
`LANGGRAPH_N_JOBS_PER_WORKER`, so you can tune the deployed runtime without
rebuilding the image. The image is defined in [`docker/Dockerfile`](./docker/Dockerfile).

If you need a different agent boundary, run `langgraph dev` directly from that
agent directory instead of reusing the shared helper.

## Docker Dev Stack

For fast host-local development with bind-mounted source code, use the
top-level [`docker/`](./../../docker/README.md) directory. That stack is a
development-only exception to the normal app-boundary layout:

- `docker/docker-compose.yml` starts one LangGraph dev container plus one
  LangChain Agent Chat dev container
- local Docker images are built from this repo for the dev stack
- LangGraph code is mounted from the host `applications/langgraph` directory to
  `/app/langgraph` inside the container so restarts pick up live code
- the LangGraph code mount overrides the baked app path inside that container
- the LangGraph dev container otherwise uses the image's own default `WORKDIR`
  and `CMD`, so it stays close to the published runtime shape
- LangChain Agent Chat source is mounted from the host
  `applications/langchain-agent-chat` directory to `/app` inside the container
- LangChain Agent Chat runs `pnpm dev` from mounted source with `node_modules`
  kept in a Docker-managed volume and `.next` written on the host mount
- LangChain Agent Chat proxy traffic to LangGraph uses the Compose service DNS
  name plus the container port, currently `http://langgraph-dev:2024`

Use this when you want quick containerized restarts on your host machine. Do
not treat it as the source of truth for deployment packaging.

## Container And Publish Notes

Build context:

- `applications/langgraph/`

Dockerfile path:

- `applications/langgraph/docker/Dockerfile`

Published image:

- `harbor.nodadyoushutup.com/homelab/langgraph:<tag>`

The published image name now matches the deployable agent boundary and the
Kubernetes workload identity: `langgraph`.
