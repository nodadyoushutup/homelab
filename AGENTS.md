# AGENTS

This repo is docs-driven. Use this file as the directory to the source-of-truth
docs to check before doing substantive work.

## Where To Look

- `docs/workflows/`: execution workflows
- `docs/workflows/edge-dns-and-nginx-proxy.md`: new public hostnames → Cloudflare tfvars + Nginx Proxy Manager tfvars (Swarm edge) vs cluster ingress
- `docs/workflows/docker-build-github-actions.md`: Docker image publishes via GHA (dispatch, semver, Terraform/Argo CD/Swarm rollout, live health, CI)
- `docs/workflows/mcp-code-worktrees-and-multi-agent.md`: mcp-code single-root model, Git worktrees, and isolating concurrent agents (one MCP backend per worktree)
- `docs/resources/README.md`: curated technology reference shelf
- `docs/workflows/langgraph.md`: LangGraph implementation workflow
- `docs/workflows/agents.md`: LangGraph runtime index (prompt map, routing, update workflow)
- `applications/langgraph/agent/system_prompt.md`: top-level supervisor (`agent` graph) instruction contract
- `docs/subagents/*/*.md`: per-specialist **deployment overlays** (loaded by each subagent app)

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
  `http://localhost:3000` (baked **`runner`** image—rebuild that service after chat UI changes),
  with the chat proxy targeting
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
  `<repo>/.secrets/.env` (same file holds `CONFIG_DIR`, Argo CD installer vars, MinIO
  compose keys, and Compose interpolation keys documented in `.secrets/.env.example`). When asked to
  edit the LangGraph `.env`, literally update that file. Do not create or use `.env`
  files inside `applications/langgraph/agent/`, `applications/langgraph/subagents/`,
  or other LangGraph app directories for now.
- If a stable pattern changes, update the corresponding docs as part of the
  task.
- Do not use a repo-wide workflow that requires choosing or locking a local
  agent before starting work. Agent-specific behavior lives in
  `applications/langgraph/` (supervisor + framework prompts) and deployment
  overlays under `docs/subagents/`, with `docs/workflows/agents.md` as the index.
- Do not reference removed legacy wiki paths until replacement docs exist in
  `docs/`.
- For this workspace, repo filesystem / ast-grep / local-git MCP access is
  **`mcp-code`** (`https://mcp.code.nodadyoushutup.com/mcp`) once it is available
  in project config. Use direct shell or local file-edit access only to bootstrap,
  repair, or validate that MCP path.
- Repo RAG MCP URL is `https://mcp.rag.nodadyoushutup.com/mcp`. Cursor project
  `.cursor/mcp.json` includes the URL; set `x-api-key` matching `MCP_RAG_API_KEY`
  via User-level Cursor MCP/`~/.cursor/mcp.json` when the Swarm service enforces auth.
  LangGraph fills the header from `.secrets/.env`; Codex uses `env_http_headers` in `.codex/config.toml`.
- LangGraph Homelab runtime enforces **docs `rag_search` before every specialist delegation**, a second **code-location `rag_search` before `code` and `tech_lead` delegation**, and **read/search before writes** on the Code specialist; see `docs/workflows/rag-agent-mcp-integration-roadmap.md`. Break-glass: **`HOMELAB_DISABLE_WORKFLOW_GATES=1`** on the agent process only.
