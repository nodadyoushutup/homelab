# Terraform best practices (homelab)

Everything in this file is **repository-specific** (layout, slices, modules).
General implementation discipline (small scoped edits, no secrets in `.tf`) is in
the framework **Generic Code Agent** system prompt.

Apply under `terraform/` (Swarm stacks, cluster definitions, and shared
**helper modules** under `terraform/modules/`).

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
  app). Reference: `terraform/swarm/harbor/app/`, `terraform/swarm/nginx_proxy_manager/app/`.
- **`config/`** — **Post-deploy configuration** via providers that target an
  **already running** app (for example Harbor projects, users, and system config
  through the Harbor provider). Reference: `terraform/swarm/harbor/config/`.
- **`database/`** — **Accompanying databases** for the app (for example a MariaDB
  Swarm service with its own network and volume). Reference:
  `terraform/swarm/nginx_proxy_manager/database/`, `terraform/swarm/grafana/database/`.

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
    **in this file only** for that slice (patterns in Harbor and
    nginx-proxy-manager slices).
  - `main.tf` — Core resources and data sources for the slice.
  - `variables.tf` — Input variables for the slice.
  - `outputs.tf` — Outputs from the slice.
  - `locals.tf` — `locals` values for the slice (older stacks may still inline
    `locals` in `main.tf`; converge toward `locals.tf` when you touch the slice).
- When you add a **new** slice or **substantially** extend a slice, prefer this
  full five-file layout so older stacks can converge over time.

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
  Prefer existing helpers (`mcp-service`, `homelab-nfs-mount`, etc.) before
  duplicating large `docker_service` blocks across services.
- **Paths:** from `terraform/swarm/<service>/app/` (and the same depth under
  `config/` or `database/`), use  
  `source = "../../../modules/<name>"`.

## Conventions

- Keep variable defaults and descriptions aligned with `variables.tf` patterns
  nearby.
- Avoid destructive refactors unless the change explicitly requires them; prefer
  additive changes and clear `moved` blocks when renaming addresses.
- Respect remote state and workspace conventions for that stack; do not
  embed secrets in `.tf` files.
