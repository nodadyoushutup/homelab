# mcp-rag

Thin MCP server: forwards **`rag_search`** (corpus query) and **memory** tools to `rag-engine` over HTTP so clients use the same embedding provider/model as ingest. Default hit count is **`RAG_TOP_K`** on **rag-engine**; optional per-request **`k`** is capped by **`RAG_QUERY_K_MAX`**. See [operators-and-clients.md](../../../docs/rag/operators-and-clients.md).

## Environment

| Variable | Purpose |
| -------- | ------- |
| `RAG_ENGINE_BASE_URL` | Base URL of rag-engine (no trailing slash), e.g. `http://rag-engine:8080` in Compose or `http://127.0.0.1:9015` from the host. |
| `RAG_ENGINE_API_KEY` | Optional; sent as `x-api-key` to the engine if non-empty (must match engine). |
| `MCP_RAG_API_KEY` | Optional; if set, required on MCP Streamable HTTP (`x-api-key`) for `/mcp`. |
| `HOST` / `PORT` | Bind address (default `0.0.0.0:8080`). |
| `LOG_LEVEL` | Uvicorn / logging level. |
| `MCP_RAG_ENGINE_TIMEOUT_SEC` | Engine POST timeout (default `120`). |

See [docs/mcp/mcp-rag.md](../../../docs/mcp/mcp-rag.md) for Cursor wiring and troubleshooting.

## Run locally

```bash
export RAG_ENGINE_BASE_URL=http://127.0.0.1:9015
export RAG_ENGINE_API_KEY=your-key
python applications/mcp-rag/src/core/server.py serve
```

Healthcheck: `python applications/mcp-rag/src/core/server.py healthcheck`
