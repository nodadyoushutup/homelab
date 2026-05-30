# Site-local configuration (tfvars, backends, keys)

This directory is the single site-local source of truth: Terraform/Kubernetes tfvars, backends, keys, and split Docker dotenv files under **`docker/`**. It mirrors the layout that used to live under a separate `CONFIG_DIR` on disk (for example `/mnt/eapp/config`). **Terraform pipelines and `scripts/terraform/load_root_env.sh` default `CONFIG_DIR` and `TFVARS_HOME_DIR` to `<repo>/.config`** when they are unset after loading **`.config/docker/*.env`**.

## homelab-config tags (required)

Every Terraform tfvars file, shared component tfvars, `minio.backend.hcl`, and live `docker/*.env` under this tree must start with a **first-line** tag:

```hcl
# homelab-config: <config-id>
```

**`<config-id>`** is the path relative to `.config` without the file suffix:

| File | Tag id |
| --- | --- |
| `terraform/swarm/grafana/app.tfvars` | `terraform/swarm/grafana/app` |
| `terraform/cluster/proxmox/app.tfvars` | `terraform/cluster/proxmox/app` |
| `terraform/cluster/argocd/config.tfvars` | `terraform/cluster/argocd/config` |
| `terraform/remote/cloudflare/config.tfvars` | `terraform/remote/cloudflare/config` |
| `terraform/network/fortigate/config.tfvars` | `terraform/network/fortigate/config` |
| `.config/terraform/components/swarm/swarm.tfvars` | `terraform/components/swarm/swarm` |
| `.config/terraform/components/swarm/dns.tfvars` | `terraform/components/swarm/dns` |
| `.config/terraform/components/swarm/nfs.tfvars` | `terraform/components/swarm/nfs` |
| `.config/terraform/components/runners/amd64.tfvars` | `terraform/components/runners/amd64` |
| `.config/terraform/components/runners/arm64.tfvars` | `terraform/components/runners/arm64` |
| `minio.backend.hcl` | `minio.backend` |
| `docker/langgraph.env` | `docker/langgraph` |
| `scripts/rag.env` | `scripts/rag` |

Pipelines resolve inputs by id (indexed once per run), so you can rename or relocate files under `.config` as long as the tag stays correct. Overrides still win: `--tfvars`, Jenkins `TFVARS_FILE`, and env vars such as `SWARM_DNS_PROVIDER_TFVARS`.

Stamp or verify tags:

```bash
python3 scripts/config/stamp_homelab_config_ids.py --config-dir .config
python3 scripts/config/stamp_homelab_config_ids.py --config-dir .config --check
```

Canonical mirrored paths (for example `terraform/swarm/<svc>/app.tfvars`) remain the fallback when no tagged file exists.

## Layout (typical)

- `docker/` — split `*.env` for Compose, LangGraph, and host scripts (see `docker/README.md` and `docker/*.env.example`)
- `scripts/` — host-only script dotenv (see `scripts/rag.env.example` for `scripts/rag/backfill.sh`); RAG backfill script lives under **`scripts/rag/`**
- `minio.backend.hcl` — shared remote state backend config for Swarm/remote Terraform stages
- `terraform/` — merged tfvars, per-stack `app.tfvars` / `config.tfvars`, shared components under **`terraform/components/{swarm,cluster,runners,remote}/`**, secrets slices where used. Copy from **`terraform/components/**/*.tfvars.example`** into matching paths under **`.config/terraform/components/`**.
- `kubernetes/` — optional cluster tfvars if your site keeps them here
- `.ssh/` — keys and `known_hosts` for optional SSH workflows

## Overrides

Set **`CONFIG_DIR`** in **`docker/site.env`** to point at another tree if this host keeps tfvars elsewhere (CI workspace, NFS-only path). Legacy read-only copies may live under **`/mnt/eapp/config/_old`** on the host; active tfvars should remain under **`<repo>/.config`** (or an explicit **`CONFIG_DIR`**).

## Git

The repo **`.gitignore` ignores `.config/*` except `README.md`, `docker/README.md`, `docker/*.env.example`, `scripts/*.env.example`**, and checked-in examples under **`terraform/components/`**, so live secrets and site tfvars are not committed accidentally. Do not force-add tfvars, `docker/*.env`, or private keys.
