# mcp-rag

Index of MCP docs in this folder: [README.md](README.md).

**mcp-rag** is the Streamable HTTP MCP in front of the RAG engine: semantic search over indexed repo code and docs, plus optional long-term memory tools, depending on build and configuration.

## URL and path

Point MCP clients at the HTTPS (or local HTTP) URL where your deployment exposes the server. Stacks in this repo terminate Streamable MCP on path **`/mcp`** on the upstream process; your reverse proxy should forward that path unchanged unless you intentionally remap it.

When **`MCP_RAG_API_KEY`** is set on the **mcp-rag** container, clients must send header **`x-api-key`** with the same value. If that env is unset, **`/mcp`** may accept unauthenticated requests (avoid on shared networks).

## LangGraph agents (this repo)

`applications/langgraph/agent/mcp.json` and **`applications/langgraph/subagents/*/mcp.json`** register **mcp-rag** with **`x_api_key_from_env": "MCP_RAG_API_KEY"`** where used. **`framework.agents`** call **`merged_settings()`** before building tools, so set **`MCP_RAG_API_KEY=…`** next to **`OPENAI_API_KEY`** in repo **`.config/docker/mcp.env`** when required (see **`.config/docker/mcp.env.example`**). Override the base URL with **`HOMELAB_MCP_RAG_URL`** when pointing agents at a different endpoint (for example Compose **mcp-rag-dev**).

Retrieval-first and read-before-write rules are enforced in code for the supervisor and Code specialist. See [rag-agent-mcp-integration-roadmap.md](../workflows/rag-agent-mcp-integration-roadmap.md).

## OpenAI Codex (`.codex/config.toml`)

`[mcp_servers.mcp_rag]` can use **`env_http_headers`** so Codex reads **`MCP_RAG_API_KEY`** from the Codex process environment. **`[shell_environment_policy] inherit`** helps when the IDE inherits a shell that exported the variable.

## Cursor

Project **`.cursor/mcp.json`** lists **`mcp_rag.url`** only (no secrets in git). Cursor does not reliably expand env vars inside MCP **`headers`** in JSON. If the server requires a key, add header **`x-api-key`** with the same value as **`MCP_RAG_API_KEY`** in **`.config/docker/mcp.env`** via **Cursor Settings → MCP** for the project **`mcp_rag`** server, or omit **`MCP_RAG_API_KEY`** on the server only in trusted, isolated environments.

## Deploy

- Application: **`applications/mcp-rag/README.md`**
- Swarm Terraform: **`terraform/swarm/mcp-rag/app/`**
