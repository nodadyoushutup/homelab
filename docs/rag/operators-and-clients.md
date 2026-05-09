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

## Docker Swarm (Terraform)

Stacks live under **`terraform/swarm/rag-engine/app`** and **`terraform/swarm/mcp-rag/app`**. Wrapper scripts: **`pipelines/terraform/swarm/rag-engine/app.sh`** and **`pipelines/terraform/swarm/mcp-rag/app.sh`** (same pattern as other Swarm apps; tfvars typically under `/mnt/eapp/config/<name>/app.tfvars`).

Images: publish with **`.github/workflows/docker_build_push.yml`** (`build_target` **`rag-engine`** or **`mcp-rag`**; **`target_registry`** **`github`** or **`both`** for GHCR under your GitHub username; **`arm64`** when possible). Point **`image_reference`** in tfvars at the tag you pushed (for example **`ghcr.io/nodadyoushutup/rag-engine:latest`**). Private GHCR pulls: add **`provider_config.registry_auth`** `{ address?, username, password }` (same nesting as **`terraform/swarm/gha-runner-arm64`** / **`chromadb`**).

Operational note: `tree-sitter-dockerfile` is not installed as a runtime dependency because it does not publish usable wheels on **linux/arm64**; Dockerfile ingestion falls back to other chunking strategies when the grammar is unavailable.

## Environment variables

All values belong in **`.secrets/.env`** with matching keys documented in **`.secrets/.env.example`** (no Compose-time `${VAR:-default}` pattern in `docker/docker-compose.yaml`).

**Engine / Chroma / embed:** `RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`, `RAG_CHROMA_COLLECTION`, `RAG_EMBEDDING_MODEL`, `RAG_ENGINE_API_KEY`, memory collection names, memory TTL and scoring tunables (`RAG_MEMORY_*` — see `.secrets/.env.example` and `docker/docker-compose.yaml` `rag-engine` service).

**Ingest scope:** `RAG_ALLOWED_PATH_PREFIXES`, and hook alignment `RAG_HOOK_INCLUDE_PREFIXES`.

**MCP (`mcp-rag`):** `RAG_ENGINE_BASE_URL`, `RAG_ENGINE_API_KEY`, `MCP_RAG_API_KEY`, `MCP_RAG_LOG_LEVEL`, `MCP_RAG_ENGINE_TIMEOUT_SEC`.

**Google ADK container** (when using the bundled agent): variables such as `MCP_RAG_URL`, `MCP_RAG_PROXY_API_KEY`, optional `MCP_RAG_TOOLS` — see Compose and `.secrets/.env.example`.

## Cursor and other MCP clients

Step-by-step MCP config, authentication headers, and troubleshooting table:

- [docs/mcp/rag.md](../mcp/rag.md)

## Direct HTTP (debugging)

`rag-engine` exposes JSON endpoints (e.g. `POST /v1/query`) for parity checks without MCP. Use the same API key rules as production (`x-api-key` when `RAG_ENGINE_API_KEY` is set).

## Application-level doc

Short pointer to the engine package layout:

- [docs/applications/rag-engine.md](../applications/rag-engine.md)
