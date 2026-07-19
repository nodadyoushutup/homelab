# Docker / local config layout

Site-local Docker inputs live under this directory. Only two files are used:

| File | Consumed by |
|---|---|
| `minio.env` | `docker/docker-compose.minio.yaml`, `scripts/install/velero.sh` |
| `swarm.tfvars` | Docker Swarm topology; managed by the `homelab-config` web app (`applications/homelab_config`) |

Copy each `*.example` to the matching live file and fill it in:

- `minio.env.example` → `minio.env` (MinIO root credentials)

`swarm.tfvars` has no checked-in example: the `homelab-config` app writes an empty
scaffold on boot and you edit it in the UI (or by hand). See below for the format.

## `minio.env`

Sourced by `scripts/terraform/load_root_env.sh` (via `load_docker_env.sh`) and
mounted by the MinIO compose file. Override the directory with
`HOMELAB_CONFIG_ENV_DIR=/path/to/.config/docker` if it lives elsewhere.

## `swarm.tfvars`

Declares the swarm machines as an HCL `swarm_nodes` map keyed by node name. Each
entry has `host`, `user`, `role` (`manager` or `worker`), `ssh_port`, optional
`ssh_key` / `ssh_password` / `sync_ssh`, and a `labels` object. Exactly one node
must have `role = "manager"` (the control plane).

```hcl
# homelab-config: docker/swarm
swarm_nodes = {
  "swarm-cp-0" = {
    host     = "swarm-cp-0.local"
    user     = "nodadyoushutup"
    role     = "manager"
    ssh_port = 22
    ssh_key  = "ca"
    sync_ssh = true
    labels = {
      "role" = "swarm-cp-0"
    }
  }
}
```

Manage this file from the `homelab-config` web app (run `python config.py`) or
edit it by hand. It is consumed only by that app (to derive the Docker provider
catalog and reconcile the live swarm); it is not passed to Terraform directly.

## Other env vars

Values that used to live in `site.env`, `shared.env`, `mcp.env`, `argocd.env`,
and `qbittorrent.env` are no longer sourced here. Export them in your shell
environment (or your process manager) when a script needs them:

- `CONFIG_DIR` — defaults to `<repo>/.config`; export only to override.
- `ARGOCD_ADMIN_USERNAME` / `ARGOCD_ADMIN_PASSWORD` — for `scripts/install/argocd.sh`.
- `QBITTORRENT_*` / `EXPORTER_*` — for `docker/docker-compose.yaml`.
- Shared API keys and `HOMELAB_MCP_*` URLs — for the tools that consume them.
