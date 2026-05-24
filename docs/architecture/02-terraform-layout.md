# Terraform layout

This file explains how **`terraform/`** is structured: top-level domains, the
**slice** pattern (`app`, `config`, `database`), and how that differs from
**helper modules**.

For HCL editing conventions (required files per slice, provider placement, module
paths), use
[`docs/subagents/code/12-terraform.md`](../subagents/code/12-terraform.md) as
the detailed checklist.

## Top-level domains under `terraform/`

| Domain | Typical contents |
| --- | --- |
| `terraform/swarm/` | One directory per **Swarm-deployed** service or family (`harbor/`, `nginx_proxy_manager/`, `mcp-rag/`, observability stacks, …). Most stacks use an `app/` slice; some add `config/` and/or `database/`. |
| `terraform/runners/` | **Pool-host** workloads outside Swarm: GitHub Actions runner pools (`gha-runner-amd64`, `gha-runner-arm64`) and Jenkins agent pools (`jenkins-agent-amd64`, `jenkins-agent-arm64`). Each uses an `app/` slice and standalone `docker_container` resources on runner pool hosts. |
| `terraform/cluster/` | Cluster-oriented roots: for example **Talos** app slice, **Proxmox** app slice, **Argo CD** `config/` slice for post-install Argo configuration. |
| `terraform/network/` | Network appliances and integrations that are not Swarm services themselves—for example **FortiGate** `config/` against the live firewall API. |
| `terraform/remote/` | SaaS or remote APIs decoupled from on-prem engines—for example **Cloudflare** `config/` for DNS and zone objects. |
| `terraform/modules/` | **Optional shared HCL** for slice roots when a pattern is worth extracting. Swarm stacks currently **inline** their `docker_service` definitions (duplication is OK for now). These directories are **not** Terraform roots: no remote backend here. |

Naming under `swarm/` follows the **service** name (underscores where the
historical stack used them, for example `nginx_proxy_manager`). Prefer matching
that folder name to the operational service name operators already use.

## Slice pattern: `app`, `config`, `database`

Most Swarm-backed services follow **separate Terraform roots per slice**. Each
slice has its **own remote state** (its own `backend` key) and is planned and
applied independently.

| Slice | Purpose | Example in repo |
| --- | --- | --- |
| **`app/`** | Core **runtime infrastructure**: overlay networks, `docker_service` resources, published ports, volumes, secrets wiring—everything needed for the containers to run. | `terraform/swarm/harbor/app/`, `terraform/swarm/mcp-rag/app/` |
| **`config/`** | **Post-deploy configuration** using a provider that targets an *already running* system (Harbor projects, Jenkins init scripts, Grafana folders/datasources, Vault policies, NPM proxy hosts, etc.). | `terraform/swarm/harbor/config/`, `terraform/cluster/argocd/config/` |
| **`database/`** | **Dedicated data plane** for the app when it is modeled as its own Swarm service (MariaDB, Postgres sidecars, etc.) with its own lifecycle and state. | `terraform/swarm/nginx_proxy_manager/database/`, `terraform/swarm/grafana/database/` |

**Apply order in practice:** bring up **`app/`** (or ensure the dependency stack
is already healthy), then **`database/`** when present, then **`config/`**—
config providers assume endpoints exist.

### Services that only have `app/`

Many stacks are **app-only** (observability agents, MCP servers, simple
stateless services). That is normal: add `config/` or `database/` only when a
separate root genuinely reduces blast radius or matches a separate lifecycle
(for example rebuilding DB storage without touching the app definition).

### Current slice combinations (Swarm)

Illustrative snapshot of how existing services split:

- **Full trio:** `grafana` (`app`, `config`, `database`), `nginx_proxy_manager`
  (same).
- **App + config:** `harbor`, `jenkins-controller`, `vault`.
- **Vault `config/`** pipeline merges plain HCL `secrets` / `secret_files` blocks
  embedded in slice tfvars (`app.tfvars`, `config.tfvars`, `database.tfvars`) under
  `TFVARS_HOME/terraform/**` and `TFVARS_HOME/kubernetes/**` (see
  `scripts/terraform/vault_merge_config_secrets.py`); `terraform/swarm/vault/config.tfvars`
  must not contain `secrets` or `secret_files`. For bulk moves from an old monolith,
  use `scripts/terraform/vault_split_k8s_secrets.py` (writes `app.tfvars` fragments).
  To fold standalone `secrets.tfvars` into slice tfvars, use
  `scripts/config/consolidate_secrets_into_slice_tfvars.py`.
- **Shared tfvars layout** mirrors this repo under `CONFIG_DIR`: for each
  Terraform slice root such as `terraform/swarm/grafana/app/`, live tfvars sit
  **one level up**, named for the slice: `terraform/swarm/grafana/app.tfvars`,
  `terraform/swarm/grafana/config.tfvars`, `terraform/swarm/grafana/database.tfvars`.
  Each file (and `minio.backend.hcl`, provider tfvars, live `docker/*.env`) must
  start with **`# homelab-config: <id>`** where `<id>` matches the mirrored path
  without suffix (for example `terraform/swarm/grafana/app`). Pipelines resolve by
  tag via `scripts/terraform/resolve_config_by_id.sh`; canonical paths are fallback
  only. Stamp tags with `scripts/config/stamp_homelab_config_ids.py` (see `.config/README.md`).
  Optional `secrets` / `secret_files` blocks in those files are **Vault-only**
  (declared as ignored variables on each slice root). The same rule applies under
  `terraform/cluster/...`, `terraform/remote/...`, `terraform/network/...`, and
  `terraform/runners/...`.
  Swarm Docker provider credentials stay at `terraform/components/swarm.tfvars`
  (Swarm control plane SSH + registry auth). Runner pool hosts use
  `terraform/components/amd64.tfvars` and `terraform/components/arm64.tfvars`
  (shared per arch by GHA runner and Jenkins agent pipelines).
  Swarm DNS resolvers live at `terraform/components/dns.tfvars`, and shared NFS export
  targets at `terraform/components/nfs.tfvars` (required for `swarm_pipeline.sh` unless a
  stage sets `SWARM_SKIP_DNS_PROVIDER_TFVARS` or `SWARM_SKIP_NFS_PROVIDER_TFVARS`;
  merged as swarm.tfvars (Swarm stacks only), then dns,
  then nfs, before each stack's slice tfvars).
  Runner pool pipelines live under `pipelines/terraform/runners/<pool>/app.sh` and merge
  amd64 or arm64 provider tfvars, then dns, nfs, and slice tfvars via `swarm_pipeline.sh`.
  **Bespoke pipelines** (no `swarm_pipeline.sh`): app stacks `chromadb`,
  `cloud-image-repository`, `dozzle`, `node_exporter`, and `prometheus` use
  `pipelines/terraform/swarm/<svc>/app.sh`. The full
  `nginx_proxy_manager` trio (`database.sh`, `app.sh`, `config.sh`) is bespoke:
  database and app merge `swarm.tfvars`, `dns.tfvars`, slice tfvars, and
  `minio.backend.hcl` (no NFS provider tfvars); config merges only slice tfvars and
  the backend (NPM API credentials live in config tfvars). Grafana `config/` also
  merges only slice tfvars and the backend (`provider_config` lives in
  `terraform/swarm/grafana/config.tfvars`, same pattern as NPM).
  Values are not defaulted in
  module code—set them only under CONFIG_DIR. Kubernetes app config under `kubernetes/<app>/`. Use
  `scripts/config/migrate_config_dir_to_repo_layout.py` to move an older flat
  `CONFIG_DIR/<name>/` tree (it also flattens legacy `*/<slice>/<slice>.tfvars`
  and `*/config/secrets.tfvars` when present).
- **App + database:** separate Swarm DB slices use **`{app}-{engine}`** names
  (overlay, service, and `-{engine}-data` volume where applicable):

  | App slice | Database engine | Service / network | Data volume |
  | --- | --- | --- | --- |
  | `grafana` | Postgres | `grafana-postgres` | `grafana-postgres-data` |
  | `graylog` | MongoDB | `graylog-mongodb` | `graylog-mongodb-data`, `graylog-mongodb-config` |
  | `nginx_proxy_manager` | MySQL | `nginx-proxy-manager-mysql` | `nginx-proxy-manager-mysql-data` |
- **VictoriaMetrics** (`terraform/swarm/victoriametrics/app`) is a standalone app
  (not a `prometheus` database slice): overlay **`victoriametrics-net`**, service
  **`victoriametrics`**, volume **`victoriametrics-data`**, DNS alias
  **`victoriametrics`**. Prometheus (`terraform/swarm/prometheus/app`) attaches to
  that overlay for `remote_write` (`http://victoriametrics:8428/api/v1/write` in
  live `prometheus.yaml`).
- **App only:** majority of MCP stacks, Rag-engine, VictoriaMetrics,
  Graphite, etc. Simple app-only stacks with bespoke pipelines: `chromadb`,
  `cloud-image-repository`, `dozzle`, `node_exporter`, `prometheus`. Runner pools
  (`terraform/runners/*`) and Jenkins agents use `swarm_pipeline.sh` with pool-host
  Docker provider tfvars. The `nginx_proxy_manager` database, app, and config slices
  all use bespoke pipelines.

Legacy nested tfvars (`terraform/swarm/<svc>/app/app.tfvars`) may still exist on
disk until flattened. **New work** should use the sibling naming above.

## Helper modules versus slices

- **Slices** (`app`, `config`, `database`) are **deployable roots** with backend
  blocks and independent plans.
- **`terraform/modules/<name>/`** holds **shared implementation** pulled in via
  `module` blocks. From a typical Swarm app root, module sources use relative
  paths such as `../../../modules/<name>` (exact depth depends on slice
  nesting—mirror neighboring stacks).

If a pattern repeats across many `docker_service` definitions but is not a
standalone deployable unit, extract a **module** instead of a new slice name.

## Cluster and remote stacks

Not every Terraform root lives under `swarm/`:

- **`cluster/proxmox/app`** and **`cluster/talos/app`** model compute and cluster
  bootstrap layers.
- **`cluster/argocd/config`** configures Argo after the control plane exists.
  See [04-argocd-gitops.md](./04-argocd-gitops.md) for how the
  Terraform-managed `Application` and `ApplicationSet` relate to
  `kubernetes/argocd-management/`.
- **`remote/cloudflare/config`** and **`network/fortigate/config`** manage
  remote APIs—same **config slice** idea: separate state, targeted provider, run
  after the dependency exists.

Treat those as the same **“slice = own state”** discipline even when the slice
name is only `config/`.
