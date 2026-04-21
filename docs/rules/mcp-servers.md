# MCP Server Rules

This document defines the steady-state rules for MCP servers in this repo. Use
[`docs/workflows/mcp-servers.md`](./../workflows/mcp-servers.md) for the
operator flow and [`docs/rules/terraform.md`](./terraform.md) for the shared
Terraform guardrails the remaining Swarm-hosted services also follow.

## Scope

This document applies to the current MCP server set:

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

## Shared Placement Rules

- Existing Swarm-hosted MCP servers stay in `terraform/swarm/<service>/app`
  unless a task explicitly migrates them.
- New MCP servers may use the Kubernetes pattern under `kubernetes/<service>/`
  when the human explicitly chooses the cluster route. Current reference
  exceptions are `kubernetes/mcp-argocd`, `kubernetes/mcp-ast-grep`,
  `kubernetes/mcp-atlassian`, `kubernetes/mcp-bash-pipeline`,
  `kubernetes/mcp-cloudflare`, `kubernetes/mcp-fortigate`,
  `kubernetes/mcp-git`, `kubernetes/mcp-github`,
  `kubernetes/mcp-google-workspace`, `kubernetes/mcp-kubernetes`,
  `kubernetes/mcp-filesystem`, and `kubernetes/mcp-terraform`.
- Each MCP server keeps its own single `app` stage and single backend state
  file. Do not merge multiple MCP services into one Terraform root or one state
  key.
- Swarm services keep the current one-replica control-plane placement pattern:
  `node.labels.role==swarm-cp-0`.
- Swarm services keep their own overlay network named after the service. Do not
  collapse multiple MCP servers onto one shared overlay by default.
- Keep provider-driven registry auth in `provider.tf` when the image comes from
  a private registry or authenticated GHCR path.

## Shared Runtime Rules

- Keep the published or ingress-routed listen path and transport path aligned
  with the actual service wrapper. Do not change ports casually because
  MCP clients and local tooling depend on them.
- Keep an explicit pod or container healthcheck that probes the actual
  listening port
  or HTTP MCP endpoint.
- Keep the standard DNS resolver list in Swarm services unless the runtime
  proves a server-specific need for something else.

## Shared Reachability Rules

- Treat MCP servers as operator apps that must still be HTTP reachable for LLM
  clients running off-platform.
- The standard client path is a stable hostname routed through the repo-managed
  edge config, not a raw Swarm published port copied into a client by hand.
- Keep `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`,
  `/mnt/eapp/.tfvars/cloudflare/config.tfvars`, and the matching Codex config
  layer (`~/.codex/config.toml` for global servers or repo-local
  `.codex/config.toml` for workspace-specific servers) aligned with the final
  service route and MCP HTTP path for every host-usable server.
- The Codex host is not part of the Swarm overlay network or the Kubernetes
  service network. Do not point host MCP config at overlay-only service names,
  cluster-only service DNS, or ad hoc direct ports unless the task explicitly
  documents a temporary fallback.
- These services are operator endpoints, not general public apps. Expose them
  through trusted DNS and reverse-proxy paths for operator and LLM access, but
  do not broaden exposure beyond that without an explicit task requirement.
- When the upstream MCP server is stdio-only or otherwise not directly HTTP
  connectable, add a repo-local wrapper under `applications/<service>/` that
  provides a stable HTTP transport.
- New custom MCP servers should default to HTTP-connectable designs. Prefer
  streamable HTTP or a maintained HTTP bridge/proxy rather than a host-local
  one-off adapter.

## Shared Credential Rules

- Credentials belong in `/mnt/eapp/.tfvars/<service>/app.tfvars`,
  `/mnt/eapp/.tfvars/vault/config.tfvars`, or in the runtime secret flow that
  the service already uses. Do not commit live tokens, passwords, or service
  account files into the repo.
- Prefer the narrowest scope that still supports the required tools. Do not
  widen provider access simply because the MCP server can expose more tools.
- When a service already supports a safer default mode such as read-only,
  preserve that default unless the task explicitly requires write access.

## Image Source Rules

- If a service has a repo-local image wrapper under `applications/<service>/`,
  keep the deployment image reference and the wrapper implementation in sync.
- If a deployment points at a custom tag, the exact referenced image must exist
  in the target registry or runtime before apply.
- Services without a repo-local Docker context should continue to pin upstream
  images directly in Terraform or manifests, whichever owns the deployment.

## Service Rules

### `mcp-argocd`

- Runtime root: `kubernetes/mcp-argocd`
- Argo CD objects: `kubernetes/argocd-management/mcp-argocd-project.yaml`
  and `kubernetes/argocd-management/mcp-argocd-app.yaml`
- Image source: upstream image pinned directly in Kubernetes manifests
- Listen model: container `3000`, service `3000`, ingress-routed hostname
  `https://mcp.argocd.nodadyoushutup.com/mcp`
- Access model: `mcp_read_only` defaults to `true` and should stay that way
  unless the task genuinely needs mutating Argo CD tools.
- Token model: keep the Kubernetes app env secret sourced from
  `secret/k8s/mcp_argocd` through `ExternalSecret`; do not widen that secret to
  unrelated Argo CD or cluster credentials.
- Trust model: `argocd_insecure_skip_verify` is an exception flag. Only enable
  it when the Argo CD certificate trust path cannot be fixed in the same task.
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of inventing a second client URL

### `mcp-atlassian`

- Runtime root: `kubernetes/mcp-atlassian`
- Argo CD objects: `kubernetes/argocd-management/mcp-atlassian-project.yaml`
  and `kubernetes/argocd-management/mcp-atlassian-app.yaml`
- Image source: upstream image pinned directly in Kubernetes manifests
- Listen model: container `8000`, service `8000`, ingress-routed hostname
  `https://mcp.atlassian.nodadyoushutup.com/mcp`
- Transport model: use upstream `streamable-http` directly on `/mcp`; do not
  add a repo-local proxy unless a future upstream limitation requires one
- Access model: the service runs with the upstream full Jira and Confluence
  tool surface enabled through explicit `--toolsets all`. Keep mutating access
  intentional, and use scope filters or explicit tool restrictions if the repo
  later needs to narrow exposure.
- Scope model: keep `JIRA_PROJECTS_FILTER` and `CONFLUENCE_SPACES_FILTER`
  populated in the Vault-backed app env secret when the server should stay
  limited to a subset of Atlassian content.
- Credential model: Jira and Confluence credentials are independent inputs in
  the Vault-backed app env secret. Do not silently drop one side when the
  service is expected to expose both tool families.
- Secret model: keep the Kubernetes app env secret sourced from
  `secret/k8s/mcp_atlassian` through `ExternalSecret`; carry forward the
  existing Jira and Confluence scope filters during migration so the platform
  move does not widen access by accident

### `mcp-ast-grep`

- Runtime root: `kubernetes/mcp-ast-grep`
- Argo CD objects: `kubernetes/argocd-management/mcp-ast-grep-project.yaml`
  and `kubernetes/argocd-management/mcp-ast-grep-app.yaml`
- Image source: `applications/mcp-ast-grep/` owns the repo-local HTTP-capable
  wrapper image referenced by Kubernetes
- Listen model: container `8096`, service `8096`, ingress-routed hostname
  `https://mcp.ast-grep.nodadyoushutup.com/mcp`
- Workspace model: mount the shared code tree from the TrueNAS NFS export at
  `/mnt/eapp/code` read-only inside the pod; keep the mounted root and
  in-container allowlist root identical so the server can serve multiple local
  workspaces from one deployment.
- Runtime user model: run the pod as UID/GID `1000:1000` so the root-squashed
  NFS workspace stays readable without relying on root inside the container.
- Scope model: keep the mounted root restricted to the shared code tree and use
  a workspace-local client hint to select the default project root. The server
  should honor repo-local Codex config via the `x-workspace-root` header or a
  `workspace_root` query parameter when `project_folder` is omitted.
- Client config model: this server is workspace-scoped, so prefer a repo-local
  `.codex/config.toml` entry instead of adding it to the global Codex config
  unless a task explicitly promotes it to a shared server. Keep the repo-local
  `http_headers.x-workspace-root` value aligned with the active workspace root.
- Language model: keep Terraform/HCL file globs configured through the
  ast-grep config used by the container; add custom parsers only when the
  language is materially used in this repo and the parser maintenance burden is
  justified
- Secret model: keep the Harbor pull secret sourced from
  `secret/k8s/mcp_ast_grep` through `ExternalSecret`; do not split the image
  pull credentials across ad hoc Kubernetes secrets
- Custom parser model: Dockerfile parsing is currently the justified
  custom-language exception; do not add template-heavy formats such as Jinja or
  `*.tftpl` unless there is a demonstrated parser strategy that handles the
  templating syntax cleanly
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port

### `mcp-cloudflare`

- Runtime root: `kubernetes/mcp-cloudflare`
- Argo CD objects: `kubernetes/argocd-management/mcp-cloudflare-project.yaml`
  and `kubernetes/argocd-management/mcp-cloudflare-app.yaml`
- Image source: `applications/mcp-cloudflare/` builds the Harbor-backed wrapper
  image referenced by Kubernetes
- Listen model: container `8084`, service `8084`, ingress-routed hostname
  `https://mcp.cloudflare.nodadyoushutup.com/mcp`
- Credential model: `cloudflare_api_token` and `cloudflare_zone_id` are both
  required for the current DNS-focused server shape.
- Scope model: keep the token limited to the zone and permissions actually
  required by the MCP server.
- Compatibility model: `cloudflare_email` is optional compatibility input, not
  the primary authentication mechanism.
- Secret model: keep both the Kubernetes app env secret and Harbor pull secret
  sourced from `secret/k8s/mcp_cloudflare` through `ExternalSecret` so the app
  runtime and registry access stay in one Vault-managed payload.
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port.

### `mcp-filesystem`

- Runtime root: `kubernetes/mcp-filesystem`
- Argo CD objects: `kubernetes/argocd-management/mcp-filesystem-project.yaml`
  and `kubernetes/argocd-management/mcp-filesystem-app.yaml`
- Image source: `applications/mcp-filesystem/` wraps the official
  `@modelcontextprotocol/server-filesystem` server behind the repo-standard
  HTTP proxy image published to Harbor
- Listen model: container `8098`, service `8098`, ingress-routed hostname
  `https://mcp.filesystem.nodadyoushutup.com/mcp/`
- Workspace model: mount the homelab workspace from the TrueNAS NFS export at
  `/mnt/eapp/code/homelab` read-write inside the pod and pass that exact path
  to the upstream filesystem server as its native allowed root
- Runtime user model: run the pod as UID/GID `1000:1000` so filesystem writes
  continue to respect the root-squashed NFS export
- Scope model: this server is homelab-workspace-scoped at deploy time. Clients
  should treat `/mnt/eapp/code/homelab` as the source of truth for local repo
  paths and keep filesystem tool arguments inside that tree
- Access model: the current proof-of-concept exposes the upstream filesystem
  toolset directly. If request-scoped read-only policy returns later, implement
  it in a dedicated wrapper instead of overloading the Kubernetes manifests
- Client config model: point repo-local `.codex/config.toml` or app MCP config
  at the stable hostname and keep local repo paths anchored at
  `/mnt/eapp/code/homelab`

### `mcp-git`

- Runtime root: `kubernetes/mcp-git`
- Argo CD objects: `kubernetes/argocd-management/mcp-git-project.yaml` and
  `kubernetes/argocd-management/mcp-git-app.yaml`
- Image source: `applications/mcp-git/` wraps the official `mcp-server-git`
  reference server behind the repo-standard HTTP bridge.
- Listen model: container `8099`, service `8099`, ingress-routed hostname
  `https://mcp.git.nodadyoushutup.com/mcp`
- Repository model: mount the shared code tree from the TrueNAS NFS export at
  `/mnt/eapp/code` read-write inside the pod, but point the upstream server at
  `/mnt/eapp/code/homelab` because it must start from a real Git repository.
- Runtime user model: run the pod as UID/GID `1000:1000` so git operations can
  keep writing through the root-squashed workspace export without falling back
  to root.
- Scope model: treat the current deployment as homelab-workspace-scoped until
  the wrapper can safely proxy arbitrary repo roots. Keep repo-local Codex
  config and tool usage anchored at `/mnt/eapp/code/homelab`.
- Secret model: keep the Kubernetes pull secret sourced from `secret/k8s/mcp_git`
  through `ExternalSecret` so Harbor registry access stays in Vault instead of
  in repo manifests.
- Client config model: this server is workspace-scoped, so prefer a repo-local
  `.codex/config.toml` entry instead of adding it to the global Codex config
  unless a task explicitly promotes it to a shared server. Keep the repo-local
  `http_headers.x-workspace-root` value aligned with the active workspace root.

### `mcp-fortigate`

- Runtime root: `kubernetes/mcp-fortigate`
- Argo CD objects:
  `kubernetes/argocd-management/mcp-fortigate-project.yaml` and
  `kubernetes/argocd-management/mcp-fortigate-app.yaml`
- Image source: `applications/mcp-fortigate/` builds the GHCR-backed wrapper
  image referenced by Kubernetes
- Listen model: container `8814`, service `8814`, ingress-routed hostname
  `https://mcp.fortigate.nodadyoushutup.com/mcp`
- Credential model: set either `fortigate_api_token` or both
  `fortigate_username` and `fortigate_password`. Do not leave both auth modes
  incomplete.
- Access model: prefer API token auth when available rather than username and
  password auth.
- Device model: keep `fortigate_host`, `fortigate_port`, `fortigate_vdom`,
  `fortigate_verify_ssl`, and `fortigate_timeout` explicit in the Kubernetes
  deployment env so the runtime config stays deterministic.
- Secret model: keep the Kubernetes app env secret and GHCR pull secret sourced
  from `secret/k8s/mcp_fortigate` through `ExternalSecret`; the unused auth
  mode may be present as empty strings, but the active auth mode must be
  populated.
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port.

### `mcp-github`

- Runtime root: `kubernetes/mcp-github`
- Argo CD objects: `kubernetes/argocd-management/mcp-github-project.yaml` and
  `kubernetes/argocd-management/mcp-github-app.yaml`
- Image source: `applications/mcp-github/` builds the wrapper image referenced
  by Kubernetes
- Listen model: container `8082`, service `8082`, ingress-routed hostname
  `https://mcp.github.nodadyoushutup.com/mcp`
- Credential model: `github_personal_access_token` is required. Use a token
  with the minimum scopes needed for the repos and organizations this server is
  supposed to manage.
- Tool model: the wrapper currently passes `GITHUB_MCP_TOOLSETS=all`. Treat any
  reduction or expansion of toolsets as a deliberate compatibility change.
- Secret model: keep both the Kubernetes app env secret and the GHCR pull
  secret sourced from `secret/k8s/mcp_github` through `ExternalSecret`; do not
  duplicate the token or registry credentials into repo-managed manifests or
  local files once the cluster path is live.
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port.

### `mcp-google-workspace`

- Runtime root: `kubernetes/mcp-google-workspace`
- Argo CD objects:
  `kubernetes/argocd-management/mcp-google-workspace-project.yaml` and
  `kubernetes/argocd-management/mcp-google-workspace-app.yaml`
- Image source: `applications/mcp-google-workspace/` builds the Harbor-backed
  wrapper image referenced by Kubernetes
- Listen model: container `8086`, service `8086`, ingress-routed hostname
  `https://mcp.google-workspace.nodadyoushutup.com/mcp`
- Credential model: keep the app env, Harbor pull credentials, and delegated
  service-account JSON sourced from `secret/k8s/mcp_google_workspace` through
  `ExternalSecret`; do not commit the service-account JSON into the repo or
  reintroduce a node-local file dependency for the runtime
- Delegation model: `workspace_delegated_user` must stay a valid email address
  because the wrapper enforces single-user service-account impersonation
- Tool model: `workspace_tool_tier` must stay one of `core`, `extended`, or
  `complete`; add `workspace_tools` back only when the task intentionally
  narrows the server below the tier default
- Safety model: `workspace_read_only` defaults to `false`, so write access is
  still the steady-state posture. Set it deliberately when the task should
  constrain the server
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port

### `mcp-kubernetes`

- Runtime root: `kubernetes/mcp-kubernetes`
- Argo CD objects: `kubernetes/argocd-management/mcp-kubernetes-project.yaml`
  and `kubernetes/argocd-management/mcp-kubernetes-app.yaml`
- Image source: upstream image pinned directly in Kubernetes manifests from
  `quay.io/containers/kubernetes_mcp_server`
- Listen model: container `8106`, service `8106`, ingress-routed hostname
  `https://mcp.kubernetes.nodadyoushutup.com/mcp`
- Credential model: use the pod's in-cluster Kubernetes credentials through a
  dedicated ServiceAccount bound to the built-in read-only `view` ClusterRole;
  do not mount a static kubeconfig unless a future recovery path explicitly
  needs one
- Access model: keep `mcp_read_only = true`, `disable_multi_cluster = true`,
  `cluster-provider = in-cluster`, and `toolsets = "core,config"` unless a
  task explicitly requires broader Kubernetes capabilities
- Output model: keep `list_output = "yaml"` so cluster object responses stay
  structured for LLM clients
- Deployment model: use the upstream native HTTP server directly; do not add a
  repo-local wrapper unless the upstream transport or image model stops fitting
  the repo standard; keep the hostname routed through ingress rather than a
  raw published port

### `mcp-bash-pipeline`

- Runtime root: `kubernetes/mcp-bash-pipeline`
- Argo CD objects:
  `kubernetes/argocd-management/mcp-bash-pipeline-project.yaml` and
  `kubernetes/argocd-management/mcp-bash-pipeline-app.yaml`
- Image source: `applications/mcp-bash-pipeline/` owns the repo-local native
  Streamable HTTP MCP server image referenced by Kubernetes
- Listen model: container `8107`, service `8107`, ingress-routed hostname
  `https://mcp.bash-pipeline.nodadyoushutup.com/mcp`
- Workspace model: mount the shared code tree from the TrueNAS NFS export at
  `/mnt/eapp/code` read-write and set the default workspace root to
  `/mnt/eapp/code/homelab`; keep the allowlist pinned to the shared code tree
- tfvars model: mount `/mnt/eapp/.tfvars` into the pod from cluster-reachable
  storage and keep the in-container path aligned with the shared Terraform
  wrapper defaults instead of depending on a Swarm node-local bind mount
- Runtime user model: run the pod as an unprivileged UID/GID that can read and
  execute files from the NFS-mounted repo path; do not fall back to root
  against a root-squashed workspace mount
- Tool model: keep the server limited to typed pipeline tools for
  `terraform/**/pipeline/*.sh`; do not widen it into arbitrary shell execution
  or a generic terminal bridge
- Execution model: prefer repo-managed Terraform stage entrypoints that already
  conform to the shared `scripts/terraform/swarm_pipeline.sh` contract; keep
  known host-dependent pipelines explicitly blocked until the container runtime
  is intentionally widened to support them
- Secret model: keep the Kubernetes pull secret sourced from
  `secret/k8s/mcp_bash_pipeline` through `ExternalSecret` so Harbor registry
  access stays in Vault instead of in repo manifests
- Client config model: this server is workspace-scoped, so keep it in the
  repo-local `.codex/config.toml` with the same `x-workspace-root` convention
  used by the other local MCP servers and include the logical workspace header
  when clients need to distinguish homelab from other mounted workspaces

### `mcp-terraform`

- Runtime root: `kubernetes/mcp-terraform`
- Argo CD objects:
  `kubernetes/argocd-management/mcp-terraform-project.yaml` and
  `kubernetes/argocd-management/mcp-terraform-app.yaml`
- Image source: `applications/mcp-terraform/` packages HashiCorp's official
  `terraform-mcp-server` binary into the Harbor-backed wrapper image referenced
  by Kubernetes
- Listen model: container `8080`, service `8080`, ingress-routed hostname
  `https://mcp.terraform.nodadyoushutup.com/mcp`, health path `/health`
- Tool model: keep `toolsets` on `registry` by default; only widen to
  `registry-private`, `terraform`, or `all` when the task explicitly needs more
  than public registry lookups
- Credential model: `tfe_token` is optional and should stay scoped to the
  minimum HCP Terraform or Terraform Enterprise permissions required; set
  `tfe_address` only when the deployment should target a non-default hostname
- Safety model: keep `enable_tf_operations` false unless the task explicitly
  requires Terraform operation tools
- CORS model: keep `mcp_cors_mode = "strict"` and leave
  `mcp_allowed_origins` empty unless a browser-based client genuinely requires
  cross-origin access
- Secret model: keep both the Kubernetes app env secret and Harbor pull secret
  sourced from `secret/k8s/mcp_terraform` through `ExternalSecret` so runtime
  config and registry access stay in one Vault-managed payload
- Delivery model: preserve the stable operator hostname during migration and
  cut the Nginx Proxy Manager route over to the Kubernetes ingress IP instead
  of keeping the old Swarm published port
