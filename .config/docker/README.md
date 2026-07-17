# Docker / local dotenv layout

Split env files under this directory so Compose can mount only what each service needs.
**Later files override earlier keys** when multiple files are loaded (same order everywhere).

## Load order

1. `site.env` — `CONFIG_DIR` (Terraform tfvars root; not injected into app containers)
2. `shared.env` — API keys shared across RAG and related tools (`OPENAI_API_KEY`, …)
3. `rag.env` — RAG engine, hooks, Chroma/embed (`RAG_*`, `RAG_ENGINE_*`)
4. `mcp.env` — MCP HTTP URLs and auth (`HOMELAB_MCP_*`, `MCP_RAG_*`, mounts)
5. `argocd.env` — `scripts/install/argocd.sh`
6. `minio.env` — `docker/docker-compose.minio.yaml`, Velero installer
7. `qbittorrent.env` — `docker/docker-compose.yaml` exporter dev

Copy each `*.env.example` to the matching `*.env` and fill secrets. Do not use a monolithic `.env` here.

## Docker Compose (`homelab-rag-dev`)

| Service | `env_file` |
|---------|------------|
| `rag-engine-dev` | `shared.env`, `rag.env` |
| `mcp-rag-dev` | `rag.env`, `mcp.env` |

For **Compose variable interpolation**, pass the same files on the CLI:

```bash
docker compose -f docker/docker-compose.rag.yml \
  --env-file .config/docker/mcp.env \
  --env-file .config/docker/rag.env \
  up -d --build
```

## Host scripts

- `scripts/terraform/load_root_env.sh` sources all present `*.env` files via `load_docker_env.sh`.
- Override directory: `HOMELAB_CONFIG_ENV_DIR=/path/to/.config/docker`

## Swarm Terraform

`env_file_path` in stack tfvars points at **one** file per service (Terraform reads a single path):

| Stack | Typical `env_file_path` |
|-------|-------------------------|
| `rag-engine` | `…/.config/docker/rag.env` (include `OPENAI_API_KEY` here for Swarm) |
| `mcp-rag` | `…/.config/docker/mcp.env` |

Pipelines still load the full split set via `load_root_env.sh` for keys such as `CONFIG_DIR`.
