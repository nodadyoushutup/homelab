# Embeddings and storage

## Embedding model

- Default embedding model id: **`RAG_EMBEDDING_MODEL`**, falling back to **`gemini-embedding-001`** (see `applications/rag-engine/src/rag_engine/server.py` for query defaults and `memory.py` for memory paths).
- Client code uses **`google.genai`** and shared helpers in **`applications/rag-engine/src/rag_engine/embed_google.py`** (`build_genai_client`, `embed_batch`).

**Query path:** `run_query` in `query.py` embeds the user query with `embed_batch` using the same model name, then calls Chroma with `query_embeddings`. Mismatched models between ingest and query produce unreliable retrieval—hence the “always go through `rag-engine`” rule.

## Chroma

- Client: **HTTP** to the `chromadb` service (`RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`; defaults suit Compose service name `chromadb` and port `8000`).
- **Distance:** collections are created with **`hnsw:space` = `cosine`** (see `pipeline.py` `_collection()` and `memory.py` `_open_collection`).

## Collections (defaults)

| Collection env | Default name | Contents |
| --- | --- | --- |
| `RAG_CHROMA_COLLECTION` | `repo_rag` | Repo corpus chunks (code, docs, PDFs, etc.) |
| `RAG_MEMORY_EPISODIC_COLLECTION` | `memories_episodic` | Episodic memories (worker memory API) |
| `RAG_MEMORY_DECLARATIVE_COLLECTION` | `memories_declarative` | Declarative memories (worker memory API) |

Repo RAG and memory share the **same embedding stack**; they differ by **collection** and **document/metadata schema**.

## Chunk metadata

Each stored chunk carries metadata used for filtering (`where` in query) and debugging: path, chunk index, embedding model id, content hash, chunk strategy (`ast_py`, `pdf_hybrid`, …), optional git last-touch fields, and structured extras (e.g. `xml_model` for Odoo XML).

The authoritative table of keys for Chroma filters is maintained in the integration roadmap (agent tooling doc) because it doubles as the contract for `where` filters:

- [rag-agent-mcp-integration-roadmap.md § Indexed metadata keys](../workflows/development/rag-agent-mcp-integration-roadmap.md#indexed-metadata-keys-for-chroma-where-filters)

**Naming pitfall:** metadata key **`model`** is the **embedding model id**, not an Odoo `ir.model`. For Odoo XML, prefer **`xml_model`** when filtering.

## Code map

| Concern | Location |
| --- | --- |
| Collection handles | `pipeline.py` (`chroma_repo_collection`), `memory.py` |
| Ingest / embed jobs | `pipeline.py` (`run_embed_job`, path allowlists) |
| Query embedding + Chroma | `query.py` |
| HTTP API | `server.py` (`rag_query`, `embed_commit`, memory routes) |
