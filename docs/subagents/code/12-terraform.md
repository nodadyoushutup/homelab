# Terraform best practices (homelab)

Everything in this file is **repository-specific** (layout, slices, modules).
General implementation discipline (small scoped edits, no secrets in `.tf`) is in
the framework **Generic Code Agent** system prompt.

Apply under `terraform/` (Swarm stacks, cluster definitions, and shared
**helper modules** under `terraform/modules/`).

**New Swarm stack:** classify placement first
([`docs/architecture/terraform/swarm-placement.md`](../../architecture/terraform/swarm-placement.md)),
then slice layout
([`swarm-slices.md`](../../architecture/terraform/swarm-slices.md)).

- Author **HashiCorp Terraform** HCL. **OpenTofu is not used** in this
  repository; do not mention it, assume it, or tune guidance for it.

## Stack slice layout

- Organize each deployable concern into a **slice directory** next to its
  siblings, using the names the service already uses (for example `app/`,
  `config/`, `database/`). Mirror the parent service; do not invent new slice
  names without a reason.

### What each slice means

Treat slices as **separate Terraform roots**: each has its **own remote state**
(different `backend` key) and is planned/applied on its own—**not** one
monolithic stack per service.

- **`app/`** — Core **application infrastructure**: the workloads that define the
  service (for example Docker services, networks, and volumes that run the
  app). Reference: `terraform/components/swarm/zot/app/`, `terraform/components/swarm/nginx_proxy_manager/app/`.
- **`config/`** — **Post-deploy configuration** via providers that target an
  **already running** app (for example NPM proxy hosts and certificates, Grafana
  folders, Vault policies). Reference: `terraform/components/swarm/nginx_proxy_manager/config/`.
- **`database/`** — **Accompanying databases** for the app (for example a MariaDB
  Swarm service with its own network and volume). Reference:
  `terraform/components/swarm/nginx_proxy_manager/database/`, `terraform/components/swarm/grafana/database/`.

These three slice types are the **only** Terraform **roots** in this pattern
(planned/applied with their own state). They are **not** the same as shared
**helper modules** under `terraform/modules/` (see below): helpers are composed
**into** `app/`, `config/`, or `database/` via `module` blocks when you need that
scaffolding.

### Standard files per slice

- **Each slice directory** uses this **standard file set**:
  - `provider.tf` — The **`terraform` block** for this slice (`backend`,
    `required_providers`, and `required_version` when used) and all **`provider`**
    blocks. Keep backend pins, provider constraints, and provider configuration
    **in this file only** for that slice (patterns in zot and nginx-proxy-manager slices).
  - `main.tf` — Core resources and data sources for the slice.
  - `variables.tf` — Input variables for the slice.
  - `outputs.tf` — Outputs from the slice.
  - `locals.tf` — `locals` values for the slice (older stacks may still inline
    `locals` in `main.tf`; converge toward `locals.tf` when you touch the slice).
- When you add a **new** slice or **substantially** extend a slice, prefer this
  full five-file layout so older stacks can converge over time.

### What belongs in slice tfvars vs `main.tf`

| Concern | Where it lives |
| --- | --- |
| **`docker_service`** / **`docker_network`** / volumes / secrets wiring | Slice **`main.tf`** (inline for Swarm stacks) |
| **Container image** reference (tag or digest) | Slice **`main.tf`** `container_spec.image` — **default for all new Swarm stacks** |
| **Published ports** that are part of the stack contract | Slice **`main.tf`** (same pin as the image) |
| **`env`**, **`placement`**, provider API endpoints, NFS targets | Slice tfvars under **`CONFIG_DIR`** (`app.tfvars`, `config.tfvars`, `database.tfvars`) |
| **`secrets`** / **`secret_files`** blocks (Vault merge only) | Same slice tfvars files; never commit real values to repo HCL |

**After image publish:** bump the pin in **`main.tf`**, then **`terraform apply`**
or the repo pipeline for that stack. See
[`docs/workflows/docker-build-github-actions.md`](../../workflows/docker-build-github-actions.md).

**Do not** add an `image` variable for new Swarm **`app/`** or **`database/`**
slices unless there is a concrete reason. Existing exceptions:

- `terraform/components/swarm/jenkins-controller/app` — `controller_image`
- `terraform/components/swarm/prometheus-pve-exporter/app` — `image_reference`
- `terraform/components/runners/*` — `image` or `agent_image` on pool-host **`docker_container`**
  resources

## Helper modules (`terraform/modules/`)

**Different role from slices:** these are **modular building blocks**, not
deployable stacks. Use them to **scaffold** repeated patterns inside whichever
root needs them—typically **`app/`** (Docker service + NFS mounts), but the same
idea applies if **`config/`** or **`database/`** benefits from a shared module
later.

- **Location:** `terraform/modules/<name>/` (peer to `swarm/`, `cluster/`, not
  nested under a service).
- **No root state:** do **not** put `terraform { backend ... }` here. Only
  `app/`, `config/`, and `database/` slices are roots with remote state.
- **Composition:** root `main.tf` (or a dedicated file if the stack already
  splits resources) calls `module "..." { source = ... }` and passes variables.
  For Swarm **`docker_service`** stacks, **inline** the service block in the
  slice root for now; extract a module under `terraform/modules/` only when a
  stable pattern is worth sharing.
- **Paths:** from `terraform/components/swarm/<service>/app/` (and the same depth under
  `config/` or `database/`), use  
  `source = "../../../modules/<name>"`.

## Swarm task placement

Pick the node **before** setting constraints — workload classes and examples:
[`docs/architecture/terraform/swarm-placement.md`](../../architecture/terraform/swarm-placement.md).

Swarm **`app/`** and **`database/`** slices that schedule `docker_service` tasks
use a single optional **`placement`** variable (not `placement_constraints` /
`platform_architecture` / `node_constraint`):

```hcl
placement = {
  constraints = ["node.labels.role==swarm-wk-0"] # observability; use swarm-wk-1 (CI/CD) or swarm-wk-4 (AI) per placement doc
  platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
  ]
}
```

Omit **`placement`** in slice tfvars to skip the task-spec placement block. Set
only **`platforms`** when you need architecture pinning without node constraints.

To rewrite legacy tfvars keys in bulk:

`python3 scripts/terraform/migrate_swarm_placement_tfvars.py .config/terraform/swarm`

## Conventions

- Keep variable defaults and descriptions aligned with `variables.tf` patterns
  nearby.
- Avoid destructive refactors unless the change explicitly requires them; prefer
  additive changes and clear `moved` blocks when renaming addresses.
- Respect remote state and workspace conventions for that stack; do not
  embed secrets in `.tf` files.
