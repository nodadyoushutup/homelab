# Swarm MCP Server Workflow

This document defines the operator workflow for changing the MCP servers that
run in Docker Swarm in this repo. Use
[`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) for the steady-state
rules and [`docs/workflows/terraform.md`](./terraform.md) for the shared
Terraform execution behavior that these stages inherit.

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
- `terraform/swarm/mcp-agent-protocol/app`

## Standard Flow

When a task changes one of the Swarm-hosted MCP servers:

1. identify the target service and read its section in
   `docs/rules/mcp-servers.md`
2. inspect whether the service uses an upstream image or a repo-local wrapper
   under `applications/<service>/`
3. if the service is custom or the upstream is stdio-only, make sure there is a
   repo-local HTTP-capable wrapper under `applications/<service>/`
4. update the Terraform app root and, if needed, the local image wrapper
5. update the matching tfvars and companion credential assets under
   `/mnt/eapp/.tfvars/<service>/`
6. update the matching Nginx Proxy Manager and Cloudflare hostname entries when
   the server is meant to be reachable from the host Codex client
7. update the matching Codex config layer when the MCP hostname set changes or
   a new server is added:
   - `~/.codex/config.toml` for shared/global servers
   - repo-local `.codex/config.toml` for workspace-specific servers
8. make sure the exact image tag referenced by Terraform exists where the Swarm
   engine can pull it
9. run the app stage pipeline
10. run the edge pipelines if the hostname or route changed
11. validate the live service by the same hostname the host Codex config uses
12. update docs if the stable MCP pattern changed

These services are single-stage Swarm apps, but host-reachable MCP delivery is
not complete until the domain route and host Codex config are aligned too.

## Shared Preflight

Before running the pipeline:

1. confirm the stage root is `terraform/swarm/<service>/app`
2. confirm `/mnt/eapp/.tfvars/<service>/app.tfvars` exists
3. confirm `/mnt/eapp/.tfvars/minio.backend.hcl` exists unless you are
   intentionally overriding it
4. confirm any local secret file paths in tfvars exist on the Terraform runner
5. if the service should be host-reachable, decide the final hostname and MCP
   path before touching the host Codex config
6. if the service uses a custom image wrapper, build and publish or otherwise
   preload the image tag referenced in Terraform

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

### `mcp-agent-protocol`

Before running `terraform/swarm/mcp-agent-protocol/app/pipeline/app.sh`:

- confirm the local image tag in Terraform exists on `swarm-cp-0`
- confirm `/mnt/eapp/.tfvars/mcp-agent-protocol/app.tfvars` exists with the
  intended key prefix or TTL overrides
- keep Redis internal to the service overlay unless the task explicitly needs a
  different exposure model
- rebuild the image first if `applications/mcp-agent-protocol/` changed

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
- `mcp-filesystem-homelab`: probe `http://<swarm-host>:18098/mcp`
- `mcp-git-homelab`: probe `http://<swarm-host>:18099/mcp`
- `mcp-fortigate`: probe `http://<swarm-host>:18084/mcp`
- `mcp-agent-protocol`: probe `http://<swarm-host>:18100/mcp`
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
