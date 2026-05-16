# Site-local configuration (tfvars, backends, keys)

This directory is the single site-local source of truth: Terraform/Kubernetes tfvars, backends, keys, and the homelab dotenv (`.env`). It mirrors the layout that used to live under a separate `CONFIG_DIR` on disk (for example `/mnt/eapp/config`). **Terraform pipelines and `scripts/terraform/load_root_env.sh` default `CONFIG_DIR` and `TFVARS_HOME_DIR` to `<repo>/.config`** when they are unset after loading `.config/.env`.

## Layout (typical)

- `.env` — API keys, Compose interpolation, Argo CD installer vars, optional `CONFIG_DIR` override (see `.env.example`)
- `minio.backend.hcl` — shared remote state backend config for Swarm/remote Terraform stages
- `terraform/` — merged tfvars, per-stack `app.tfvars` / `config.tfvars`, providers (`terraform/providers/*.tfvars`), secrets slices where used
- `kubernetes/` — optional cluster tfvars if your site keeps them here
- `.ssh/` — keys and `known_hosts` for scripts that sync or repair state over SSH (for example `scripts/misc/rag_backfill.sh`)

## Overrides

Set **`CONFIG_DIR`** in **`.config/.env`** to point at another tree if this host keeps tfvars elsewhere (CI workspace, NFS-only path). Legacy read-only copies may live under **`/mnt/eapp/config/_old`** on the host; active tfvars should remain under **`<repo>/.config`** (or an explicit **`CONFIG_DIR`**).

## Git

The repo **`.gitignore` ignores `.config/*` except `README.md` and `.env.example`** so live secrets and site tfvars are not committed accidentally. Do not force-add tfvars, `.env`, or private keys.
