# Embeddings and storage

## Embedding provider and model

- Provider selector: **`RAG_EMBEDDING_PROVIDER`** supports **`google`** (default), **`openai`**, and **`anthropic`**.
- Default model id: **`RAG_EMBEDDING_MODEL`**. When unset/empty, Google uses **`gemini-embedding-001`**, OpenAI uses **`text-embedding-3-small`**, and **`anthropic`** uses **`voyage-3.5`** (Voyage AI — see below).
- Provider dispatch lives in **`applications/rag-engine/src/embeddings/providers.py`**. Google-specific calls live in **`embeddings/google_genai.py`**; OpenAI-specific calls live in **`embeddings/openai_client.py`**; **`anthropic`** is implemented in **`embeddings/anthropic_client.py`**.
- OpenAI optional dimensions override: **`RAG_OPENAI_EMBEDDING_DIMENSIONS`**. This is only sent for `text-embedding-3*` models.
- **Anthropic provider:** Anthropic does not publish first-party embedding vectors on `api.anthropic.com`; Claude’s RAG docs use **Voyage** embedding models. With **`RAG_EMBEDDING_PROVIDER=anthropic`**, the engine calls **`https://api.voyageai.com/v1/embeddings`** using **`VOYAGE_API_KEY`** (`Authorization: Bearer`). Optional: **`RAG_VOYAGE_BASE_URL`**, **`RAG_ANTHROPIC_EMBEDDING_DIMENSIONS`** (maps to Voyage `output_dimension` for supported models), **`RAG_ANTHROPIC_EMBED_BATCH_SIZE`**, **`RAG_ANTHROPIC_TIMEOUT_SEC`**. Indexing passes `input_type=document` and query paths pass `input_type=query` for retrieval-tuned behavior.

**Query path:** `run_query` in `retrieve/query.py` embeds the user query with `embed_batch` using the configured provider/model/dimensions, then calls Chroma with `query_embeddings`. Mismatched providers, models, or dimensions between ingest and query produce unreliable retrieval or Chroma dimension errors; hence the “always go through `rag-engine`” rule.

When switching provider/model/dimensions, use a new Chroma collection (for example `homelab_openai`) or rebuild the existing collection. OpenAI's current embedding docs list `text-embedding-3-small` and `text-embedding-3-large`, with default dimensions 1536 and 3072 respectively. Voyage model dimensions depend on the model and optional **`RAG_ANTHROPIC_EMBEDDING_DIMENSIONS`**; see [Voyage embeddings](https://docs.voyageai.com/docs/embeddings).

## Chroma

- Client: **HTTP** to Chroma (`RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`). In the Swarm layout, point the engine at the Chroma service hostname/IP and the published HTTP port (**8000** on the Swarm host; see **`terraform/swarm/chromadb/app/main.tf`**).
- **Distance:** collections are created with **`hnsw:space` = `cosine`** (see `ingest/pipeline.py` `_collection()` and `memory/__init__.py` `_open_collection`).

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

- [rag-agent-mcp-integration-roadmap.md § Indexed metadata keys](../workflows/rag-agent-mcp-integration-roadmap.md#indexed-metadata-keys-for-chroma-where-filters)

**Naming pitfall:** metadata key **`model`** is the **embedding model id**, not an Odoo `ir.model`. For Odoo XML, prefer **`xml_model`** when filtering.

## Code map

| Concern | Location |
| --- | --- |
| Collection handles | `ingest/pipeline.py` (`chroma_repo_collection`), `memory/__init__.py` |
| Ingest / embed jobs | `ingest/pipeline.py` (`run_embed_job`, path allowlists) |
| Provider dispatch | `embeddings/providers.py` (`google_genai.py`, `openai_client.py`, `anthropic_client.py`) |
| Query embedding + Chroma | `retrieve/query.py` |
| HTTP API | `api/server.py` (`rag_query`, `embed_commit`, memory routes) |
