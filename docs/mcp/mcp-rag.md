# mcp-rag

Index of MCP docs in this folder: [README.md](README.md).

**mcp-rag** is the Streamable HTTP MCP in front of the RAG engine: semantic search over indexed repo code and docs, plus optional long-term memory tools, depending on build and configuration.

## URL and path

Publish the service behind TLS at **`https://mcp.rag.nodadyoushutup.com/mcp`** (or your hostname). The container listens on **8080**; Swarm publishes **9016** → **8080**.

When **`MCP_RAG_API_KEY`** is set on the **mcp-rag** container, clients must send header **`x-api-key`** with the same value. If that env is unset, **`/mcp`** may accept unauthenticated requests (avoid on shared networks).

## LangGraph agents (this repo)

`applications/langgraph/agent/mcp.json` and **`applications/langgraph/subagents/*/mcp.json`** register **mcp-rag** with **`x_api_key_from_env": "MCP_RAG_API_KEY"`** where used. **`framework.agents`** call **`merged_settings()`** before building tools, so set **`MCP_RAG_API_KEY=…`** next to **`OPENAI_API_KEY`** in repo **`.config/docker/mcp.env`** when required (see **`.config/docker/mcp.env.example`**). Override the base URL with **`HOMELAB_MCP_RAG_URL`** when pointing agents at a different endpoint (for example Compose **mcp-rag-dev**).

Retrieval-first and read-before-write rules are enforced in code for the supervisor and Code specialist. See [rag-agent-mcp-integration-roadmap.md](../workflows/rag-agent-mcp-integration-roadmap.md).

## OpenAI Codex (`.codex/config.toml`)

`[mcp_servers.mcp_rag]` can use **`env_http_headers`** so Codex reads **`MCP_RAG_API_KEY`** from the Codex process environment. **`[shell_environment_policy] inherit`** helps when the IDE inherits a shell that exported the variable.

## Cursor

Project **`.cursor/mcp.json`** registers **`mcp_rag`** at **`https://mcp.rag.nodadyoushutup.com/mcp`** (Streamable HTTP — same path as LangGraph **`mcp.json`**). When Swarm sets **`MCP_RAG_API_KEY`**, the checked-in config sends **`x-api-key`** via **`${env:MCP_RAG_API_KEY}`** (no secret in git).

Export the key from **`.config/docker/mcp.env`** into the environment Cursor inherits (for example `set -a && source .config/docker/mcp.env && set +a` in the shell before launching Cursor, or your desktop/session env). After deploy or config edits, **reload MCP** in Cursor Settings if tools stay disconnected. If interpolation fails on your build, add header **`x-api-key`** manually under **Cursor Settings → MCP** for **`mcp_rag`**.

Native tool calling exposes **`rag_search`**, **`memory_recall`**, **`memory_save`**, and **`memory_forget`** once the server connects. **`rag_search`** accepts **`query`**, optional **`where`**, optional **`path_prefix`** (repo directory scope), and optional **`k`** (per-request hit count capped by **`RAG_QUERY_K_MAX`** on **rag-engine**). Default breadth remains **`RAG_TOP_K`** (default **20**).

## Swarm

- Stack: **`terraform/swarm/mcp-rag/app/`** — all site credentials in the **`env`** map on **`.config/terraform/swarm/mcp-rag/app.tfvars`** (flat keys such as **`RAG_ENGINE_BASE_URL`**, **`RAG_ENGINE_API_KEY`**, **`MCP_RAG_API_KEY`**; no Vault **`secrets`** block or **`env_file_path`**). Keep keys out of git.
- Image tag and ingress port **9016** are pinned in **`terraform/swarm/mcp-rag/app/main.tf`**. Bump the tag after publish, then re-apply.
- The service joins the existing **`rag-engine`** overlay network (created by the **rag-engine** stack) so it can reach **`http://rag-engine:8080`**.

## Deploy

- Application: **`applications/mcp-rag/README.md`**
- RAG stack operators: [operators-and-clients.md](../rag/operators-and-clients.md)
