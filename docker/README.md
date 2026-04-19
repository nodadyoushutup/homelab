# Docker Dev Stack

This directory contains a host-local Docker Compose workflow for fast
development of:

- the LangGraph `controller-agent` runtime
- the LangChain Agent Chat frontend

The stack is intentionally development-only:

- each service declares an explicit local `build` context and Dockerfile plus a
  local `image` tag, so `docker compose build` produces reusable local images
  from this repo
- LangGraph source is bind-mounted from `applications/langgraph` on the host to
  `/app/langgraph` in the container, matching the published image layout
- the LangGraph bind mount overrides the baked application files inside that
  container
- the chat UI image is built from `applications/langchain-agent-chat` in this
  repo and serves the compiled Next.js app from the image
- changing chat UI `NEXT_PUBLIC_*` values requires rebuilding `chat-ui-dev`
- the chat UI proxies to LangGraph over the Compose network using
  `http://langgraph-dev:2024`
- restart the affected service after code or dependency changes, and rebuild
  the chat UI service when the public browser URL changes

The `langgraph-dev` service intentionally uses the image's built-in `WORKDIR`
and `CMD`. The only LangGraph-specific overrides are the bind mount onto
`/app/langgraph` and the separate state volume for
`/app/langgraph/apps/controller-agent/.langgraph_api`.

The `chat-ui-dev` service keeps the image config minimal, but its public client
config is baked at build time because it is a Next.js production build.

Local image tags:

- `homelab/controller-agent:latest`
- `homelab/langchain-agent-chat:latest`

## Usage

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
- Chat UI: `http://localhost:3000`

Secrets live in [`./.env`](./.env).

For now, non-secret dev defaults such as ports and public local URLs are
hardcoded directly in `docker-compose.yml`.

The browser-facing `NEXT_PUBLIC_API_URL` and the internal proxy
`LANGGRAPH_API_URL` serve different purposes:

- `NEXT_PUBLIC_API_URL` should be the URL your browser can reach, such as
  `http://192.168.1.36:3000/api`
- `LANGGRAPH_API_URL` should be the upstream LangGraph service URL inside the
  Compose network, currently `http://langgraph-dev:2024`
