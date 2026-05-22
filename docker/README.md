# Docker Dev Stack

This directory contains a host-local Docker Compose workflow for fast
development of:

- the Docker dev LangGraph `langgraph-dev` runtime
- the Docker dev LangGraph Postgres `langgraph-postgres` database
- the Docker dev LangChain Agent Chat `langchain-agent-chat-dev` frontend

The stack is intentionally development-only:

- each service declares an explicit local `build` context and Dockerfile plus a
  local `image` tag, so `docker compose build` produces reusable local images
  from this repo
- LangGraph source is bind-mounted from `applications/langgraph` on the host to
  `/app/langgraph` in the container, matching the published image layout
- the LangGraph bind mount overrides the baked application files inside that
  container
- LangChain Agent Chat source is bind-mounted from
  `applications/langchain-agent-chat` on the host to `/app` in the container
- the chat service runs `pnpm dev` from the mounted source tree and stores
  `node_modules` in a Docker-managed volume while `.next` remains on the host
  mount so the dev server can write generated files on NFS-backed storage
- the LangChain Agent Chat frontend proxies to LangGraph over the Compose
  network using
  `http://langgraph-dev:2024`
- LangGraph backend state is stored in the Compose-managed Postgres database
  using `POSTGRES_URI` from `<repo>/.config/docker/*.env`
- this dev pair is separate from the Kubernetes production pair; do not point
  Docker dev chat at production LangGraph, and do not point production chat at
  Docker dev LangGraph
- restart the affected service after source or environment changes; rebuild the
  LangChain Agent Chat service when dependencies or Docker build layers change

The `langgraph-dev` service intentionally uses the image's built-in `WORKDIR`
and `CMD`. Its LangGraph-specific wiring is the bind mount onto
`/app/langgraph`, the separate state volume for
`/app/langgraph/agent/.langgraph_api`, the custom LangGraph API checkpointer in
`agent/langgraph.json`, and `env_file: ../.config/docker/*.env` so API keys, model
overrides, and database settings match local host development. The checkpointer
uses `POSTGRES_URI` to store graph checkpoints in `langgraph-postgres`. Create
or edit `<repo>/.config/docker/*.env` at the homelab repo root; do not use a LangGraph
app-local `.env` file.

The `langchain-agent-chat-dev` service runs a Next.js dev server against the
bind-mounted source tree. Source edits are picked up from the host; restart the
service for environment changes and rebuild when dependency manifests change.

Local image tags:

- `homelab/langgraph:latest`
- `homelab/langchain-agent-chat:latest`

## Usage

Use **`docker-compose.yml`** only. A second file named `docker-compose.yaml` in
this directory makes Compose warn and pick one arbitrarily; remove duplicates or
symlinks.

From this directory:

```bash
docker compose up --build
```

Or in detached mode:

```bash
docker compose up -d --build
```

Default endpoints:

- LangGraph: `http://localhost:2124`
- LangChain Agent Chat: `http://localhost:3000`
- LangGraph Postgres: Compose-internal `langgraph-postgres:5432`

Secrets live in [`../.config/docker/*.env`](./../.config/docker/*.env).

For now, non-secret dev defaults such as ports and public local URLs are
hardcoded directly in `docker-compose.yml`. **`rag-engine-dev`** sets
**`RAG_CHROMA_HOSTNAME`** to **`192.168.1.120:8000`** by default (Swarm Chroma per
`terraform/swarm/chromadb`); override with **`HOMELAB_DEV_CHROMA_HOSTNAME`** in the
shell when invoking Compose if your LAN differs.

The browser-facing `NEXT_PUBLIC_API_URL` and the internal proxy
`LANGGRAPH_API_URL` serve different purposes:

- `NEXT_PUBLIC_API_URL` should be the URL your browser can reach, such as
  `http://localhost:3000/api` or a LAN URL for this same dev chat service
- `LANGGRAPH_API_URL` should be the upstream LangGraph service URL inside the
  Compose network, currently `http://langgraph-dev:2024`
