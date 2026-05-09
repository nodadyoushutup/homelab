# RAG MCP client wiring

Production Streamable MCP URL (**HTTPS**, Nginx Proxy Manager): **`https://mcp.rag.nodadyoushutup.com/mcp`**

When **`MCP_RAG_API_KEY`** is set on the **`mcp-rag`** container, clients must send header **`x-api-key`** with the same value. If that env is unset, `/mcp` accepts unauthenticated requests (not recommended on shared networks).

## LangGraph agents (this repo)

`applications/langgraph/agent/subagents/*/mcp.json` includes an **`mcp-rag`** server with **`x_api_key_from_env": "MCP_RAG_API_KEY"`**. **`framework.agents`** call **`merged_settings()`** before building tools, so add **`MCP_RAG_API_KEY=…`** next to **`OPENAI_API_KEY`** in repo **`.secrets/.env`** (see **`.secrets/.env.example`**).

## OpenAI Codex (`.codex/config.toml`)

`[mcp_servers.mcp_rag]` uses **`env_http_headers`** so Codex reads **`MCP_RAG_API_KEY`** from the Codex process environment (shell profile or IDE env). **`[shell_environment_policy] inherit`** in your Codex config helps when the IDE inherits a shell that exported the variable.

## Cursor

Project **`.cursor/mcp.json`** lists **`mcp_rag.url`** only. Cursor does not reliably expand env vars inside MCP **`headers`** in JSON. If your Swarm service requires a key, add the same **`x-api-key`** in **User** MCP settings or **`~/.cursor/mcp.json`**, or run without **`MCP_RAG_API_KEY`** on the server (LAN-only labs).
