# Embeddings and storage

## Embedding provider and model

- Provider selector: **`RAG_EMBEDDING_PROVIDER`** supports **`google`** (default) and **`openai`**.
- Default model id: **`RAG_EMBEDDING_MODEL`**. When unset/empty, Google uses **`gemini-embedding-001`** and OpenAI uses **`text-embedding-3-small`**.
- Provider dispatch lives in **`applications/rag-engine/src/rag_engine/embeddings.py`**. Google-specific calls live in **`embed_google.py`**; OpenAI-specific calls live in **`embed_openai.py`**.
- OpenAI optional dimensions override: **`RAG_OPENAI_EMBEDDING_DIMENSIONS`**. This is only sent for `text-embedding-3*` models.

**Query path:** `run_query` in `query.py` embeds the user query with `embed_batch` using the configured provider/model/dimensions, then calls Chroma with `query_embeddings`. Mismatched providers, models, or dimensions between ingest and query produce unreliable retrieval or Chroma dimension errors; hence the “always go through `rag-engine`” rule.

When switching provider/model/dimensions, use a new Chroma collection (for example `homelab_openai`) or rebuild the existing collection. OpenAI's current embedding docs list `text-embedding-3-small` and `text-embedding-3-large`, with default dimensions 1536 and 3072 respectively.

## Chroma

- Client: **HTTP** to Chroma (`RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`). In the Swarm layout, point the engine at the Chroma service hostname/IP and the published HTTP port (Terraform default **8000** on the Swarm host; see **`terraform/swarm/chromadb/app`**).
- **Distance:** collections are created with **`hnsw:space` = `cosine`** (see `pipeline.py` `_collection()` and `memory.py` `_open_collection`).

## Collections (defaults)

| Collection env | Default name | Contents |
| --- | --- | --- |
| `RAG_CHROMA_COLLECTION` | `homelab` | Repo corpus chunks (code, docs, PDFs, etc.) |
| `RAG_MEMORY_EPISODIC_COLLECTION` | `memories_episodic` | Episodic memories (engine memory API) |
| `RAG_MEMORY_DECLARATIVE_COLLECTION` | `memories_declarative` | Declarative memories (engine memory API) |

Repo RAG and memory share the **same embedding stack**; they differ by **collection** and **document/metadata schema**.

## Chunk metadata

Each stored chunk carries metadata used for filtering (`where` in query) and debugging: path, chunk index, embedding provider, embedding model id, optional embedding dimensions override, content hash, chunk strategy (`ast_py`, `pdf_hybrid`, …), optional git last-touch fields, and structured extras (e.g. `xml_model` for Odoo XML).

The authoritative table of keys for Chroma filters is maintained in the integration roadmap (agent tooling doc) because it doubles as the contract for `where` filters:

- [rag-agent-mcp-integration-roadmap.md § Indexed metadata keys](../workflows/development/rag-agent-mcp-integration-roadmap.md#indexed-metadata-keys-for-chroma-where-filters)

**Naming pitfall:** metadata key **`model`** is the **embedding model id**, not an Odoo `ir.model`. For Odoo XML, prefer **`xml_model`** when filtering.

## Code map

| Concern | Location |
| --- | --- |
| Collection handles | `pipeline.py` (`chroma_repo_collection`), `memory.py` |
| Ingest / embed jobs | `pipeline.py` (`run_embed_job`, path allowlists) |
| Provider dispatch | `embeddings.py` |
| Query embedding + Chroma | `query.py` |
| HTTP API | `server.py` (`rag_query`, `embed_commit`, memory routes) |
