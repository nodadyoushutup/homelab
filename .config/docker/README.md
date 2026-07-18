# Docker / local config layout

Site-local Docker inputs live under this directory. Only two files are used:

| File | Consumed by |
|---|---|
| `minio.env` | `docker/docker-compose.minio.yaml`, `scripts/install/velero.sh` |
| `swarm.yaml` | `applications/bootstrap` (Docker Swarm topology) |

Copy each `*.example` to the matching live file and fill it in:

- `minio.env.example` → `minio.env` (MinIO root credentials)
- `swarm.yaml.example` → `swarm.yaml` (swarm control plane + worker SSH targets)

## `minio.env`

Sourced by `scripts/terraform/load_root_env.sh` (via `load_docker_env.sh`) and
mounted by the MinIO compose file. Override the directory with
`HOMELAB_CONFIG_ENV_DIR=/path/to/.config/docker` if it lives elsewhere.

## `swarm.yaml`

Declares the swarm control plane and worker SSH targets. Bootstrap builds the
swarm from this file without prompting. If `control_plane` is empty, bootstrap
prompts interactively and writes your answers back here. Passwords are never
stored in this file (key-based SSH first, interactive password fallback).

## Other env vars

Values that used to live in `site.env`, `shared.env`, `mcp.env`, `argocd.env`,
and `qbittorrent.env` are no longer sourced here. Export them in your shell
environment (or your process manager) when a script needs them:

- `CONFIG_DIR` — defaults to `<repo>/.config`; export only to override.
- `ARGOCD_ADMIN_USERNAME` / `ARGOCD_ADMIN_PASSWORD` — for `scripts/install/argocd.sh`.
- `QBITTORRENT_*` / `EXPORTER_*` — for `docker/docker-compose.yaml`.
- Shared API keys and `HOMELAB_MCP_*` URLs — for the tools that consume them.
