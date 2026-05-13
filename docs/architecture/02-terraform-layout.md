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
| `terraform/swarm/` | One directory per **Swarm-deployed** service or family (`harbor/`, `nginx_proxy_manager/`, `mcp-code/`, observability stacks, runners, …). Most stacks use an `app/` slice; some add `config/` and/or `database/`. |
| `terraform/cluster/` | Cluster-oriented roots: for example **Talos** app slice, **Proxmox** app slice, **Argo CD** `config/` slice for post-install Argo configuration. |
| `terraform/network/` | Network appliances and integrations that are not Swarm services themselves—for example **FortiGate** `config/` against the live firewall API. |
| `terraform/remote/` | SaaS or remote APIs decoupled from on-prem engines—for example **Cloudflare** `config/` for DNS and zone objects. |
| `terraform/modules/` | **Reusable building blocks** (`mcp-service`, `homelab-nfs-mount`, …) consumed *from* slice roots. These directories are **not** Terraform roots: no remote backend here. |

Naming under `swarm/` follows the **service** name (underscores where the
historical stack used them, for example `nginx_proxy_manager`). Prefer matching
that folder name to the operational service name operators already use.

## Slice pattern: `app`, `config`, `database`

Most Swarm-backed services follow **separate Terraform roots per slice**. Each
slice has its **own remote state** (its own `backend` key) and is planned and
applied independently.

| Slice | Purpose | Example in repo |
| --- | --- | --- |
| **`app/`** | Core **runtime infrastructure**: overlay networks, `docker_service` resources, published ports, volumes, secrets wiring—everything needed for the containers to run. | `terraform/swarm/harbor/app/`, `terraform/swarm/mcp-code/app/` |
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
- **App + database:** `prometheus` (`database/` hosts the VictoriaMetrics-style
  long-term store as its own Swarm service and state).
- **App only:** majority of MCP stacks, runners, Loki, Chromadb, Rag-engine,
  etc.

Legacy or transitional layouts may still exist (nested directories, empty parent
folders). **New work** should prefer the flat `terraform/swarm/<service>/<slice>/`
shape alongside siblings.

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
