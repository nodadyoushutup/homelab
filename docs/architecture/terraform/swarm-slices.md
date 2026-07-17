# Swarm Terraform slices

Swarm stacks under `terraform/components/swarm/<service>/` use the **`app` / `config` /
`database`** slice pattern. Read
[swarm-placement.md](./swarm-placement.md) first when adding a service —
**classify the workload and pick a node** before choosing slices.

HCL file conventions (required files per slice, provider placement):
[`docs/subagents/code/12-terraform.md`](../../subagents/code/12-terraform.md).

## Slice pattern

Each slice is a **separate Terraform root** with its **own remote state**
(`backend` key). Plan and apply slices independently.

| Slice | Purpose | Example |
| --- | --- | --- |
| **`app/`** | Runtime infrastructure: overlay networks, `docker_service`, published ports, volumes, secrets wiring. | `terraform/components/swarm/zot/app/` |
| **`config/`** | Post-deploy configuration via a provider against a **running** system (NPM hosts, Grafana folders, Vault policies). | `terraform/components/swarm/nginx_proxy_manager/config/` |
| **`database/`** | Dedicated data-plane Swarm service (Postgres, MariaDB, MongoDB) with its own lifecycle and state. | `terraform/components/swarm/grafana/database/` |

**Apply order:** **`database/`** (when the app depends on it) → **`app/`** →
**`config/`**. Some stacks are **`app/`** only — apply once dependencies exist.

### Standard files per slice

Each slice directory: `provider.tf`, `main.tf`, `variables.tf`, `outputs.tf`,
`locals.tf` (prefer `locals.tf` over inline locals in `main.tf` on new work).

### Services that only have `app/`

Many stacks are app-only (MCP servers, simple stateless services, global
exporters). Add `config/` or `database/` only when a separate root reduces blast
radius or matches a separate lifecycle.

### Current slice combinations

- **Full trio:** `grafana`, `nginx_proxy_manager` (`app`, `config`, `database`).
- **App + config:** `jenkins-controller`, `vault`.
- **App + database** naming — `{app}-{engine}` service/network/volume:

  | App | Engine | Service / network | Data volume |
  | --- | --- | --- | --- |
  | `grafana` | Postgres | `grafana-postgres` | `grafana-postgres-data` |
  | `graylog` | MongoDB | `graylog-mongodb` | `graylog-mongodb-data`, `graylog-mongodb-config` |
  | `nginx_proxy_manager` | MySQL | `nginx-proxy-manager-mysql` | `nginx-proxy-manager-mysql-data` |

- **VictoriaMetrics** is a standalone `app` (not a `prometheus` database slice).
  Prometheus attaches to its overlay for `remote_write`.
- **App only:** most `mcp-*` stacks, `rag-engine`, `chromadb`, `cadvisor`,
  `container-housekeeping`, `prometheus`, etc.

## Container images and published ports

Swarm **`app/`** and **`database/`** slices pin **`container_spec.image`**
(and contract **published ports**) in **`main.tf`**, not in slice tfvars. After
publish, bump the pin in **`main.tf`**, commit, and re-apply.

Slice tfvars carry **`env`**, **`placement`**, secrets blocks, and provider
endpoints — not image tags. Rollout discipline:
[`docs/workflows/docker-build-github-actions.md`](../../workflows/docker-build-github-actions.md).

**Exceptions (image from tfvars):**

- `jenkins-controller` — `controller_image`
- `prometheus-pve-exporter` — `image_reference`
- `terraform/components/runners/*` — `image` or `agent_image` on `docker_container`

### What belongs where

| Concern | Location |
| --- | --- |
| `docker_service`, networks, volumes | Slice **`main.tf`** |
| Image reference | Slice **`main.tf`** (default) |
| Published ports (stack contract) | Slice **`main.tf`** |
| `env`, `placement`, API endpoints | Slice tfvars under **`CONFIG_DIR`** |
| `secrets` / `secret_files` (Vault merge) | Same tfvars; never real values in git HCL |

## Config and pipelines

Live tfvars mirror the repo under **`CONFIG_DIR`**:

- `terraform/components/swarm/grafana/app/` → `.config/terraform/components/swarm/grafana/app.tfvars`
- Same for `config.tfvars`, `database.tfvars` siblings.

Each file starts with **`# homelab-config: <id>`** matching the mirrored path
without suffix (for example `terraform/components/swarm/grafana/app`). Resolve by tag via
`scripts/terraform/resolve_config_by_id.sh`. Stamp with
`scripts/config/stamp_homelab_config_ids.py` (see `.config/README.md`).

**Provider tfvars** (merged before slice tfvars):

| File | Used for |
| --- | --- |
| `.config/terraform/components/swarm/swarm.tfvars` | Swarm SSH + registry auth |
| `.config/terraform/components/swarm/dns.tfvars` | Swarm DNS resolvers |
| `.config/terraform/components/swarm/nfs.tfvars` | Shared NFS export targets |
| `.config/terraform/components/runners/amd64.tfvars` / `arm64.tfvars` | Runner pool Docker hosts |

Copy from **`terraform/components/**/*.tfvars.example`** into **`.config/terraform/components/`** when bootstrapping a site.

**Vault `config/`** merges `secrets` / `secret_files` from slice tfvars via
`scripts/terraform/vault_merge_config_secrets.py`. Do not put those blocks in
checked-in `terraform/components/swarm/vault/config.tfvars`.

**Pipelines:**

Each stack keeps **bespoke pipeline entrypoints** next to its Terraform slices
under **`terraform/components/swarm/<svc>/pipeline/`** (Swarm services),
**`terraform/components/network/<svc>/pipeline/`** (FortiGate),
**`terraform/components/remote/<svc>/pipeline/`** (Cloudflare), or
**`terraform/components/cluster/<svc>/pipeline/`** (Proxmox, Argo CD):

| File | Runs slice |
| --- | --- |
| `app.sh` | `terraform/components/swarm/<svc>/app/` |
| `config.sh` | `terraform/components/swarm/<svc>/config/` (when present) |
| `database.sh` | `terraform/components/swarm/<svc>/database/` (when present) |

- Default Swarm path: `terraform/components/swarm/<svc>/pipeline/*.sh` via
  `scripts/terraform/swarm_pipeline.sh` (merges `swarm.tfvars`, `dns.tfvars`,
  `nfs.tfvars`, slice tfvars).
- **Cluster** path: `terraform/components/cluster/<svc>/pipeline/*.sh` via
  `scripts/terraform/cluster_pipeline.sh` (slice tfvars only).
- **Remote** path: `terraform/components/remote/<svc>/pipeline/*.sh` via
  `scripts/terraform/remote_pipeline.sh` (slice tfvars only).
- **Network** path: `terraform/components/network/<svc>/pipeline/*.sh` via
  `scripts/terraform/network_pipeline.sh` (slice tfvars only).
- **Bespoke** (no `swarm_pipeline.sh`): `chromadb`, `cadvisor`,
  `cloud-image-repository`, `dozzle`, `node_exporter`, `prometheus`;
  full `nginx_proxy_manager` trio; Grafana `config/` (slice tfvars + backend only).
- **Runners:** `terraform/components/runners/<pool>/pipeline/app.sh`.

Values are not defaulted in module code — set them only under **`CONFIG_DIR`**.
Migrate older flat trees with
`scripts/config/migrate_config_dir_to_repo_layout.py`.

Legacy nested tfvars (`terraform/components/swarm/<svc>/app/app.tfvars`) may still exist on
disk. **New work** uses sibling `app.tfvars` naming one level up.
