# Terraform Rules

This document defines the baseline Terraform rules for this repo. Use it for
layout, naming, ownership, and guardrails. Use
[docs/rules/applications.md](./applications.md) when deciding whether a new app
belongs in Swarm or Kubernetes. Use
[docs/rules/application-networking.md](./application-networking.md) for app
hostname, DNS, and exposure rules. Use
[docs/workflows/terraform.md](./../workflows/terraform.md) for the operator flow
and [docs/rules/repo.md](./repo.md) for repo-wide rules that also apply here.
For the Swarm-hosted MCP service set, also use
[docs/rules/mcp-servers.md](./mcp-servers.md).

## Scope

Terraform in this repo is organized by infrastructure type first, then service,
then stage. Current top-level groups are:

- `terraform/cluster`
- `terraform/swarm`
- `terraform/network`
- `terraform/remote`

The normal path shape is:

```text
terraform/<type>/<service>/<stage>/
```

Examples already in use:

- `terraform/swarm/grafana/app`
- `terraform/swarm/grafana/database`
- `terraform/swarm/grafana/config`
- `terraform/network/fortigate/config`
- `terraform/remote/cloudflare/config`

## Stage Model

Each stage directory is its own Terraform root and its own state file. Common
stage names are:

- `app` for runtime resources
- `config` for post-runtime API/configuration resources
- `database` for stateful prerequisites

Service-specific stage names are allowed when they match the implementation
better than the generic names. Existing examples include:

- `terraform/swarm/jenkins/agent`
- `terraform/swarm/jenkins-controller/app`
- `terraform/swarm/jenkins-controller/config`

## Required Stage Files

New stage directories should follow this pattern:

```text
terraform/<type>/<service>/<stage>/
  main.tf
  provider.tf
  variables.tf
  pipeline/
    <stage>.sh
```

Additional files are fine when they are part of the implementation, for example:

- `outputs.tf`
- `data.tf`
- `*.tftpl`
- stage-local JSON payloads such as dashboards

Use `variables.tf` for new work. A few older directories still use
`variable.tf`; treat those as legacy, not the pattern to copy.

## Pipeline Conventions

Every stage is expected to have a thin entrypoint script under `pipeline/`.
That script defines the stage metadata and then sources the shared wrapper at
`scripts/terraform/swarm_pipeline.sh`.

The normal entrypoint responsibilities are:

1. Resolve `ROOT_DIR` and `PIPELINE_SCRIPT_ROOT`.
2. Set `SERVICE_NAME`, `STAGE_NAME`, `ENTRYPOINT_RELATIVE`, and `TERRAFORM_DIR`.
3. Point `DEFAULT_TFVARS_FILE` at the service/stage tfvars file.
4. Optionally set `PLAN_ARGS_EXTRA` or `APPLY_ARGS_EXTRA`.
5. Pass through CLI args in `PIPELINE_ARGS`.
6. Source `scripts/terraform/swarm_pipeline.sh`.

Despite its name, `swarm_pipeline.sh` is the common Terraform wrapper for
`cluster`, `swarm`, `network`, and `remote` stages.

Recognized hook points in the shared wrapper are:

- `pipeline_pre_terraform`
- `pipeline_post_init`

Use those when a stage needs repo-specific prechecks or post-init behavior.

## tfvars and Backend Rules

Default tfvars live under `/mnt/eapp/.tfvars`. The common pattern is:

- `/mnt/eapp/.tfvars/<service>/app.tfvars`
- `/mnt/eapp/.tfvars/<service>/config.tfvars`
- `/mnt/eapp/.tfvars/<service>/database.tfvars`

Some services intentionally use a different basename. Existing examples include:

- `nginx_proxy_manager` Terraform paths paired with `.tfvars/nginx-proxy-manager/...`
- single-stage services that resolve to `/mnt/eapp/.tfvars/<service>.tfvars`

The default backend file is usually:

- `/mnt/eapp/.tfvars/minio.backend.hcl`

The shared scripts resolve tfvars home like this:

- `TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"`

`scripts/terraform/load_root_env.sh` preserves already-exported values for:

- `TFVARS_DIR`
- `TFVARS_HOME_DIR`
- `JENKINS_TFVARS_DIR`
- `JENKINS_CONTROLLER_TFVARS_DIR`

Jenkins-specific defaults remain special cases:

- `JENKINS_TFVARS_DIR` defaults to `${TFVARS_DIR}/jenkins`
- `JENKINS_CONTROLLER_TFVARS_DIR` defaults to `${TFVARS_DIR}/jenkins-controller`

If a stage needs fixed inputs and must reject overrides, document that in the
pipeline and keep the behavior explicit. `vault` already does this.

### tfvars lookup precedence

`scripts/terraform/resolve_inputs.sh` resolves inputs in this order.

TFVARS:

1. explicit `--tfvars <path>` or first positional arg
2. `DEFAULT_TFVARS_FILE` from the stage script
3. `TFVARS_HOME_DIR/${DEFAULT_TFVARS_BASENAME}[.tfvars]`
4. first top-level `*.tfvars` in `TFVARS_HOME_DIR`
5. first top-level `*.tfvars` in the Terraform working directory

Backend config:

1. explicit `--backend <path>` or second positional arg
2. `DEFAULT_BACKEND_FILE` from the stage script
3. first top-level `*.backend.hcl` or `backend.hcl` in `TFVARS_HOME_DIR`

If either path cannot be resolved, the pipeline fails before `terraform init`.

### tfvars directory expectations

`/mnt/eapp/.tfvars/<service>/` can include more than `*.tfvars` files. Companion
assets such as `config.yaml`, `grafana.ini`, `service_account.json`, cloud-init
YAML, or Talos patch files are normal when a stage consumes them.

## Backend State Naming

Each stage must have a unique backend key in `provider.tf`.

Patterns already used in this repo:

- single-stage service: `<service>.tfstate`
- multi-stage service: `<service>-<stage>.tfstate`

Do not share one state file across multiple stages.

## New Swarm Work

For new Docker Swarm applications:

- define resources directly under `terraform/swarm/<service>/<stage>`
- do not create new `terraform/module/<service>` abstractions
- do not abstract container images into locals
- keep the image directly in the resource definition

This is current repo policy, not a suggestion.

## Naming Rules

Match existing service naming instead of trying to normalize the whole tree.
The repo intentionally has both hyphenated and underscored names depending on
the implementation history and external system naming.

Examples:

- Terraform path: `terraform/swarm/nginx_proxy_manager/...`
- tfvars path: `/mnt/eapp/.tfvars/nginx-proxy-manager/...`
- Terraform path: `terraform/swarm/node_exporter/...`
- Terraform path: `terraform/swarm/mcp-github/...`

Do not rename service paths unless the work is explicitly a migration.

## Dependency and Ordering Rules

Stage order is dependency-driven, not globally enforced. The common shapes are:

- `database -> app -> config`
- `app -> config`

If a stage depends on another stage, enforce it in code through stage hooks or
prechecks. Do not rely on tribal knowledge.

## Endpoint and Ingress Rules

Any new externally reachable application added via Terraform must also have its
edge configuration represented in code:

- Nginx Proxy Manager tfvars under `/mnt/eapp/.tfvars/nginx-proxy-manager/`
- Cloudflare tfvars under `/mnt/eapp/.tfvars/cloudflare/`

Use explicit per-app hostnames and records. Do not treat the wildcard DNS entry
as enough for new application onboarding.

Default new app DNS targets to internal RFC1918 addresses unless a human
explicitly asks for public exposure.

Do not leave external routing as manual-only UI work.

For BitTorrent clients, do not use HTTP reverse proxy routing for peer traffic.
That traffic must be handled with direct L4 forwarding and matching FortiGate
configuration in code.

## Change Safety Rules

- Do not use Terraform `moved` blocks in this repo unless the task explicitly
  calls for them.
- Ignore unrelated modified or untracked files from other agents.
- Never perform destructive dataset actions from Terraform or shell.
- Keep all networking, FortiGate, DNS, proxy, and ingress changes represented
  in repo code so they survive reconciliation.

## Known Exceptions

These are valid existing exceptions, not patterns to copy by default:

- `terraform/cluster/proxmox/app` uses `variable.tf`
- `terraform/swarm/vault/{app,config}` use fixed input paths
- `terraform/swarm/jenkins/agent` is a legacy path that reads controller
  outputs from `terraform/swarm/jenkins-controller/app`
- `terraform/swarm/prometheus/database` prefers
  `/mnt/eapp/.tfvars/prometheus/database.tfvars` but falls back to
  `/mnt/eapp/.tfvars/victoriametrics/app.tfvars`
