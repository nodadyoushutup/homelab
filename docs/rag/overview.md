# RAG stack overview

## What “RAG” means here

The repo maintains a **semantic index** of allowed paths: files are chunked, embedded through the configured provider (OpenAI by default; Google and Voyage-backed `anthropic` optional), and stored in **Chroma**. Queries embed the question text with the **same provider/model/dimensions** and run a vector search so results stay comparable to ingest.

Downstream clients (**`mcp-rag`**, LangGraph agents, Cursor, Codex, or direct HTTP) should treat **`rag-engine`** as the retrieval API, not a raw Chroma client with ad hoc settings—otherwise embeddings and collection choice can drift from what ingest used.

## Main components

| Piece | Role |
| --- | --- |
| **`chromadb` (Swarm)** | Vector database; deployed with **`terraform/swarm/chromadb/app`** as a Swarm service with a named Docker volume (**`chromadb-data`**, fixed in **`main.tf`**, mounted at `/data` in the container). Not defined in the repo’s root Compose file. |
| **`rag-engine`** | HTTP service: ingest jobs, `POST /v1/query`, memory HTTP endpoints. Owns chunking, embedding calls, and writes to Chroma. Code: `applications/rag-engine/`. |
| **`mcp-rag`** | Thin MCP server: `rag_search` and memory tools forward to `rag-engine` over HTTP. Code: `applications/mcp-rag/`. |
| **Git hooks / backfill** | Trigger or batch embed paths under configured prefixes (aligned with `RAG_ALLOWED_PATH_PREFIXES` / `RAG_HOOK_INCLUDE_PREFIXES`). |

## Typical flows

**Ingest (index update):** eligible file changes → `rag-engine` pipeline (`ingest/pipeline.py`) → chunk strategies (`chunks/structured.py`, sibling modules under `chunks/`) → provider dispatcher (`embeddings/providers.py`) → vectors + metadata → Chroma collection (default name **`homelab`**, overridable via `RAG_CHROMA_COLLECTION`).

**Query:** client → `POST /v1/query` on `rag-engine` (or `rag_search` via `mcp-rag`) → embed query text → Chroma query with optional `where` metadata filter → ranked chunks returned to the client.

**Long-term memory (separate collections):** `mcp-rag` memory tools call `rag-engine` memory routes; vectors live in dedicated Chroma collections (`memories_episodic`, `memories_declarative` by default). Storage reuses the same embedding stack as repo RAG. **Promotion gates and agent responsibilities** are documented in [rag-agent-mcp-integration-roadmap.md](../workflows/rag-agent-mcp-integration-roadmap.md).

## Related reading

- Corpus and hooks: [corpus-and-ingest.md](corpus-and-ingest.md)
- Embeddings and collections: [embeddings-and-storage.md](embeddings-and-storage.md)
- Running services and env: [operators-and-clients.md](operators-and-clients.md)
