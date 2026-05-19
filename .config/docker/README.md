# Docker / local dotenv layout

Split env files under this directory so Compose can mount only what each service needs.
**Later files override earlier keys** when multiple files are loaded (same order everywhere).

## Load order

1. `site.env` — `CONFIG_DIR` (Terraform tfvars root; not injected into app containers)
2. `shared.env` — API keys shared across LangGraph and RAG (`OPENAI_API_KEY`, …)
3. `postgres.env` — LangGraph dev Postgres (`POSTGRES_*`)
4. `rag.env` — RAG engine, hooks, Chroma/embed (`RAG_*`, `RAG_ENGINE_*`)
5. `mcp.env` — MCP HTTP URLs and auth (`HOMELAB_MCP_*`, `MCP_RAG_*`, mounts)
6. `langgraph.env` — LangGraph runtime (models, tracing, workflow gates)
7. `agents.env` — Host scripts / Harbor / optional remote agent endpoints
8. `argocd.env` — `scripts/install/argocd.sh`
9. `minio.env` — `docker/docker-compose.minio.yaml`, Velero installer
10. `qbittorrent.env` — `docker/docker-compose.yaml` exporter dev

Copy each `*.env.example` to the matching `*.env` and fill secrets. Do not use a monolithic `.env` here.

## Docker Compose (`homelab-dev`)

| Service | `env_file` |
|---------|------------|
| `langgraph-postgres` | `postgres.env` |
| `langgraph-dev` | `postgres.env`, `shared.env`, `langgraph.env`, `mcp.env` |
| `rag-engine-dev` | `shared.env`, `rag.env` |
| `mcp-rag-dev` | `rag.env`, `mcp.env` |
| `mcp-code-dev` | `mcp.env` |

For **Compose variable interpolation** (`${HOMELAB_MCP_CODE_HOST_MOUNT}`, …), pass the same files on the CLI:

```bash
docker compose -f docker/docker-compose.langgraph.yml \
  --env-file .config/docker/mcp.env \
  --env-file .config/docker/langgraph.env \
  up -d --build
```

## Host scripts and LangGraph

- `scripts/terraform/load_root_env.sh` sources all present `*.env` files via `load_docker_env.sh`.
- LangGraph `framework.configuration.merged_settings()` uses the same order.
- Override directory: `HOMELAB_CONFIG_ENV_DIR=/path/to/.config/docker`

## Swarm Terraform

`env_file_path` in stack tfvars points at **one** file per service (Terraform reads a single path):

| Stack | Typical `env_file_path` |
|-------|-------------------------|
| `rag-engine` | `…/.config/docker/rag.env` (include `OPENAI_API_KEY` here for Swarm) |
| `mcp-rag` | `…/.config/docker/mcp.env` |

Pipelines still load the full split set via `load_root_env.sh` for keys such as `CONFIG_DIR` and Harbor.
