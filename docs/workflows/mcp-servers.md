# MCP Server Workflow

This document defines the operator workflow for changing MCP servers in this
repo. Use
[`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) for the steady-state
rules and [`docs/workflows/terraform.md`](./terraform.md) for the shared
Terraform execution behavior that the Swarm stages inherit.

## Scope

Use this workflow for:

- `terraform/swarm/mcp-argocd/app`
- `terraform/swarm/mcp-atlassian/app`
- `terraform/swarm/mcp-ast-grep/app`
- `terraform/swarm/mcp-cloudflare/app`
- `terraform/swarm/mcp-filesystem-homelab/app`
- `terraform/swarm/mcp-git-homelab/app`
- `terraform/swarm/mcp-fortigate/app`
- `terraform/swarm/mcp-github/app`
- `terraform/swarm/mcp-google-workspace/app`
- `terraform/swarm/mcp-kubernetes/app`
- `terraform/swarm/mcp-redis/app`
- `terraform/swarm/mcp-agent-protocol/app`
- `terraform/swarm/mcp-bash-pipeline/app`
- `terraform/swarm/mcp-terraform/app`
- `kubernetes/mcp-filesystem`

## Standard Flow

When a task changes an MCP server:

1. identify the target service, platform, and read its section in
   `docs/rules/mcp-servers.md`
2. inspect whether the service uses an upstream image or a repo-local wrapper
   under `applications/<service>/`
3. if the service is custom or the upstream is stdio-only, make sure there is
   a repo-local HTTP-capable wrapper under `applications/<service>/`
4. update the platform runtime root:
   - `terraform/swarm/<service>/app` for Swarm services
   - `kubernetes/<service>/` plus `kubernetes/argocd-management/` for
     Kubernetes services
5. update the matching tfvars and companion credential assets when the service
   needs them:
   - `/mnt/eapp/.tfvars/<service>/` for Swarm runtime inputs
   - `/mnt/eapp/.tfvars/harbor/config.tfvars` for Harbor projects and robots
   - `/mnt/eapp/.tfvars/vault/config.tfvars` for Kubernetes registry or app
     secrets consumed through External Secrets
6. update the matching Nginx Proxy Manager and Cloudflare hostname entries when
   the server is meant to be reachable from the host Codex client
7. update the matching Codex config layer when the MCP hostname set changes or
   a new server is added:
   - `~/.codex/config.toml` for shared/global servers
   - repo-local `.codex/config.toml` for workspace-specific servers
8. make sure the exact referenced image tag exists in the target registry or
   runtime before deploy
9. apply the platform change:
   - run the Swarm app stage pipeline for Swarm services
   - commit and push the Kubernetes manifests, then let Argo CD sync
10. run the edge pipelines if the hostname or route changed
11. validate the live service by the same hostname the host Codex config uses
12. update docs if the stable MCP pattern changed

Host-reachable MCP delivery is not complete until the domain route and host
Codex config are aligned too.

## Shared Preflight

Before running the pipeline:

1. confirm the platform root is correct for the target service:
   - `terraform/swarm/<service>/app` for Swarm
   - `kubernetes/<service>/` plus `kubernetes/argocd-management/` for
     Kubernetes
2. confirm the matching runtime config inputs exist:
   - `/mnt/eapp/.tfvars/<service>/app.tfvars` for Swarm runtime inputs
   - `/mnt/eapp/.tfvars/vault/config.tfvars` and Harbor config entries for
     Kubernetes registry-backed pulls when used
3. confirm `/mnt/eapp/.tfvars/minio.backend.hcl` exists unless you are
   intentionally overriding it for a Swarm Terraform run
4. confirm any local secret file paths in tfvars exist on the Terraform runner
5. if the service should be host-reachable, decide the final hostname and MCP
   path before touching the host Codex config
6. if the service uses a custom image wrapper, build and publish or otherwise
   preload the referenced image tag

The normal invocation stays the standard Terraform stage entrypoint:

```bash
terraform/swarm/<service>/app/pipeline/app.sh
```

## Service-Specific Preflight

### `mcp-argocd`

Before running `terraform/swarm/mcp-argocd/app/pipeline/app.sh`:

- make sure `kubectl`, `argocd`, and `python3` are available on the operator
  host if `argocd_api_token` is empty, placeholder text, or intentionally left
  for pipeline bootstrap
- make sure the current kube context can reach the `argocd` namespace
- expect the pipeline to enable `accounts.admin: apiKey, login`, restart
  `deployment/argocd-server`, and generate the managed token id
  `mcp-argocd-swarm` when bootstrap is needed

### `mcp-atlassian`

Before running `terraform/swarm/mcp-atlassian/app/pipeline/app.sh`:

- confirm Jira and Confluence URLs, usernames, and API tokens are all present
- confirm the full-access posture is still intentional for the current task and
  environment because the deployed server will expose mutating Jira and
  Confluence tools to clients
- confirm any `jira_projects_filter` or `confluence_spaces_filter` changes are
  intentional because they directly narrow or widen the MCP surface

### `mcp-ast-grep`

Before running `terraform/swarm/mcp-ast-grep/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm the mounted shared code path exists on the Terraform runner and on
  the Swarm node at `/mnt/eapp/code`
- confirm the configured runtime UID/GID can read that NFS-mounted workspace
  path on the Swarm node
- rebuild the image first if `applications/mcp-ast-grep/` changed
- keep the ast-grep config aligned with the repo’s real file mix before adding
  custom language parsers; use custom parser plugins only where built-in
  language support plus globs are insufficient
- update the repo-local `.codex/config.toml` entry if the hostname, MCP path,
  or `http_headers.x-workspace-root` value changes

### `mcp-cloudflare`

Before running `terraform/swarm/mcp-cloudflare/app/pipeline/app.sh`:

- confirm the custom image tag in Terraform exists in Harbor
- confirm `cloudflare_api_token` and `cloudflare_zone_id` match the target zone
- rebuild and republish the image first if `applications/mcp-cloudflare/` changed

### `mcp-filesystem-homelab`

Before running `terraform/swarm/mcp-filesystem-homelab/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm the mounted shared code path exists on the Terraform runner and on
  the Swarm node at `/mnt/eapp/code`
- confirm the configured runtime UID/GID can write to that NFS-mounted
  workspace path on the Swarm node
- rebuild the image first if `applications/mcp-filesystem-homelab/` changed
- update the repo-local `.codex/config.toml` entry if the hostname, MCP path,
  or `http_headers.x-workspace-root` value changes

### `mcp-filesystem`

Before committing `kubernetes/mcp-filesystem/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-filesystem/deployment.yaml` exists or will be published in
  the same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_filesystem` registry credentials for the `ExternalSecret`
- confirm the NFS export `192.168.1.100:/mnt/eapp/code` is still the intended
  shared repo mount for the pod
- confirm the repo-local `.codex/config.toml` entry uses request headers for
  workspace selection and access policy instead of relying on one hard-coded
  server workspace

### `mcp-git-homelab`

Before running `terraform/swarm/mcp-git-homelab/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm the mounted shared code path exists on the Terraform runner and on
  the Swarm node at `/mnt/eapp/code`
- confirm the configured runtime UID/GID can write to that NFS-mounted
  repository path on the Swarm node
- rebuild the image first if `applications/mcp-git-homelab/` changed
- update the repo-local `.codex/config.toml` entry if the hostname, MCP path,
  or `http_headers.x-workspace-root` value changes

### `mcp-fortigate`

Before running `terraform/swarm/mcp-fortigate/app/pipeline/app.sh`:

- confirm the GHCR image tag in Terraform exists
- confirm `fortigate_host` resolves from the Swarm node
- confirm tfvars set either `fortigate_api_token` or both
  `fortigate_username` and `fortigate_password`
- rebuild and republish the image first if `applications/mcp-fortigate/` changed

### `mcp-github`

Before running `terraform/swarm/mcp-github/app/pipeline/app.sh`:

- confirm the GHCR image tag in Terraform exists
- confirm `github_personal_access_token` is present and still valid
- rebuild and republish the image first if `applications/mcp-github/` changed

### `mcp-google-workspace`

Before running `terraform/swarm/mcp-google-workspace/app/pipeline/app.sh`:

- confirm the `homelab/mcp-google-workspace:*` image tag in Terraform exists on
  the Docker engine that will run the service
- confirm `workspace_service_account_file` points at a readable local
  `service_account.json` on the Terraform runner
- confirm `workspace_delegated_user` is the intended impersonated user email
- rebuild the image first if `applications/mcp-google-workspace/` changed

### `mcp-kubernetes`

Before running `terraform/swarm/mcp-kubernetes/app/pipeline/app.sh`:

- confirm `quay.io/containers/kubernetes_mcp_server:v0.0.60` is still the intended upstream release
- confirm the local kubeconfig file referenced by tfvars exists on the Terraform runner
- prefer a dedicated read-only kubeconfig for this service instead of reusing a broad admin kubeconfig
- keep `mcp_read_only = true` unless the task explicitly requires mutating Kubernetes tools
- keep the initial toolset narrow unless the task explicitly needs more than `core,config`

### `mcp-redis`

Before running `terraform/swarm/mcp-redis/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm `/mnt/eapp/.tfvars/mcp-redis/app.tfvars` exists with the intended
  `key_prefix` and safety settings
- keep Redis internal to the service overlay unless the task explicitly needs a
  different exposure model
- rebuild the image first if `applications/mcp-redis/` changed

### `mcp-agent-protocol`

Before running `terraform/swarm/mcp-agent-protocol/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm `/mnt/eapp/.tfvars/mcp-agent-protocol/app.tfvars` exists with the
  intended key prefix or TTL overrides
- keep Redis internal to the service overlay unless the task explicitly needs a
  different exposure model
- rebuild the image first if `applications/mcp-agent-protocol/` changed

### `mcp-bash-pipeline`

Before running `terraform/swarm/mcp-bash-pipeline/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm the mounted shared code path exists on the Terraform runner and on
  the Swarm node at `/mnt/eapp/code`
- confirm `/mnt/eapp/.tfvars/mcp-bash-pipeline/app.tfvars` exists with the
  intended repo mount path, tfvars mount path, and runtime UID/GID
- confirm the matching `/mnt/eapp/.tfvars` subtree is populated on
  `swarm-cp-0` itself, not only on the operator host, because the service bind
  mount reads the node-local path at runtime
- confirm the configured runtime UID/GID can read and execute files from the
  NFS-mounted workspace path on the Swarm node
- rebuild the image first if `applications/mcp-bash-pipeline/` changed
- update the repo-local `.codex/config.toml` entry if the hostname, MCP path,
  or workspace headers change

### `mcp-terraform`

Before running `terraform/swarm/mcp-terraform/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm `/mnt/eapp/.tfvars/mcp-terraform/app.tfvars` exists with the intended
  `toolsets` and optional HCP Terraform or Terraform Enterprise credentials
- rebuild the image first if `applications/mcp-terraform/` changed
- if a browser-based MCP client is part of the task, decide the final
  `mcp_allowed_origins` value before apply instead of widening CORS later by
  hand

## Apply

Run the stage through its pipeline entrypoint:

```bash
terraform/swarm/<service>/app/pipeline/app.sh
```

Use explicit `--tfvars` or `--backend` overrides only when the task calls for a
non-default path. Otherwise use the repo defaults.

If the task also changes the MCP hostname route, apply the edge config after the
service stage:

```bash
terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh
terraform/remote/cloudflare/config/pipeline/config.sh
```

## Validation

After apply:

1. confirm the service converged with `docker service ps <service>`
2. confirm the published port is open on the Swarm ingress node
3. if the service exposes an explicit MCP HTTP path, probe that path with the
   same transport assumptions the healthcheck uses
4. if the service is meant to be host-reachable, validate the final hostname
   and MCP path that the matching Codex config layer points to
5. if the change touched credentials or provider reachability, verify one real
   tool call through the MCP endpoint before closing the task

Validation examples:

- `mcp-argocd`: probe `http://<swarm-host>:18086/mcp` with an
  `mcp-session-id` header
- `mcp-atlassian`: probe `http://<swarm-host>:18080/mcp` with
  `Accept: text/event-stream`
- `mcp-ast-grep`: probe `http://<swarm-host>:18096/mcp`
- `mcp-filesystem`: probe `https://mcp.filesystem.nodadyoushutup.com/mcp/`
  with `x-workspace-name` and `x-mcp-filesystem-access` headers
- `mcp-filesystem-homelab`: probe `http://<swarm-host>:18098/mcp`
- `mcp-git-homelab`: probe `http://<swarm-host>:18099/mcp`
- `mcp-fortigate`: probe `http://<swarm-host>:18084/mcp`
- `mcp-kubernetes`: probe `http://<swarm-host>:18106/mcp`
- `mcp-redis`: probe `http://<swarm-host>:18101/mcp`
- `mcp-agent-protocol`: probe `http://<swarm-host>:18100/mcp`
- `mcp-bash-pipeline`: probe `http://<swarm-host>:18107/mcp`
- `mcp-terraform`: probe `http://<swarm-host>:18104/mcp`
- `mcp-github`, `mcp-cloudflare`, `mcp-google-workspace`: at minimum verify the
  port is listening if the wrapper does not define a fixed explicit path in
  Terraform
- host validation: probe `https://mcp.<service>.nodadyoushutup.com/mcp` from
  the Codex host and make sure the same URL exists in the intended Codex config
  layer (`~/.codex/config.toml` or repo-local `.codex/config.toml`)

## Change Boundaries

- Do not leave a host-usable MCP server on a raw port-only access pattern when
  the stable model is supposed to be hostname-based.
- Do not widen secrets or provider scopes unless the task explicitly requires
  new MCP capabilities.
- If you change the stable operating pattern for any MCP server, update both
  `docs/rules/mcp-servers.md` and this workflow doc in the same task.
