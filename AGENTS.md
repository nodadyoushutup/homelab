# AGENTS

This repo is docs-driven. Use this file as the directory to the source-of-truth
docs to check before doing substantive work.

## Where To Look

- `docs/workflows/`: execution workflows
- `docs/resources/README.md`: curated technology reference shelf
- `docs/workflows/langgraph.md`: LangGraph implementation workflow
- `docs/agents/README.md`: LangGraph runtime contract index
- `docs/agents/homelab-agent/homelab-agent.md` and `docs/subagents/*/*.md`:
  LangGraph runtime instruction and I/O contracts for deployed agents

## Repo Notes

- **Repository path namespaces:** On the host, this workspace is
  `/mnt/eapp/code/homelab`. In Docker dev (`docker/docker-compose.yml`),
  LangGraph sets `HOMELAB_REPO_ROOT=/app` and bind-mounts the same tree under
  `/app/...`. Remote filesystem MCP and `list_allowed_directories` may report
  `/app` (or children) while Cursor and local shell use the host path. That is
  expected: same repo, different mount namespace—do not spend cycles
  reconciling it as a misconfiguration.
- Treat `docs/` as the source of truth for repeatable repo guidance and
  workflows.
- LangGraph plus LangChain Agent Chat have two separate runtime pairs. For all
  local debugging, code work, and quick compose up/down validation, use the
  Docker dev pair only: `docker/docker-compose.yml` runs `langgraph-dev` at
  `http://localhost:2124` and `langchain-agent-chat-dev` at
  `http://localhost:3000`, with the chat proxy targeting
  `http://langgraph-dev:2024` on the Compose network.   The same file can also run **`rag-engine-dev`** and **`mcp-rag-dev`**
  (bind-mounted source, host ports **9015** / **9016**) for fast RAG iteration;
  **`langgraph-dev`** sets **`HOMELAB_MCP_RAG_URL`** so in-container agents use
  that MCP. **Chroma stays on Swarm**; **`rag-engine-dev`** defaults Chroma to
  **`192.168.1.120:8000`** via Compose (overriding **`chromadb`** in
  **`.secrets/.env`**). Adjust with **`HOMELAB_DEV_CHROMA_HOST`** /
  **`HOMELAB_DEV_CHROMA_PORT`** if needed. Swarm RAG deploys are unchanged. The Kubernetes pair is
  production only: `kubernetes/langgraph` and `kubernetes/langchain-agent-chat`.
  Do not point Docker dev chat at Kubernetes/prod LangGraph, and do not point
  Kubernetes/prod chat at Docker dev LangGraph.
- For LangGraph secrets and config, the single local dotenv source of truth is
  `<repo>/.secrets/.env`. When asked to edit the LangGraph `.env`, literally
  update that file. Do not create or use `.env` files inside
  `applications/langgraph/agent/`, subagent directories, or other LangGraph app
  directories for now.
- If a stable pattern changes, update the corresponding docs as part of the
  task.
- Do not use a repo-wide workflow that requires choosing or locking a local
  agent before starting work. Agent-specific behavior lives in the LangGraph
  runtime contracts under `docs/agents/` and `applications/langgraph/`.
- Do not reference removed legacy wiki paths until replacement docs exist in
  `docs/`.
- For this workspace, filesystem interaction should go through the
  `mcp_filesystem` MCP server once it is available in project config.
  Use direct shell or local file-edit access only to bootstrap, repair, or
  validate that MCP path.
- Repo RAG MCP URL is `https://mcp.rag.nodadyoushutup.com/mcp`. Cursor project
  `.cursor/mcp.json` includes the URL; set `x-api-key` matching `MCP_RAG_API_KEY`
  via User-level Cursor MCP/`~/.cursor/mcp.json` when the Swarm service enforces auth.
  LangGraph fills the header from `.secrets/.env`; Codex uses `env_http_headers` in `.codex/config.toml`.
- LangGraph Homelab runtime enforces **`rag_search` before `code` delegation** and **read/search before writes** on the Code specialist; see `docs/workflows/development/rag-agent-mcp-integration-roadmap.md`. Break-glass: **`HOMELAB_DISABLE_WORKFLOW_GATES=1`** on the agent process only.
