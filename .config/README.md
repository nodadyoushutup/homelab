# Site-local configuration (tfvars, backends, keys)

This directory is the single site-local source of truth: Terraform/Kubernetes tfvars, backends, keys, and split Docker dotenv files under **`docker/`**. Its Terraform tree mirrors the repo under **`terraform/components/`** (for example `.config/terraform/components/swarm/grafana/app.tfvars`). **Terraform pipelines and `scripts/terraform/load_root_env.sh` default `CONFIG_DIR` and `TFVARS_HOME_DIR` to `<repo>/.config`** when they are unset after loading **`.config/docker/*.env`**.

## homelab-config tags (required)

Every Terraform tfvars file, shared component tfvars, `minio.backend.hcl`, and live `docker/*.env` under this tree must start with a **first-line** tag:

```hcl
# homelab-config: <config-id>
```

**`<config-id>`** is the path relative to `.config` without the file suffix:

| File | Tag id |
| --- | --- |
| `terraform/components/swarm/grafana/app.tfvars` | `terraform/components/swarm/grafana/app` |
| `terraform/components/cluster/proxmox/app.tfvars` | `terraform/components/cluster/proxmox/app` |
| `terraform/components/cluster/argocd/config.tfvars` | `terraform/components/cluster/argocd/config` |
| `terraform/components/remote/cloudflare/config.tfvars` | `terraform/components/remote/cloudflare/config` |
| `terraform/components/network/fortigate/config.tfvars` | `terraform/components/network/fortigate/config` |
| `terraform/components/swarm/swarm.tfvars` | `terraform/components/swarm/swarm` |
| `terraform/components/swarm/dns.tfvars` | `terraform/components/swarm/dns` |
| `terraform/components/swarm/nfs.tfvars` | `terraform/components/swarm/nfs` |
| `terraform/components/runners/amd64.tfvars` | `terraform/components/runners/amd64` |
| `terraform/components/runners/arm64.tfvars` | `terraform/components/runners/arm64` |
| `minio.backend.hcl` | `minio.backend` |
| `docker/langgraph.env` | `docker/langgraph` |
| `scripts/rag.env` | `scripts/rag` |

Pipelines resolve inputs by id (indexed once per run), so you can rename or relocate files under `.config` as long as the tag stays correct. Overrides still win: `--tfvars`, Jenkins `TFVARS_FILE`, and env vars such as `SWARM_DNS_PROVIDER_TFVARS`.

Stamp or verify tags:

```bash
python3 scripts/config/stamp_homelab_config_ids.py --config-dir .config
python3 scripts/config/stamp_homelab_config_ids.py --config-dir .config --check
```

Canonical mirrored paths (for example `terraform/components/swarm/<svc>/app.tfvars`) remain the fallback when no tagged file exists.

## Layout (typical)

- `docker/` — split `*.env` for Compose, LangGraph, and host scripts (see `docker/README.md` and `docker/*.env.example`)
- `scripts/` — host-only script dotenv (see `scripts/rag.env.example` for `scripts/rag/backfill.sh`); RAG backfill script lives under **`scripts/rag/`**
- `minio.backend.hcl` — shared remote state backend config for Swarm/remote Terraform stages
- `terraform/components/` — site tfvars mirroring **`terraform/components/`** in the repo (`swarm/`, `cluster/`, `remote/`, `network/`, `runners/`). Copy from **`terraform/components/**/*.tfvars.example`** into the matching path under **`.config/terraform/components/`**.
- `kubernetes/` — optional cluster tfvars if your site keeps them here
- `.ssh/` — keys and `known_hosts` for optional SSH workflows

## Overrides

Set **`CONFIG_DIR`** in **`docker/site.env`** only when this host keeps the site config tree somewhere other than **`<repo>/.config`** (for example a CI bind-mount). The canonical layout is still **`$CONFIG_DIR/terraform/components/...`**.

## Git

The repo **`.gitignore` ignores `.config/*` except `README.md`, `docker/README.md`, `docker/*.env.example`, `scripts/*.env.example`**, and checked-in examples under **`terraform/components/`**, so live secrets and site tfvars are not committed accidentally. Do not force-add tfvars, `docker/*.env`, or private keys.
