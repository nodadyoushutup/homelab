# mcp-rag

Thin MCP server: **one tool** (`rag_search`) that POSTs to `rag-worker` `/v1/query` so agents use the same Gemini embeddings as ingest.

## Environment

| Variable | Purpose |
| -------- | ------- |
| `RAG_WORKER_BASE_URL` | Base URL of rag-worker (no trailing slash), e.g. `http://rag-worker:8080` in Compose or `http://127.0.0.1:9015` from the host. |
| `RAG_WORKER_API_KEY` | Optional; sent as `x-api-key` to the worker if non-empty (must match worker). |
| `MCP_RAG_API_KEY` | Optional; if set, required on MCP Streamable HTTP (`x-api-key`) for `/mcp`. |
| `HOST` / `PORT` | Bind address (default `0.0.0.0:8080`). |
| `LOG_LEVEL` | Uvicorn / logging level. |
| `MCP_RAG_WORKER_TIMEOUT_SEC` | Worker POST timeout (default `120`). |

See [docs/mcp/rag.md](../../../docs/mcp/rag.md) for Cursor wiring and troubleshooting.

## Run locally

```bash
export RAG_WORKER_BASE_URL=http://127.0.0.1:9015
export RAG_WORKER_API_KEY=your-key
python applications/mcp-rag/src/core/server.py serve
```

Healthcheck: `python applications/mcp-rag/src/core/server.py healthcheck`
