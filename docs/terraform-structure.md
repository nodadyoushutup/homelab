# Terraform Structure Guide

This document defines the repository pattern for Terraform so new infrastructure stays consistent with the existing layout.

## 1) Canonical directory hierarchy

Terraform is organized by **infrastructure type** first, then **service**, then one or more **stages**.

```text
terraform/
  cluster/
    <service>/
      <stage>/
  swarm/
    <service>/
      <stage>/
  network/
    <service>/
      <stage>/
  remote/
    <service>/
      <stage>/
```

Current top-level types in this repo:

- `terraform/cluster`
- `terraform/swarm`
- `terraform/network`
- `terraform/remote`

## 2) Stage model (`app`, `config`, `database`, or service-specific)

A service can have one or multiple stages. Common stage names:

- `app`: runtime workload (containers/services/VM resources)
- `config`: API/configuration resources after runtime exists
- `database`: stateful DB/network/volume prerequisites

Service-specific stage names are allowed when they are clearer, for example:

- `terraform/swarm/jenkins-controller/app`
- `terraform/swarm/jenkins-controller/config`
- `terraform/swarm/jenkins/agent` (legacy)

Rule of thumb: each stage is its own Terraform root module and its own state file.

## 3) Required files in each stage

Each stage directory should contain:

```text
terraform/<type>/<service>/<stage>/
  main.tf
  provider.tf
  variables.tf          # `variable.tf` exists in one legacy location; use `variables.tf` for new work
  pipeline/
    <stage>.sh          # often app.sh/config.sh/database.sh
```

Optional stage-local assets are fine when needed, for example:

- templates (`*.tftpl`)
- dashboards/config payloads (`dashboards/*.json`)

## 4) Pipeline organization

Each stage has a thin entrypoint script under `pipeline/` that sets stage metadata and delegates execution to shared helpers.

Entrypoint scripts source:

- `scripts/terraform/load_root_env.sh`
- `scripts/terraform/swarm_pipeline.sh`

Despite the name, `swarm_pipeline.sh` is the common Terraform pipeline wrapper used by `cluster`, `network`, and `remote` stage scripts too.

### Shared helper flow

`swarm_pipeline.sh` orchestrates:

1. `scripts/terraform/env_check.sh` (terraform/realpath/python checks)
2. `scripts/terraform/resolve_inputs.sh` (resolve tfvars/backend paths)
3. `scripts/terraform/terraform_exec.sh` (exec terraform with optional output filtering)
4. Terraform sequence:
   - `terraform init -backend-config=...`
   - `terraform plan -var-file ...`
   - `terraform apply -auto-approve -var-file ...`

Stage scripts can inject hooks:

- `pipeline_pre_terraform`
- `pipeline_post_init`

Use these for dependency checks or stage-specific validation.

### Stage execution order

Execution order is dependency-driven, not global. Use prechecks/hooks when a stage depends on another stage.

Common patterns in this repo:

- `database -> app -> config` (example shape: services where app reads external DB/network created in database stage)
- `app -> config` (example shape: runtime first, then API configuration against it)
- `app -> config` for Jenkins controller

If a non-standard order is required for a service, document that service-specific order near the service Terraform (for example in a service README).

## 5) Naming conventions

### Service path naming

Keep service directory naming stable and consistent with existing usage:

- Hyphenated examples: `mcp-github`, `webserver-image`, `nginx-proxy-manager` (in tfvars path)
- Underscore examples: `nginx_proxy_manager` (Terraform dir), `node_exporter`, `docker_volume_backup`

Do not rename existing service paths unless explicitly planned as a migration.

### Backend state key naming

In each `provider.tf`, define an S3 backend key unique to the stage.

Common patterns in this repo:

- Single-stage service: `<service>.tfstate` (example: `alloy.tfstate`)
- Multi-stage service: `<service>-<stage>.tfstate` (example: `grafana-config.tfstate`)

### tfvars naming

Default tfvars location is under `/mnt/eapp/.tfvars`.

Common stage file pattern:

- `/mnt/eapp/.tfvars/<service>/app.tfvars`
- `/mnt/eapp/.tfvars/<service>/config.tfvars`
- `/mnt/eapp/.tfvars/<service>/database.tfvars`

See [docs/tfvars.md](./tfvars.md) for the full resolution order and overrides.

## 6) New service scaffold (copy pattern)

Example for a new swarm service with `database`, `app`, and `config` stages:

```text
terraform/swarm/<service>/
  database/
    main.tf
    provider.tf
    variables.tf
    pipeline/database.sh
  app/
    main.tf
    provider.tf
    variables.tf
    pipeline/app.sh
  config/
    main.tf
    provider.tf
    variables.tf
    pipeline/config.sh
```

Minimal stage pipeline template:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="<service>"
STAGE_NAME="<Service> <stage>"
ENTRYPOINT_RELATIVE="terraform/<type>/<service>/<stage>/pipeline/<stage>.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/<type>/<service>/<stage>"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/<service>/<stage>.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()
PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
```

## 7) Compliance checklist for adding new Terraform

1. Put new service under the correct type path (`cluster`, `swarm`, `network`, `remote`).
2. Split stage directories only as needed (`app`/`config`/`database` or explicit names like `controller`).
3. Ensure each stage has its own `provider.tf` backend key and pipeline entrypoint.
4. Use `variables.tf` for new stages (avoid new `variable.tf` files).
5. Keep image references direct in resources (do not abstract image names into locals).
6. For new app endpoints, also update Terraform-managed Nginx Proxy Manager and Cloudflare tfvars/config and apply via Terraform pipelines.
7. For new Swarm apps, place resources directly in `terraform/swarm/<service>/<stage>` (do not create new `terraform/module/<service>` abstractions).
8. If a stage depends on another stage, enforce it in pipeline prechecks/hook logic rather than manual assumptions.

## 8) Known exceptions in current repo

- `terraform/cluster/proxmox/app` uses `variable.tf` (legacy naming).
- `terraform/swarm/vault/{app,config}/pipeline/*.sh` intentionally use fixed tfvars/backend paths and reject override args.
- `terraform/swarm/jenkins/agent/pipeline/agent.sh` is legacy and reads controller outputs from `terraform/swarm/jenkins-controller/app`.

These are valid existing patterns; new services should follow the standard pattern unless there is a clear operational reason to diverge.
