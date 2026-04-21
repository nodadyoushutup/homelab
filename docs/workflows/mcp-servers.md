# MCP Server Workflow

This document defines the operator workflow for changing MCP servers in this
repo. Use
[`docs/rules/mcp-servers.md`](./../rules/mcp-servers.md) for the steady-state
rules and [`docs/workflows/terraform.md`](./terraform.md) for the shared
Terraform execution behavior that the remaining Swarm stages inherit.

## Scope

Use this workflow for:

- `kubernetes/mcp-ast-grep`
- `kubernetes/mcp-argocd`
- `kubernetes/mcp-atlassian`
- `kubernetes/mcp-bash-pipeline`
- `kubernetes/mcp-cloudflare`
- `kubernetes/mcp-fortigate`
- `kubernetes/mcp-git`
- `kubernetes/mcp-github`
- `kubernetes/mcp-google-workspace`
- `kubernetes/mcp-kubernetes`
- `kubernetes/mcp-filesystem`
- `kubernetes/mcp-terraform`

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

Before committing `kubernetes/mcp-argocd/`:

- confirm the upstream image reference in
  `kubernetes/mcp-argocd/deployment.yaml` still exists in GHCR
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains a `k8s/mcp_argocd`
  payload with `argocd_base_url`, `argocd_api_token`, `mcp_read_only`, and the
  current `argocd_insecure_skip_verify` posture
- bootstrap the namespace-local Vault reader secret
  `mcp-argocd-vault-reader` before expecting External Secrets to sync
- confirm the existing hostname route for
  `https://mcp.argocd.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration

### `mcp-atlassian`

Before committing `kubernetes/mcp-atlassian/`:

- confirm the upstream image reference in
  `kubernetes/mcp-atlassian/deployment.yaml` still exists in GHCR
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains a
  `k8s/mcp_atlassian` payload with Jira and Confluence URLs, usernames, API
  tokens, and the current scope-filter values if the service should stay
  narrowed
- bootstrap the namespace-local Vault reader secret
  `mcp-atlassian-vault-reader` before expecting External Secrets to sync
- confirm the full-access posture is still intentional for the current task and
  environment because the deployed server will expose mutating Jira and
  Confluence tools to clients
- confirm the existing hostname route for
  `https://mcp.atlassian.nodadyoushutup.com/mcp` still points at the intended
  ingress entrypoint, because the client-facing URL is preserved during the
  migration

### `mcp-ast-grep`

Before committing `kubernetes/mcp-ast-grep/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-ast-grep/deployment.yaml` exists or will be published in the
  same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_ast_grep` registry credentials for the `ExternalSecret`
- confirm the NFS export `192.168.1.100:/mnt/eapp/code` is still the intended
  read-only workspace mount for the pod
- confirm the pod runtime UID/GID `1000:1000` can read that root-squashed
  workspace path
- rebuild the image first if `applications/mcp-ast-grep/` changed
- keep the ast-grep config aligned with the repo’s real file mix before adding
  custom language parsers; use custom parser plugins only where built-in
  language support plus globs are insufficient
- confirm the existing hostname route for
  `https://mcp.ast-grep.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration
- update the repo-local `.codex/config.toml` entry only if the hostname, MCP
  path, or `http_headers.x-workspace-root` value changes

### `mcp-cloudflare`

Before committing `kubernetes/mcp-cloudflare/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-cloudflare/deployment.yaml` exists or will be published in
  the same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_cloudflare` app and registry credentials for the `ExternalSecret`
- confirm `cloudflare_api_token` and `cloudflare_zone_id` match the target zone
- bootstrap the namespace-local Vault reader secret
  `mcp-cloudflare-vault-reader` before expecting External Secrets to sync
- confirm the existing hostname route for
  `https://mcp.cloudflare.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration
- rebuild and republish the image first if `applications/mcp-cloudflare/` changed

### `mcp-filesystem`

Before committing `kubernetes/mcp-filesystem/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-filesystem/deployment.yaml` exists or will be published in
  the same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_filesystem` registry credentials for the `ExternalSecret`
- confirm the NFS export `192.168.1.100:/mnt/eapp/code/homelab` is still the
  intended workspace mount for the pod
- confirm the repo-local `.codex/config.toml` or app MCP config points at the
  stable hostname and that filesystem guidance stays anchored to
  `/mnt/eapp/code/homelab`

### `mcp-git`

Before committing `kubernetes/mcp-git/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-git/deployment.yaml` exists or will be published in the same
  task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_git` registry credentials for the `ExternalSecret`
- confirm the NFS export `192.168.1.100:/mnt/eapp/code` is still the intended
  shared repository mount for the pod
- confirm the repo-local `.codex/config.toml` entry points at the stable
  hostname and that `http_headers.x-workspace-root` still matches the intended
  workspace root

### `mcp-fortigate`

Before committing `kubernetes/mcp-fortigate/`:

- confirm the GHCR image tag referenced in
  `kubernetes/mcp-fortigate/deployment.yaml` exists
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains a
  `k8s/mcp_fortigate` payload with `ghcr_username`, `ghcr_password`, plus
  either `fortigate_api_token` or both `fortigate_username` and
  `fortigate_password`
- bootstrap the namespace-local Vault reader secret
  `mcp-fortigate-vault-reader` before expecting External Secrets to sync
- confirm the deployment env in `kubernetes/mcp-fortigate/deployment.yaml`
  still matches the intended FortiGate host, port, VDOM, TLS verify posture,
  and timeout before push
- confirm the existing hostname route for
  `https://mcp.fortigate.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration
- rebuild and republish the image first if `applications/mcp-fortigate/` changed

### `mcp-github`

Before committing `kubernetes/mcp-github/`:

- confirm the image tag referenced in `kubernetes/mcp-github/deployment.yaml`
  exists in GHCR
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains a `k8s/mcp_github`
  payload with `github_personal_access_token`, `ghcr_registry`,
  `ghcr_username`, and `ghcr_password`
- bootstrap the namespace-local Vault reader secret
  `mcp-github-vault-reader` before expecting External Secrets to sync
- confirm the existing hostname route for
  `https://mcp.github.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration
- rebuild and republish the image first if `applications/mcp-github/` changed

### `mcp-google-workspace`

Before committing `kubernetes/mcp-google-workspace/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-google-workspace/deployment.yaml` exists or will be
  published in the same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_google_workspace` app and registry credentials plus the delegated
  service-account JSON payload
- bootstrap the namespace-local Vault reader secret
  `mcp-google-workspace-vault-reader` before expecting External Secrets to sync
- confirm `workspace_delegated_user` is still the intended impersonated user
  email and that `workspace_tool_tier` and `workspace_read_only` preserve the
  existing access posture
- confirm the existing hostname route for
  `https://mcp.google-workspace.nodadyoushutup.com/mcp` will move to the
  Kubernetes ingress entrypoint, because the client-facing URL is preserved
  during the migration
- rebuild and republish the image first if
  `applications/mcp-google-workspace/` changed

### `mcp-kubernetes`

Before committing `kubernetes/mcp-kubernetes/`:

- confirm `quay.io/containers/kubernetes_mcp_server:v0.0.60` is still the intended upstream release
- keep the deployment on the upstream native HTTP server; do not add a repo-local proxy unless the upstream transport model regresses
- keep the pod on a dedicated in-cluster ServiceAccount bound to the built-in read-only `view` ClusterRole instead of mounting a static kubeconfig
- keep `mcp_read_only = true` unless the task explicitly requires mutating Kubernetes tools
- keep the initial toolset narrow unless the task explicitly needs more than `core,config`

### `mcp-bash-pipeline`

Before committing `kubernetes/mcp-bash-pipeline/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-bash-pipeline/deployment.yaml` exists or will be published in
  the same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_bash_pipeline` registry credentials for the `ExternalSecret`
- confirm the NFS exports for both `/mnt/eapp/code` and `/mnt/eapp/.tfvars`
  are reachable from the selected Kubernetes worker and still represent the
  intended runtime inputs
- confirm the configured runtime UID/GID can read and execute files from the
  mounted workspace path and read the mounted tfvars path inside the pod
- rebuild the image first if `applications/mcp-bash-pipeline/` changed
- confirm the existing hostname route for
  `https://mcp.bash-pipeline.nodadyoushutup.com/mcp` will move to the
  Kubernetes ingress entrypoint, because the client-facing URL is preserved
  during the migration
- update the repo-local `.codex/config.toml` entry if the hostname, MCP path,
  or workspace headers change

### `mcp-terraform`

Before committing `kubernetes/mcp-terraform/`:

- confirm the Harbor image tag referenced in
  `kubernetes/mcp-terraform/deployment.yaml` exists or will be published in the
  same task
- confirm the Harbor project and the Kubernetes pull robot entry exist in
  `/mnt/eapp/.tfvars/harbor/config.tfvars`
- confirm `/mnt/eapp/.tfvars/vault/config.tfvars` contains the matching
  `k8s/mcp_terraform` app and registry credentials for the `ExternalSecret`
- bootstrap the namespace-local Vault reader secret
  `mcp-terraform-vault-reader` before expecting External Secrets to sync
- confirm the intended `toolsets`, `enable_tf_operations`, `mcp_cors_mode`, and
  optional HCP Terraform or Terraform Enterprise credentials still match the
  desired access posture before push
- confirm the existing hostname route for
  `https://mcp.terraform.nodadyoushutup.com/mcp` will move to the Kubernetes
  ingress entrypoint, because the client-facing URL is preserved during the
  migration
- rebuild and republish the image first if `applications/mcp-terraform/`
  changed

## Apply

Run the stage through its platform owner:

For Swarm MCP servers:

```bash
terraform/swarm/<service>/app/pipeline/app.sh
```

For Kubernetes MCP servers, commit and push the manifests and let Argo CD
autosync them:

```bash
git add kubernetes/<service> kubernetes/argocd-management/<service>-*.yaml docs/...
git commit -m "<service>: migrate to kubernetes"
git push
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

1. confirm the service converged with the platform-appropriate control plane:
   `docker service ps <service>` for Swarm or `kubectl get pods -n <namespace>`
   for Kubernetes
2. confirm the runtime listener is reachable from the platform edge:
   published port on the Swarm ingress node or Kubernetes service/ingress path
3. if the service exposes an explicit MCP HTTP path, probe that path with the
   same transport assumptions the healthcheck uses
4. if the service is meant to be host-reachable, validate the final hostname
   and MCP path that the matching Codex config layer points to
5. if the change touched credentials or provider reachability, verify one real
   tool call through the MCP endpoint before closing the task

Validation examples:

- `mcp-argocd`: probe `https://mcp.argocd.nodadyoushutup.com/mcp` with an
  `mcp-session-id` header
- `mcp-atlassian`: probe `https://mcp.atlassian.nodadyoushutup.com/mcp`
- `mcp-ast-grep`: probe `https://mcp.ast-grep.nodadyoushutup.com/mcp`
- `mcp-filesystem`: probe `https://mcp.filesystem.nodadyoushutup.com/mcp/`
- `mcp-git`: probe `https://mcp.git.nodadyoushutup.com/mcp`
- `mcp-fortigate`: probe `https://mcp.fortigate.nodadyoushutup.com/mcp`
- `mcp-kubernetes`: probe `https://mcp.kubernetes.nodadyoushutup.com/mcp`
- `mcp-bash-pipeline`: probe `https://mcp.bash-pipeline.nodadyoushutup.com/mcp`
- `mcp-terraform`: probe `https://mcp.terraform.nodadyoushutup.com/mcp`
- `mcp-cloudflare`: probe `https://mcp.cloudflare.nodadyoushutup.com/mcp`
- `mcp-google-workspace`: probe
  `https://mcp.google-workspace.nodadyoushutup.com/mcp`
- `mcp-github`: probe `https://mcp.github.nodadyoushutup.com/mcp`
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
