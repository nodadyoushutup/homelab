# Terraform Workflows

This document describes how Terraform is actually used in this repo. Use
[docs/rules/terraform.md](./../rules/terraform.md) for structure and guardrails.
If the first question is whether a new app belongs in Swarm or Kubernetes,
start with [docs/workflows/new-application.md](./new-application.md).
Use [docs/workflows/application-networking.md](./application-networking.md) for
the standard domain, DNS, and reverse-proxy flow.
If the target service is one of the Swarm-hosted MCP servers, also use
[docs/workflows/mcp-servers.md](./mcp-servers.md).

## Standard Execution Model

Terraform is normally executed through canonical stage entrypoint scripts under
`pipelines/terraform/<type>/<service>/<stage>.sh`. Those entrypoints delegate
to `scripts/terraform/swarm_pipeline.sh`, which handles:

1. environment checks
2. tfvars/backend resolution
3. `terraform init`
4. `terraform plan`
5. `terraform apply`

The common operator pattern is:

```bash
pipelines/terraform/<type>/<service>/<stage>.sh
```

Legacy wrappers under `terraform/<type>/<service>/<stage>/pipeline/<stage>.sh`
still forward to the canonical scripts so existing bash callers keep working
during the migration.

Examples:

```bash
pipelines/terraform/swarm/grafana/database.sh
pipelines/terraform/swarm/grafana/app.sh
pipelines/terraform/swarm/grafana/config.sh
pipelines/terraform/network/fortigate/config.sh
pipelines/terraform/remote/cloudflare/config.sh
```

## Before You Run a Stage

1. Identify the correct stage or stage sequence.
2. Confirm the matching tfvars file exists under `/mnt/eapp/config`.
3. Confirm the backend config exists, normally `/mnt/eapp/config/minio.backend.hcl`.
4. Check whether the stage has custom preflight or post-init hooks.
5. If the change introduces an endpoint, include the matching Nginx Proxy
   Manager and Cloudflare changes in the same workflow.

The usual stage order is:

- `database -> app -> config` when runtime depends on stateful prerequisites
- `app -> config` when config stages call a running service API

## Normal Stage Invocation

Most stages can be run with no arguments:

```bash
pipelines/terraform/swarm/grafana/app.sh
```

Most stages also accept optional overrides:

```bash
pipelines/terraform/swarm/grafana/app.sh \
  --tfvars /mnt/eapp/config/grafana/app.tfvars \
  --backend /mnt/eapp/config/minio.backend.hcl
```

Positional arguments are also supported:

```bash
pipelines/terraform/swarm/grafana/app.sh \
  /mnt/eapp/config/grafana/app.tfvars \
  /mnt/eapp/config/minio.backend.hcl
```

Do not assume every stage accepts overrides. `vault` intentionally rejects them.

## What the Shared Wrapper Does

The shared wrapper handles the repeatable Terraform lifecycle:

1. `scripts/terraform/env_check.sh` verifies `terraform`, `realpath`, and a
   Python interpreter for filtered output.
2. `scripts/terraform/resolve_inputs.sh` resolves tfvars and backend paths.
3. `scripts/terraform/terraform_exec.sh` runs Terraform, optionally through the
   output filter helper.
4. `terraform init -backend-config=...`
5. `terraform plan -input=false -var-file ...`
6. `terraform apply -input=false -auto-approve -var-file ...`

If Terraform reports a backend change during init, the wrapper will try:

1. `terraform init -force-copy -migrate-state`
2. `terraform init -reconfigure`

That behavior is built into the shared wrapper, so operators normally do not
handle that manually.

## Common Workflow Patterns

### Deploy a new or updated service

1. Update the Terraform code in the relevant stage directories.
2. Update the matching tfvars under `/mnt/eapp/config`.
3. Run the dependent stages in order.
4. Validate the runtime after each stage that changes live infrastructure.
5. If the service exposes an endpoint, run the matching edge stages too.

Example:

```bash
pipelines/terraform/swarm/harbor/app.sh
pipelines/terraform/swarm/harbor/config.sh
pipelines/terraform/swarm/nginx_proxy_manager/config.sh
pipelines/terraform/remote/cloudflare/config.sh
```

### Update app config that talks to a live API

Some `config` stages only make sense after the app is running. In those cases:

1. run the `app` stage first
2. verify the service is reachable/authenticated
3. run the `config` stage

Examples in the repo include `grafana`, `harbor`, `jenkins-controller`, and
`nginx_proxy_manager`.

For Jenkins specifically:

- `pipelines/terraform/swarm/jenkins-controller/app.sh` should run before
  `pipelines/terraform/swarm/jenkins-agent-arm64/app.sh` and
  `pipelines/terraform/swarm/jenkins-agent-amd64/app.sh`
- Terraform Jenkins jobs pass optional `TFVARS_FILE` and `BACKEND_FILE`
  overrides through `scripts/terraform/jenkins_stage_runner.sh`; leave those
  parameters empty to use normal auto-discovery
- add or update repo-tracked `*.jenkins` files under `pipelines/` when a stage
  should become a Jenkins job; keep the existing `.sh` entrypoint as the stage
  source-of-truth that the Jenkins wrapper executes
- `pipelines/terraform/swarm/jenkins-controller/config.sh` reconciles the
  Terraform-managed Jenkins folders, multibranch XML job definitions, optional
  SCM checkout credential for private GitHub access, and branch discovery
  filters for each repo-tracked `*.jenkins` path
- each multibranch parent job indexes the repository for branches that contain
  its configured `*.jenkins` script path; use the Jenkins controller config
  tfvars include and exclude wildcards to narrow branch discovery when needed
- the split Jenkins agent app stages validate that the configured `agent_image`
  manifest actually contains the expected target architecture before Terraform
  apply proceeds
- the controller app stage writes inbound agent secret files under
  `/mnt/eapp/config/jenkins-controller/agent-secrets/`
- both controller and agent containers expect the shared `/mnt/eapp/config`
  mount to be present
- when Jenkins-side auto-discovery fails, verify the running `jenkins-agent-arm64`
  and `jenkins-agent-amd64` services both still bind-mount host
  `/mnt/eapp/config` to container `/mnt/eapp/config`

### Run a stage with custom safety hooks

Some stages inject repo-specific safeguards:

- `vault/app` performs SSH-based port preflight checks, runs a bootstrap
  script, and validates the Vault health endpoint after apply
- `grafana/database` and `nginx_proxy_manager/{database,config}` force
  `-parallelism=1`
- `talos/app` uses hook logic and extra Terraform args for node replacement

If a stage has custom hooks, follow that stage's actual script rather than
assuming the generic wrapper is the full story.

## Validation After Apply

Validation should match the stage type:

- `database`: confirm the dependency exists and is reachable by the consumer
- `app`: confirm the workload or service is running and reachable
- `config`: confirm the remote system accepted the desired configuration
- `network` and `remote`: confirm the target record, VIP, policy, or proxy host
  exists in the target system

Typical examples:

- open the service URL or API after an `app` stage
- verify DNS or proxy host behavior after Cloudflare or NPM config
- confirm FortiGate VIP/policy behavior after network changes

## State Audit And Repair

When Jenkins and shell entrypoints disagree with reality, treat remote state as
the first thing to audit. The shared backend is what makes bash and Jenkins
interchangeable for a given stage.

Audit all Terraform stages against remote state with:

```bash
scripts/terraform/audit_remote_state.sh
```

Use `--only` to narrow the audit to one service or stage:

```bash
scripts/terraform/audit_remote_state.sh --only 'grafana/config'
```

Interpret the audit like this:

- `IN_SYNC`: all defined resource addresses exist in remote state
- `STATE_EMPTY`: code defines resources but the remote state object is empty
- `MISSING_STATE`: some code-defined resources are missing from remote state
- `ORPHANED_STATE`: remote state still contains resources no longer defined in code
- `PARTIAL`: both missing and orphaned entries exist

For Grafana `config`, existing folders, data sources, and dashboards can be
reconciled into remote state with:

```bash
scripts/terraform/grafana_config_import_existing.sh
```

Use `--dry-run` first if you want to inspect the import commands before they
touch shared state.

After any import repair, rerun the stage through either bash or Jenkins and
confirm both paths now produce the same plan against the same remote state.

## Endpoint Changes

When a Terraform change creates or modifies an externally exposed app:

1. update the service Terraform
2. update Nginx Proxy Manager tfvars
3. update Cloudflare tfvars
4. run the required stage pipelines
5. validate the final hostname with `curl` or equivalent

Default the DNS target to an internal RFC1918 address unless a human explicitly
asks for public exposure.

Do not rely on only the wildcard record for a new app hostname.

For torrent-related services, do not use this HTTP endpoint flow for peer
traffic. Use direct L4 forwarding and validate the port mapping end to end.

## Failure Handling

If a stage fails:

1. stop at the failing stage
2. read the stage script for custom hooks or fixed-path behavior
3. correct code or tfvars
4. rerun the same stage
5. only continue to later stages after the failing dependency stage succeeds

Do not skip straight to a `config` stage if its `app` or `database`
dependencies are still broken.

## Kubernetes and Argo CD Tie-In

Some Terraform work manages Kubernetes delivery rather than workloads directly.
The main example is Argo CD management under `terraform/cluster/argocd/config`.

Use that stage when the change belongs to Terraform-managed Argo CD resources.
Use [docs/workflows/argocd.md](./argocd.md) and the Kubernetes workflow for
changes under `kubernetes/` that are delivered by Argo CD after Git
reconciliation.
