# Operators and clients

## Docker Swarm (Terraform)

**`chromadb`**, **`rag-engine`**, and **`mcp-rag`** are **Swarm services** for the shared stack. The repo’s **`docker/docker-compose.yml`** can run **LangGraph dev**, **Agent Chat**, and optionally **local `rag-engine-dev` + `mcp-rag-dev`** (bind-mounted code); **Chroma is not duplicated in Compose** — dev engine containers use **`RAG_CHROMA_HOST` / `RAG_CHROMA_PORT`** in **`.secrets/.env`** to reach Swarm Chroma on the LAN.

| Stack | Terraform | Wrapper script |
| --- | --- | --- |
| ChromaDB | **`terraform/swarm/chromadb/app`** | **`pipelines/terraform/swarm/chromadb/app.sh`** |
| RAG engine | **`terraform/swarm/rag-engine/app`** | **`pipelines/terraform/swarm/rag-engine/app.sh`** |
| MCP RAG | **`terraform/swarm/mcp-rag/app`** | **`pipelines/terraform/swarm/mcp-rag/app.sh`** |

Tfvars typically live under **`/mnt/eapp/config/<name>/app.tfvars`** (same pattern as other Swarm apps).

**Published ports (Terraform defaults on the Swarm host):** ChromaDB HTTP **`published_port`** default **8000** (see **`terraform/swarm/chromadb/app/variables.tf`**), **`rag-engine` → 9015**, **`mcp-rag` → 9016**. Adjust in tfvars if your host uses different ingress ports.

**Images:** publish with **`.github/workflows/docker_build_push.yml`** (`build_target` **`rag-engine`** or **`mcp-rag`**; **`target_registry`** **`github`** or **`both`** for GHCR under your GitHub username; **`arm64`** when possible). Point **`image_reference`** in tfvars at the tag you pushed (for example **`ghcr.io/nodadyoushutup/rag-engine:latest`**). Private GHCR pulls: add **`provider_config.registry_auth`** `{ address?, username, password }` (same nesting as **`terraform/swarm/gha-runner-arm64`** / **`chromadb`**).

Operational note: `tree-sitter-dockerfile` is not installed as a runtime dependency because it does not publish usable wheels on **linux/arm64**; Dockerfile ingestion falls back to other chunking strategies when the grammar is unavailable.

DNS/TLS parity with **`chromadb`**: **`terraform/remote/cloudflare/config`** (`/mnt/eapp/config/cloudflare/config.tfvars`) holds **`rag-engine.nodadyoushutup.com`** and **`mcp.rag.nodadyoushutup.com`** **`A`** records → **`192.168.1.120`**. **`terraform/swarm/nginx_proxy_manager/config`** (`nginx-proxy-manager/config.tfvars`) terminates HTTPS and forwards to **`192.168.1.120:9015`** (`GET /healthz`, `POST /v1/query`, …) and **`:9016`** (Cursor Streamable MCP: **`https://mcp.rag.nodadyoushutup.com/mcp`**). The zone **`*.nodadyoushutup.com`** wildcard already pointed at **`192.168.1.120`**; explicit names document RAG URLs and isolate them from wildcard changes.

## Docker Compose in this repo

**`docker/docker-compose.yml`** (`homelab-dev`) runs **LangGraph dev**, **Postgres**, **LangChain Agent Chat**, and **local `rag-engine-dev` + `mcp-rag-dev`** for fast iteration on engine/MCP code without Swarm image deploys. **Chroma remains the Swarm service**. For **`rag-engine-dev`**, Compose **overrides** **`RAG_CHROMA_HOST` / `RAG_CHROMA_PORT`** to **`192.168.1.120` / `8000`** by default (same assumptions as **`terraform/swarm/chromadb`**), so **`.secrets/.env`** may still say **`chromadb`** for Swarm without breaking local dev. Override with **`HOMELAB_DEV_CHROMA_HOST`** / **`HOMELAB_DEV_CHROMA_PORT`** in the shell when your LAN differs.

| Compose service | Role | Host ports (defaults) |
| --- | --- | --- |
| **`rag-engine-dev`** | RAG HTTP API; **`src`** bind-mounted | **9015** → 8080 |
| **`mcp-rag-dev`** | MCP → engine; **`src`** bind-mounted; **`RAG_ENGINE_BASE_URL`** forced to the engine service | **9016** → 8080 |

**`langgraph-dev`** sets **`HOMELAB_MCP_RAG_URL=http://mcp-rag-dev:8080/mcp`** so supervisor and specialists load **`mcp-rag`** from Compose (see **`url_from_env`** on **`mcp-rag`** in each `mcp.json`). Unset that variable in other environments to keep the public HTTPS MCP URL from **`mcp.json`**.

Bring the dev stack up (including RAG):

```bash
sudo docker compose -f docker/docker-compose.yml --env-file .secrets/.env up -d
```

After editing **`applications/rag-engine/src`** or **`applications/mcp-rag/src`**, restart the affected service (`docker compose restart rag-engine-dev` / `mcp-rag-dev`); no image rebuild required. First run still needs **`docker compose build`** (or an implicit build on `up`) for base images.

Swarm/Terraform RAG (including **`chromadb-data`** on Swarm) remains the persistence and production path; Compose only swaps **where the engine and MCP processes run** for dev.

## Environment variables

Use **`.secrets/.env`** (and **`.secrets/.env.example`**) for the canonical key list. **Git hooks** and **local scripts** read that file. **Swarm** services take the same variables via Terraform (`env_file_path` / `env` on the **`rag-engine`** and **`mcp-rag`** modules — see their **`main.tf`**).

**Engine / Chroma / embed:** `RAG_CHROMA_HOST`, `RAG_CHROMA_PORT`, `RAG_CHROMA_COLLECTION`, `RAG_EMBEDDING_PROVIDER`, `RAG_EMBEDDING_MODEL`, `RAG_ENGINE_API_KEY`, memory collection names, memory TTL and scoring tunables (`RAG_MEMORY_*` — see `.secrets/.env.example` and the engine’s `server.py` / `memory.py`).

For OpenAI embeddings, set `RAG_EMBEDDING_PROVIDER=openai`, `OPENAI_API_KEY`, and optionally `RAG_EMBEDDING_MODEL` (default `text-embedding-3-small`) plus `RAG_OPENAI_EMBEDDING_DIMENSIONS`. Use a separate Chroma collection or rebuild when changing provider/model/dimensions.

**Ingest scope:** `RAG_ALLOWED_PATH_PREFIXES`, and hook alignment `RAG_HOOK_INCLUDE_PREFIXES`.

**MCP (`mcp-rag`):** `RAG_ENGINE_BASE_URL`, `RAG_ENGINE_API_KEY`, `MCP_RAG_API_KEY`, `MCP_RAG_LOG_LEVEL`, `MCP_RAG_ENGINE_TIMEOUT_SEC`.

## Cursor and other MCP clients

Step-by-step MCP config, authentication headers, and troubleshooting table:

- [docs/mcp/rag.md](../mcp/rag.md)

## Direct HTTP (debugging)

`rag-engine` exposes JSON endpoints (e.g. `POST /v1/query`) for parity checks without MCP. Use the same API key rules as production (`x-api-key` when `RAG_ENGINE_API_KEY` is set).

## Application-level doc

Short pointer to the engine package layout:

- [docs/applications/rag-engine.md](../applications/rag-engine.md)
