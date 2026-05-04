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

- `terraform/swarm/jenkins-agent-arm64/app`
- `terraform/swarm/jenkins-agent-amd64/app`
- `terraform/swarm/jenkins-controller/app`
- `terraform/swarm/jenkins-controller/config`

## Required Stage Files

New stage directories should follow this pattern:

```text
terraform/<type>/<service>/<stage>/
  main.tf
  provider.tf
  variables.tf

pipelines/terraform/<type>/<service>/<stage>.sh
```

Additional files are fine when they are part of the implementation, for example:

- `outputs.tf`
- `data.tf`
- `*.tftpl`
- stage-local JSON payloads such as dashboards

Use `variables.tf` for new work. A few older directories still use
`variable.tf`; treat those as legacy, not the pattern to copy.

## Pipeline Conventions

Every stage is expected to have one canonical entrypoint script under
`pipelines/terraform/<type>/<service>/<stage>.sh`. That script defines the
stage metadata and then sources the shared wrapper at
`scripts/terraform/swarm_pipeline.sh`.

Terraform-backed Jenkins jobs should keep their Groovy wrapper thin and invoke
the stage through `scripts/terraform/jenkins_stage_runner.sh` so unset optional
`TFVARS_FILE` and `BACKEND_FILE` parameters do not break auto-discovery under
`set -u`.

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

Default tfvars live under `/mnt/eapp/config`. The common pattern is:

- `/mnt/eapp/config/<service>/app.tfvars`
- `/mnt/eapp/config/<service>/config.tfvars`
- `/mnt/eapp/config/<service>/database.tfvars`

Some services intentionally use a different basename. Existing examples include:

- `nginx_proxy_manager` Terraform paths paired with `config/nginx-proxy-manager/...`
- single-stage services that resolve to `/mnt/eapp/config/<service>.tfvars`

The default backend file is usually:

- `/mnt/eapp/config/minio.backend.hcl`

`CONFIG_DIR` is the canonical shared configuration root. The shared scripts
resolve tfvars home like this:

- `TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}"`

For Terraform stages that reach Docker Swarm over SSH, keep the SSH material in
the shared configuration root instead of a workstation-local home directory:

- private key: `/mnt/eapp/config/.ssh/id_ed25519`
- known hosts: `/mnt/eapp/config/.ssh/known_hosts`

Prefer explicit `ssh_opts` in tfvars that point at those shared paths so Swarm
deploys do not depend on whichever local `~/.ssh` state happens to be present
on the runner.

Also keep the SSH target itself portable across runners:

- prefer an explicit remote user in `host = "ssh://user@host"`
- prefer a container-resolvable IP or standard DNS name over mDNS-only
  `.local` hostnames

`scripts/terraform/load_root_env.sh` preserves already-exported values for:

- `CONFIG_DIR`
- `TFVARS_HOME_DIR`
- `JENKINS_AGENT_TFVARS_DIR`
- `JENKINS_TFVARS_DIR`
- `JENKINS_CONTROLLER_TFVARS_DIR`

Jenkins-specific defaults remain special cases:

- `JENKINS_AGENT_ARM64_TFVARS_DIR` defaults to
  `${CONFIG_DIR}/jenkins-agent-arm64`
- `JENKINS_AGENT_AMD64_TFVARS_DIR` defaults to
  `${CONFIG_DIR}/jenkins-agent-amd64`
- `JENKINS_AGENT_TFVARS_DIR` remains a backward-compat passthrough when
  explicitly exported, but new Jenkins agent work should use the arch-specific
  directories above
- `JENKINS_CONTROLLER_TFVARS_DIR` defaults to `${CONFIG_DIR}/jenkins-controller`
- Jenkins controller and agent secret handoff now defaults to the shared
  configuration root mounted at `/mnt/eapp/config`, with controller-written
  secret files under `/mnt/eapp/config/jenkins-controller/agent-secrets/`
- Jenkins controller JCasC now defaults to the literal YAML companion file
  `/mnt/eapp/config/jenkins-controller/jenkins.yaml`, and the Jenkins agent
  stages read that same file to derive inbound agent service definitions
- Split Jenkins agent stages should filter that shared JCasC node set by
  architecture label tokens such as `arm64` and `amd64`, while keeping
  hostname placement in the same YAML source-of-truth
- The same shared Jenkins JCasC YAML is also the source-of-truth for each
  agent node's `numExecutors`, so collapsing a pool from many `1`-executor
  nodes into one multi-executor node should be done there rather than by
  changing the Terraform service replica count
- Split Jenkins agent stage entrypoints should fail fast when the Terraform-
  defined Jenkins agent image manifest does not advertise the required target
  architecture, using the same stage `registry_auth` credentials when the
  registry requires authentication
- Jenkins controller `config` is the Terraform-managed Jenkins API stage for
  folders, multibranch jobs, and optional SCM checkout credentials
- Jenkins controller and agent services should mount `/mnt/eapp/config`
  through Docker-managed NFS-backed volumes that point at the shared export on
  `192.168.1.100:/mnt/eapp/config`, rather than relying on a host bind mount on
  every Swarm node
- GitHub Actions runner services that need shared repo configuration should use
  the same Docker-managed NFS-backed `/mnt/eapp/config` mount pattern instead
  of host bind mounts so the service remains portable across Swarm nodes
- Jenkins agent node entries in that YAML should use `nodeDescription` for the
  target Swarm hostname when the agent stage needs deterministic per-service
  placement from the same source-of-truth file
- Jenkins jobs should be defined as repo-tracked `*.jenkins` files under
  `pipelines/`; the Jenkins controller config stage mirrors the directory tree
  beneath that root into Jenkins folders and renders multibranch job XML from
  templates under `terraform/swarm/jenkins-controller/config/job/`
- each repo-tracked `*.jenkins` file becomes one multibranch parent job whose
  `scriptPath` points at that file, so Jenkins indexes matching branches in the
  repository instead of pinning every job to one shared branch
- multibranch branch discovery should use wildcard include and exclude filters
  from the Jenkins controller config tfvars; keep scanning manually triggered
  unless a human explicitly asks for scheduled indexing or webhooks
- Terraform Jenkins jobs should rely on the shared `/mnt/eapp/config`
  Docker-managed NFS-backed volume for tfvars and backend auto-discovery, and
  should fail with an explicit mount error when that directory is absent inside
  the runner
- Keep those Terraform-managed Jenkins jobs manually triggered unless a human
  explicitly asks for webhooks, SCM polling, or scheduled triggers

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

`/mnt/eapp/config/<service>/` can include more than `*.tfvars` files. Companion
assets such as `config.yaml`, `grafana.ini`, `service_account.json`, cloud-init
YAML, or Talos patch files are normal when a stage consumes them.

For Talos specifically, treat the shared `/mnt/eapp/config/talos/` directory as
the durable runtime handoff path for:

- node patch YAML files consumed by the stage
- the managed `talosconfig` and `kubeconfig` outputs used by non-interactive
  runners such as Jenkins

Do not rely on a long-lived `secrets.yaml` migration bundle in shared config.
The Talos app stage exports a temporary machine-secrets import file from a
working Talos client config only when it needs to repair
`talos_machine_secrets.cluster`.

The Jenkins controller and agents also use the shared `/mnt/eapp/config`
mount as their runtime handoff path for inbound agent secret files. Treat that
Jenkins-owned subdirectory as runtime configuration data, not as a generic dump
location for unrelated service state.

Jenkins also uses a repo-external companion YAML file at
`/mnt/eapp/config/jenkins-controller/jenkins.yaml` as the source-of-truth
Configuration as Code document. Keep controller security, location, and node
definitions in that file rather than re-encoding them inline in Terraform.
That includes whether an architecture pool is modeled as several `1`-executor
nodes or one node with multiple executors.

## Backend State Naming

Each stage must have a unique backend key in `provider.tf`.

Patterns already used in this repo:

- single-stage service: `<service>.tfstate`
- multi-stage service: `<service>-<stage>.tfstate`

Do not share one state file across multiple stages.

The remote backend object for that stage is the shared source-of-truth for both
shell and Jenkins execution. If a stage plans to create resources that already
exist remotely, treat that as a state reconciliation problem first, not as a
reason to bypass the backend.

## New Swarm Work

For new Docker Swarm applications:

- define resources directly under `terraform/swarm/<service>/<stage>`
- do not create new `terraform/module/<service>` abstractions
- do not abstract container images into locals
- keep the image directly in the resource definition

This is current repo policy, not a suggestion.

## Swarm Purge Scripts

Canonical Swarm purge scripts live under `scripts/docker/purge/`.

- Keep one canonical purge script at `scripts/docker/purge/<service>.sh` for
  each active runtime root under `terraform/swarm/<service>/`.
- Match the canonical purge script name to the Terraform service path name, even
  when Docker object names use hyphens instead of underscores.
- Use service-specific regex or filter overrides in that script when a service
  owns related assets from multiple stages, such as app and database resources.
- Compatibility alias scripts are allowed, but `scripts/docker/purge/purge.sh
  all` should iterate only the canonical active runtime roots to avoid duplicate
  purges.

## Naming Rules

Match existing service naming instead of trying to normalize the whole tree.
The repo intentionally has both hyphenated and underscored names depending on
the implementation history and external system naming.

Examples:

- Terraform path: `terraform/swarm/nginx_proxy_manager/...`
- tfvars path: `/mnt/eapp/config/nginx-proxy-manager/...`
- Terraform path: `terraform/swarm/node_exporter/...`

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

- Nginx Proxy Manager tfvars under `/mnt/eapp/config/nginx-proxy-manager/`
- Cloudflare tfvars under `/mnt/eapp/config/cloudflare/`

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
- `terraform/swarm/prometheus/database` prefers
  `/mnt/eapp/config/prometheus/database.tfvars` but falls back to
  `/mnt/eapp/config/victoriametrics/app.tfvars`
