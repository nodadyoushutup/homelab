# Docker / local dotenv layout

Split env files under this directory so Compose can mount only what each service needs.
**Later files override earlier keys** when multiple files are loaded (same order everywhere).

## Load order

1. `site.env` — `CONFIG_DIR` (Terraform tfvars root; not injected into app containers)
2. `shared.env` — shared API keys (`OPENAI_API_KEY`, …)
3. `mcp.env` — MCP HTTP URLs and auth (`HOMELAB_MCP_*`, mounts)
4. `argocd.env` — `scripts/install/argocd.sh`
5. `minio.env` — `docker/docker-compose.minio.yaml`, Velero installer
6. `qbittorrent.env` — `docker/docker-compose.yaml` exporter dev

Copy each `*.env.example` to the matching `*.env` and fill secrets. Do not use a monolithic `.env` here.

## Host scripts

- `scripts/terraform/load_root_env.sh` sources all present `*.env` files via `load_docker_env.sh`.
- Override directory: `HOMELAB_CONFIG_ENV_DIR=/path/to/.config/docker`

## Swarm Terraform

`env_file_path` in stack tfvars points at **one** file per service (Terraform reads a single path). Pipelines still load the full split set via `load_root_env.sh` for keys such as `CONFIG_DIR`.
