# Terraform layout

How **`terraform/`** is organized at the repo level: domains, helper modules,
and pointers to Swarm-specific guides.

## Topics in this folder

| File | What it covers |
| --- | --- |
| [swarm-placement.md](./swarm-placement.md) | **Classify Swarm workloads** (observability → `swarm-wk-0`, CI/CD → `swarm-wk-1`, AI → `swarm-wk-4`) and node placement. |
| [swarm-slices.md](./swarm-slices.md) | Swarm **`app` / `config` / `database`** slices, tfvars, pipelines, image pins in **`main.tf`**. |

HCL editing checklist:
[`docs/subagents/code/12-terraform.md`](../../subagents/code/12-terraform.md).

## Adding a new app

Do **not** jump straight to `main.tf`. Work through this order:

1. **Runtime** — Swarm, Kubernetes, or runner pool?
   [01-repository-layout.md](../01-repository-layout.md#swarm-versus-kubernetes)
2. **Swarm class and node** — observability (`swarm-wk-0`), CI/CD (`swarm-wk-1` /
   runners), AI (`swarm-wk-4`), or manager edge (`swarm-cp-0`).
   [swarm-placement.md](./swarm-placement.md)
3. **Slices and tfvars** — `app` / `config` / `database`, images in `main.tf`,
   live config under `.config/terraform/`.
   [swarm-slices.md](./swarm-slices.md)
4. **HCL checklist** — files per slice, placement variable shape.
   [`docs/subagents/code/12-terraform.md`](../../subagents/code/12-terraform.md)

## Top-level domains under `terraform/`

| Domain | Typical contents |
| --- | --- |
| `terraform/swarm/` | One directory per **Swarm deployable stack** — services (`zot/`, `mcp-rag/`, observability, …). Each stack has Terraform slices (`app/`, `config/`, `database/`) and **bespoke pipeline scripts** under `pipeline/`. Placement and slice rules: [swarm-placement.md](./swarm-placement.md), [swarm-slices.md](./swarm-slices.md). |
| `terraform/network/` | **On-prem network appliance** Terraform roots — **FortiGate** (`fortigate/config`). Pipelines use `scripts/terraform/network_pipeline.sh` (slice tfvars only). |
| `terraform/remote/` | **Remote SaaS / API** Terraform roots — **Cloudflare** DNS (`cloudflare/config`). Pipelines use `scripts/terraform/remote_pipeline.sh` (slice tfvars only). |
| `terraform/cluster/` | **Kubernetes cluster bootstrap** and GitOps wiring: **Proxmox** VM lifecycle (`proxmox/app`), **Argo CD** root Application (`argocd/config`). Pipelines use `scripts/terraform/cluster_pipeline.sh` (slice tfvars only — no Swarm component merges). **Talos** (`talos/app`) remains under **`terraform/swarm/`** until moved. |
| `terraform/runners/` | **Pool-host** workloads outside Swarm: GHA runner pools and Jenkins agent pools. Each uses an `app/` slice and `docker_container` on pool hosts — CI/CD class; see placement doc. Jenkins/bash pipeline entrypoints live under **`pipeline/`** (for example `terraform/runners/gha-runner-amd64/pipeline/app.sh`). |
| `terraform/components/` | Shared **component tfvars** merged by domain pipelines: **`swarm/`** (Docker SSH, DNS, NFS), **`runners/`** (pool-host Docker), **`cluster/`** and **`remote/`** (reserved). Examples live in-repo; live files under **`.config/terraform/components/`**. |
| `terraform/modules/` | **Optional shared HCL** composed into slice roots. **Not** deployable roots (no backend here). Swarm stacks **inline** `docker_service` blocks for now. |

Naming under `swarm/` follows the **operational service name** (underscores where
historical stacks use them, e.g. `nginx_proxy_manager`).

## Helper modules versus slices

- **Slices** (`app`, `config`, `database`) are **deployable roots** with backend
  blocks and independent state. Swarm slice detail:
  [swarm-slices.md](./swarm-slices.md).
- **`terraform/modules/<name>/`** holds shared implementation pulled in via
  `module` blocks (e.g. `source = "../../../modules/<name>"` from
  `terraform/swarm/<service>/app/`).

Extract a **module** when a pattern repeats; do not invent new slice names.

**Cloudflare** DNS lives under **`terraform/remote/`**. **FortiGate** appliance
config lives under **`terraform/network/`**. Cluster bootstrap (**Proxmox**,
**Argo CD**; **Talos** still in swarm) lives under **`terraform/cluster/`** —
see the table above.

Treat **`config/`**-only roots the same way: **one slice = one state**.
