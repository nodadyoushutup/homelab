# Operators and clients

## Compose services

Typical local stack:

```bash
sudo docker compose -f docker/docker-compose.yaml --env-file .secrets/.env up -d chromadb rag-engine
```

Add **`mcp-rag`** when a Cursor (or other) MCP client should call **`rag_search`** / memory tools:

```bash
sudo docker compose -f docker/docker-compose.yaml --env-file .secrets/.env up -d mcp-rag
```

Published ports (host defaults in this repo): **`chromadb` → 8010** (mapped to the server HTTP port inside the container), **`rag-engine` → 9015**, **`mcp-rag` → 9016**. Exact mapping lives in `docker/docker-compose.yaml`.

## Environment variables

All values belong in **`.secrets/.env`** with matching keys documented in **`.secrets/.env.example`** (no Compose-time `${VAR:-default}` pattern in `docker/docker-compose.yaml`).

**Worker / Chroma / embed:** `RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`, `RAG_CHROMA_COLLECTION`, `RAG_EMBEDDING_MODEL`, `RAG_ENGINE_API_KEY`, memory collection names, memory TTL and scoring tunables (`RAG_MEMORY_*` — see `.secrets/.env.example` and `docker/docker-compose.yaml` `rag-engine` service).

**Ingest scope:** `RAG_ALLOWED_PATH_PREFIXES`, and hook alignment `RAG_HOOK_INCLUDE_PREFIXES`.

**MCP (`mcp-rag`):** `RAG_ENGINE_BASE_URL`, `RAG_ENGINE_API_KEY`, `MCP_RAG_API_KEY`, `MCP_RAG_LOG_LEVEL`, `MCP_RAG_ENGINE_TIMEOUT_SEC`.

**Google ADK container** (when using the bundled agent): variables such as `MCP_RAG_URL`, `MCP_RAG_PROXY_API_KEY`, optional `MCP_RAG_TOOLS` — see Compose and `.secrets/.env.example`.

## Cursor and other MCP clients

Step-by-step MCP config, authentication headers, and troubleshooting table:

- [docs/mcp/rag.md](../mcp/rag.md)

## Direct HTTP (debugging)

`rag-engine` exposes JSON endpoints (e.g. `POST /v1/query`) for parity checks without MCP. Use the same API key rules as production (`x-api-key` when `RAG_ENGINE_API_KEY` is set).

## Application-level doc

Short pointer to the worker package layout:

- [docs/applications/rag-engine.md](../applications/rag-engine.md)
