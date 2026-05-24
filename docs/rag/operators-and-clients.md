# Operators and clients

## Docker Swarm (Terraform)

**`chromadb`**, **`rag-engine`**, and **`mcp-rag`** are **Swarm services** for the shared stack. The repo’s **`docker/docker-compose.yml`** can run **LangGraph dev**, **Agent Chat**, and optionally **local `rag-engine-dev` + `mcp-rag-dev`** (bind-mounted code); **Chroma is not duplicated in Compose** — dev engine containers use **`RAG_CHROMA_HOSTNAME`** (e.g. **`192.168.1.120:8000`**) to reach Swarm Chroma on the LAN.

| Stack | Terraform | Wrapper script |
| --- | --- | --- |
| ChromaDB | **`terraform/swarm/chromadb/app`** | **`pipelines/terraform/swarm/chromadb/app.sh`** (bespoke; **`swarm.tfvars`** + **`dns.tfvars`** + **`chromadb/app.tfvars`**, not **`swarm_pipeline.sh`**) |
| RAG engine | **`terraform/swarm/rag-engine/app`** | **`pipelines/terraform/swarm/rag-engine/app.sh`** |
| MCP RAG | **`terraform/swarm/mcp-rag/app`** | **`pipelines/terraform/swarm/mcp-rag/app.sh`** |

Tfvars typically live under **`<repo>/.config/terraform/swarm/<stack>/app.tfvars`** (same pattern as other Swarm apps). For **`rag-engine`** and **`mcp-rag`**, set **`env`** (all container settings and secrets) and **`placement`** only; image and ingress ports are fixed in each stack’s **`main.tf`**. Bump the image tag in **`main.tf`** after publish, then re-apply.

**Published ports (fixed in Terraform `main.tf` on the Swarm host):** ChromaDB HTTP **8000**, **`rag-engine` → 9015**, **`mcp-rag` → 9016**.

**Images:** publish with **`.github/workflows/docker_build_push.yml`** (`build_target` **`rag-engine`** or **`mcp-rag`**; **`target_registry`** **`github`** or **`both`** for GHCR under your GitHub username; **`arm64`** when possible). **`rag-engine`** image tag is pinned in **`terraform/swarm/rag-engine/app/main.tf`** (Harbor). Private registry pulls: set **`registry_auths`** under **`swarm_docker_provider_config`** in **`<repo>/.config/terraform/components/swarm.tfvars`**.

Operational note: `tree-sitter-dockerfile` is not installed as a runtime dependency because it does not publish usable wheels on **linux/arm64**; Dockerfile ingestion falls back to other chunking strategies when the grammar is unavailable.

DNS/TLS parity with **`chromadb`**: **`terraform/remote/cloudflare/config`** (`<repo>/.config/terraform/remote/cloudflare/config.tfvars`) holds **`rag-engine.nodadyoushutup.com`** and **`mcp.rag.nodadyoushutup.com`** **`A`** records → **`192.168.1.120`**. **`terraform/swarm/nginx_proxy_manager/config`** (`<repo>/.config/terraform/swarm/nginx_proxy_manager/config.tfvars`) terminates HTTPS and forwards to **`192.168.1.120:9015`** (`GET /healthz`, `POST /v1/query`, …) and **`:9016`** (Cursor Streamable MCP: **`https://mcp.rag.nodadyoushutup.com/mcp`**). The zone **`*.nodadyoushutup.com`** wildcard already pointed at **`192.168.1.120`**; explicit names document RAG URLs and isolate them from wildcard changes. For the general pattern (any new Swarm or cluster app), see [edge-dns-and-nginx-proxy.md](../workflows/edge-dns-and-nginx-proxy.md).

## Docker Compose in this repo

**`docker/docker-compose.yml`** (`homelab-dev`) runs **LangGraph dev**, **Postgres**, **LangChain Agent Chat**, and **local `rag-engine-dev` + `mcp-rag-dev`** for fast iteration on engine/MCP code without Swarm image deploys. **Chroma remains the Swarm service**. For **`rag-engine-dev`**, Compose **overrides** **`RAG_CHROMA_HOSTNAME`** to **`192.168.1.120:8000`** by default (same assumptions as **`terraform/swarm/chromadb`**), so **`.config/docker/rag.env`** may still say **`chromadb:8000`** for Swarm without breaking local dev. Override with **`HOMELAB_DEV_CHROMA_HOSTNAME`** in the shell when your LAN differs. **Postgres** and **LangGraph API state** (`.langgraph_api` checkpoints) use **Docker named volumes** so the containers can write reliably (bind mounts under the repo often hit **NFS `root_squash`** / uid mismatches). **LangChain Agent Chat** in Compose is the **baked `runner` image** (no source bind mount); run **`docker compose build langchain-agent-chat-dev`** after UI changes, then **`up`**.

| Compose service | Role | Host ports (defaults) |
| --- | --- | --- |
| **`rag-engine-dev`** | RAG HTTP API; **`src`** bind-mounted | **9015** → 8080 |
| **`mcp-rag-dev`** | MCP → engine; **`src`** bind-mounted; **`RAG_ENGINE_BASE_URL`** forced to the engine service | **9016** → 8080 |

**`langgraph-dev`** sets **`HOMELAB_MCP_RAG_URL=http://mcp-rag-dev:8080/mcp`** so supervisor and specialists load **`mcp-rag`** from Compose (see **`url_from_env`** on **`mcp-rag`** in each `mcp.json`). Unset that variable in other environments to keep the public HTTPS MCP URL from **`mcp.json`**.

Bring the dev stack up (including RAG):

```bash
sudo docker compose -f docker/docker-compose.langgraph.yml \
  --env-file .config/docker/mcp.env \
  --env-file .config/docker/langgraph.env \
  up -d
```

After editing **`applications/rag-engine/src`** or **`applications/mcp-rag/src`**, restart the affected service (`docker compose restart rag-engine-dev` / `mcp-rag-dev`); no image rebuild required. First run still needs **`docker compose build`** (or an implicit build on `up`) for base images.

Swarm/Terraform RAG (including **`chromadb-data`** on Swarm) remains the persistence and production path; Compose only swaps **where the engine and MCP processes run** for dev.

## Environment variables

Use **`.config/docker/rag.env`** (and **`.config/docker/rag.env.example`**) for the canonical key list. **`scripts/terraform/load_root_env.sh`** (Swarm/terraform pipelines) and other **local scripts** read that file. **Swarm `rag-engine`** and **`mcp-rag`** take container variables from **`env`** in **`.config/terraform/swarm/rag-engine/app.tfvars`** and **`.config/terraform/swarm/mcp-rag/app.tfvars`** respectively.

**Engine / Chroma / embed:** `RAG_CHROMA_HOSTNAME` (default `chromadb:8000`; host-only uses port **8000**), `RAG_CHROMA_COLLECTION`, `RAG_TOP_K` (default repo query nearest-neighbor count; default **20**), `RAG_QUERY_K_MAX` (cap for per-request `k` overrides; default **50**), `RAG_EMBEDDING_PROVIDER`, `RAG_EMBEDDING_MODEL`, `RAG_ENGINE_API_KEY`, memory collection names, memory TTL and scoring tunables (`RAG_MEMORY_*` — see `.config/docker/rag.env.example`, `chroma_config.py`, `server.py` / `memory.py`).

**OpenAI** is the default provider: set `OPENAI_API_KEY` and optionally `RAG_EMBEDDING_MODEL` (default `text-embedding-3-small`) plus `RAG_OPENAI_EMBEDDING_DIMENSIONS`. For **Google**, set `RAG_EMBEDDING_PROVIDER=google` and `GOOGLE_API_KEY`. For **`anthropic`** (Voyage-backed; see `docs/rag/embeddings-and-storage.md`), set `RAG_EMBEDDING_PROVIDER=anthropic`, `VOYAGE_API_KEY`, and optionally `RAG_EMBEDDING_MODEL` (default `voyage-3.5`) plus `RAG_ANTHROPIC_EMBEDDING_DIMENSIONS`. Use a separate Chroma collection or rebuild when changing provider/model/dimensions.

**Ingest scope:** `RAG_PATHS_ALLOWED` (required for indexing — set in Swarm **`env`** / **`.config/docker/rag.env`**), **`RAG_PATHS_DISALLOWED`** (comma-separated path segment names skipped even under allowed prefixes — e.g. `node_modules`, `.venv`), and **`RAG_EXTENSIONS_IGNORE`** (comma-separated file suffixes to skip; no in-app default).

**MCP (`mcp-rag`):** `RAG_ENGINE_BASE_URL`, `RAG_ENGINE_API_KEY`, `MCP_RAG_API_KEY`, `MCP_RAG_LOG_LEVEL`, `MCP_RAG_ENGINE_TIMEOUT_SEC`. Corpus **`rag_search`** breadth is **`RAG_TOP_K`** on **rag-engine** only (not on mcp-rag).

## Cursor and other MCP clients

Step-by-step MCP config, authentication headers, and troubleshooting table:

- [docs/mcp/mcp-rag.md](../mcp/mcp-rag.md)

## Direct HTTP (debugging)

`rag-engine` exposes JSON endpoints (e.g. `POST /v1/query`) for parity checks without MCP. Use the same API key rules as production (`x-api-key` when `RAG_ENGINE_API_KEY` is set).

**Backfill (async):** `POST /v1/backfill` starts a background job (`202`); indexing is followed automatically by orphan prune unless the job is stopped early. `GET /v1/backfill/status` for progress/summary; `POST /v1/backfill/stop` to cancel between files. Dry-run stays synchronous (`200`). Operator script: **`scripts/rag/backfill.sh`** — reads **`.config/scripts/rag.env`** when present, otherwise requires **`--base-url`** and **`--api-key`**. Watch progress in service logs (Dozzle/Graylog).

## Application-level doc

Short pointer to the engine package layout:

- [docs/applications/rag-engine.md](../applications/rag-engine.md)
