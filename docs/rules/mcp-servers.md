# MCP Server Rules

This document defines the steady-state rules for MCP servers in this repo. Use
[`docs/workflows/mcp-servers.md`](./../workflows/mcp-servers.md) for the
operator flow and [`docs/rules/terraform.md`](./terraform.md) for the shared
Terraform guardrails the Swarm-hosted services also follow.

## Scope

This document applies to the current MCP server set:

- `terraform/swarm/mcp-argocd/app`
- `terraform/swarm/mcp-ast-grep/app`
- `terraform/swarm/mcp-cloudflare/app`
- `terraform/swarm/mcp-git-homelab/app`
- `terraform/swarm/mcp-fortigate/app`
- `terraform/swarm/mcp-github/app`
- `terraform/swarm/mcp-google-workspace/app`
- `terraform/swarm/mcp-kubernetes/app`
- `terraform/swarm/mcp-redis/app`
- `terraform/swarm/mcp-agent-protocol/app`
- `terraform/swarm/mcp-bash-pipeline/app`
- `terraform/swarm/mcp-terraform/app`
- `kubernetes/mcp-atlassian`
- `kubernetes/mcp-filesystem`

## Shared Placement Rules

- Existing Swarm-hosted MCP servers stay in `terraform/swarm/<service>/app`
  unless a task explicitly migrates them.
- New MCP servers may use the Kubernetes pattern under `kubernetes/<service>/`
  when the human explicitly chooses the cluster route. Current reference
  exceptions are `kubernetes/mcp-atlassian` and `kubernetes/mcp-filesystem`.
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

- Runtime root: `terraform/swarm/mcp-argocd/app`
- Image source: upstream image pinned directly in Terraform
- Listen model: internal `3000`, published `18086`
- Access model: `mcp_read_only` defaults to `true` and should stay that way
  unless the task genuinely needs mutating Argo CD tools.
- Token model: `argocd_api_token` may be injected at deploy time by the stage
  pipeline; do not replace that with a hardcoded repo secret.
- Trust model: `argocd_insecure_skip_verify` is an exception flag. Only enable
  it when the Argo CD certificate trust path cannot be fixed in the same task.

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

- Runtime root: `terraform/swarm/mcp-ast-grep/app`
- Image source: `applications/mcp-ast-grep/` owns the repo-local HTTP-capable
  wrapper image
- Listen model: internal `8096`, published `18096`, HTTP path `/mcp`
- Workspace model: bind-mount the shared code tree at `/mnt/eapp/code`
  read-only on both the Swarm host and inside the container; keep the host mount
  root and in-container allowlist root identical so the server can serve
  multiple local workspaces from one deployment.
- Runtime user model: run the container with an unprivileged UID/GID that can
  read the NFS-mounted workspace path. Do not rely on root inside the
  container against a root-squashed repo mount.
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
- Custom parser model: Dockerfile parsing is currently the justified
  custom-language exception; do not add template-heavy formats such as Jinja or
  `*.tftpl` unless there is a demonstrated parser strategy that handles the
  templating syntax cleanly

### `mcp-cloudflare`

- Runtime root: `terraform/swarm/mcp-cloudflare/app`
- Image source: `applications/mcp-cloudflare/` builds the wrapper image referenced by
  Terraform
- Listen model: internal `8084`, published `18090`, HTTP bridge provided by the
  local wrapper
- Credential model: `cloudflare_api_token` and `cloudflare_zone_id` are both
  required for the current DNS-focused server shape.
- Scope model: keep the token limited to the zone and permissions actually
  required by the MCP server.
- Compatibility model: `cloudflare_email` is optional compatibility input, not
  the primary authentication mechanism.

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

### `mcp-git-homelab`

- Runtime root: `terraform/swarm/mcp-git-homelab/app`
- Image source: `applications/mcp-git-homelab/` wraps the official
  `mcp-server-git` reference server behind the repo-standard HTTP bridge.
- Listen model: internal `8099`, published `18099`, HTTP path `/mcp`
- Repository model: bind-mount the shared code tree at `/mnt/eapp/code`
  read-write on both the Swarm host and inside the container so the git server
  can serve multiple real repositories beneath one NFS-backed root.
- Runtime user model: run the container with an unprivileged UID/GID that can
  write to the NFS-mounted repository path. Do not run the service as root
  against a root-squashed repo mount.
- Scope model: keep the server pinned to the shared code tree and rely on the
  explicit `repo_path` argument each git tool already requires. Repo-local
  Codex config may carry an `x-workspace-root` hint, but repository selection
  remains an explicit tool argument.
- Client config model: this server is workspace-scoped, so prefer a repo-local
  `.codex/config.toml` entry instead of adding it to the global Codex config
  unless a task explicitly promotes it to a shared server. Keep the repo-local
  `http_headers.x-workspace-root` value aligned with the active workspace root.

### `mcp-fortigate`

- Runtime root: `terraform/swarm/mcp-fortigate/app`
- Image source: `applications/mcp-fortigate/` supplies the custom runtime currently
  published to GHCR
- Listen model: internal `8814`, published `18084`, HTTP path `/mcp`
- Credential model: set either `fortigate_api_token` or both
  `fortigate_username` and `fortigate_password`. Do not leave both auth modes
  incomplete.
- Access model: prefer API token auth when available rather than username and
  password auth.
- Device model: keep `fortigate_host`, `fortigate_port`, `fortigate_vdom`, and
  `fortigate_timeout` explicit in tfvars so the generated runtime config is
  deterministic.

### `mcp-github`

- Runtime root: `terraform/swarm/mcp-github/app`
- Image source: `applications/mcp-github/` builds the wrapper image referenced by
  Terraform
- Listen model: internal `8082`, published `18082`, HTTP bridge provided by the
  local wrapper
- Credential model: `github_personal_access_token` is required. Use a token
  with the minimum scopes needed for the repos and organizations this server is
  supposed to manage.
- Tool model: the wrapper currently passes `GITHUB_MCP_TOOLSETS=all`. Treat any
  reduction or expansion of toolsets as a deliberate compatibility change.

### `mcp-google-workspace`

- Runtime root: `terraform/swarm/mcp-google-workspace/app`
- Image source: `applications/mcp-google-workspace/` owns the local wrapper for the
  `homelab/mcp-google-workspace:*` image tag used by Terraform
- Listen model: internal `8086`, published `18092`, HTTP endpoint provided by
  the local wrapper
- Credential model: `workspace_service_account_file` must point at a real local
  file on the Terraform runner. The JSON file is converted into a Docker secret
  at apply time and must never be committed to the repo.
- Delegation model: `workspace_delegated_user` must stay a valid email address
  because the wrapper enforces service-account impersonation for a single user.
- Tool model: `workspace_tool_tier` must stay one of `core`, `extended`, or
  `complete`; `workspace_tools` is optional and only used for explicit
  narrowing.
- Safety model: `workspace_read_only` defaults to `false`, so write access is
  the current steady-state behavior. Set it deliberately when the task should
  constrain the server.

### `mcp-kubernetes`

- Runtime root: `terraform/swarm/mcp-kubernetes/app`
- Image source: upstream image pinned directly in Terraform from
  `quay.io/containers/kubernetes_mcp_server`
- Listen model: internal `8106`, published `18106`, HTTP path `/mcp`
- Credential model: source the cluster credential from a dedicated kubeconfig
  file under `/mnt/eapp/.tfvars/mcp-kubernetes/` and inject it as a Docker
  secret instead of baking credentials into the image
- Access model: keep `mcp_read_only = true`, `disable_multi_cluster = true`,
  and `toolsets = "core,config"` unless a task explicitly requires broader
  Kubernetes capabilities
- Output model: keep `list_output = "yaml"` so cluster object responses stay
  structured for LLM clients
- Deployment model: use the upstream native HTTP server directly; do not add a
  repo-local wrapper unless the upstream transport or image model stops fitting
  the repo standard

### `mcp-redis`

- Runtime root: `terraform/swarm/mcp-redis/app`
- Image source: `applications/mcp-redis/` owns the repo-local native
  Streamable HTTP MCP server image
- Listen model: internal `8101`, published `18101`, HTTP path `/mcp`
- Redis model: keep the backing Redis service private to the service overlay;
  the MCP server is the host-routed access path, not the Redis TCP port itself
- Scope model: use `key_prefix` deliberately so agents operate inside an
  intended logical namespace rather than treating the whole Redis instance as
  an unbounded scratchpad
- Safety model: destructive operations are allowed by default for this server,
  but they remain explicitly controllable through
  `allow_destructive_operations`

### `mcp-agent-protocol`

- Runtime root: `terraform/swarm/mcp-agent-protocol/app`
- Image source: `applications/mcp-agent-protocol/` owns the repo-local native
  Streamable HTTP MCP server image
- Listen model: internal `8100`, published `18100`, HTTP path `/mcp`
- Redis model: keep the backing Redis service private to the overlay network;
  expose the MCP server, not raw Redis, to host clients by default
- Storage model: store protocol request/response envelopes, liveness records,
  task claims, and short-lived summaries as JSON under a stable key prefix
- Host validation model: keep the MCP transport host/origin allowlist aligned
  with the raw Swarm validation host and the intended `mcp.agent-protocol`
  hostname instead of disabling DNS rebinding protection
- Safety model: do not widen the server into a generic Redis console; keep the
  tool surface constrained to protocol-aware operations
- Data model: do not use this store for raw chain-of-thought, long-lived
  secrets, or the only durable audit trail

### `mcp-bash-pipeline`

- Runtime root: `terraform/swarm/mcp-bash-pipeline/app`
- Image source: `applications/mcp-bash-pipeline/` owns the repo-local native
  Streamable HTTP MCP server image
- Listen model: internal `8107`, published `18107`, HTTP path `/mcp`
- Workspace model: bind-mount the shared code tree at `/mnt/eapp/code`
  read-write and the tfvars tree at `/mnt/eapp/.tfvars`; keep the default
  workspace root aligned with the repo-local Codex config and allowlist only
  the shared code tree
- tfvars host model: the `/mnt/eapp/.tfvars` bind source is node-local from the
  Swarm host that runs the service. Keep the required tfvars subtree populated
  on `swarm-cp-0` itself; a matching directory that exists only on another host
  does not satisfy the runtime contract inside the container
- Runtime user model: run the container with an unprivileged UID/GID that can
  read and execute files from the NFS-mounted repo path; do not fall back to
  root against a root-squashed workspace mount
- Tool model: keep the server limited to typed pipeline tools for
  `terraform/**/pipeline/*.sh`; do not widen it into arbitrary shell execution
  or a generic terminal bridge
- Execution model: prefer repo-managed Terraform stage entrypoints that already
  conform to the shared `scripts/terraform/swarm_pipeline.sh` contract; keep
  known host-dependent pipelines explicitly blocked until the container runtime
  is intentionally widened to support them
- Client config model: this server is workspace-scoped, so keep it in the
  repo-local `.codex/config.toml` with the same `x-workspace-root` convention
  used by the other local MCP servers and include the logical workspace header
  when clients need to distinguish homelab from other mounted workspaces

### `mcp-terraform`

- Runtime root: `terraform/swarm/mcp-terraform/app`
- Image source: `applications/mcp-terraform/` packages HashiCorp's official
  `terraform-mcp-server` binary into a thin image that can expose the upstream
  HTTP health endpoint to Swarm healthchecks
- Listen model: internal `8080`, published `18104`, HTTP path `/mcp`, health
  path `/health`
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
