# Swarm MCP Server Rules

This document defines the steady-state rules for the MCP servers that run in
Docker Swarm in this repo. Use
[`docs/workflows/mcp-servers.md`](./../workflows/mcp-servers.md) for the
operator flow and [`docs/rules/terraform.md`](./terraform.md) for the shared
Terraform guardrails these services also follow.

## Scope

This document applies to the current Swarm-hosted MCP server set:

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

## Shared Placement Rules

- Swarm-hosted MCP servers stay in `terraform/swarm/<service>/app`. Do not move
  them into `kubernetes/`; these are management-plane services that should stay
  available during cluster trouble.
- Each MCP server keeps its own single `app` stage and single backend state
  file. Do not merge multiple MCP services into one Terraform root or one state
  key.
- Each service keeps the current one-replica control-plane placement pattern:
  `node.labels.role==swarm-cp-0`.
- Each service keeps its own overlay network named after the service. Do not
  collapse multiple MCP servers onto one shared overlay by default.
- Keep provider-driven registry auth in `provider.tf` when the image comes from
  a private registry or authenticated GHCR path.

## Shared Runtime Rules

- Keep the published ingress port, internal listen port, and transport path
  aligned with the actual service wrapper. Do not change ports casually because
  MCP clients and local tooling depend on them.
- Keep an explicit container healthcheck that probes the actual listening port
  or HTTP MCP endpoint.
- Keep the standard DNS resolver list in the Swarm service unless the runtime
  proves a server-specific need for something else.

## Shared Reachability Rules

- Treat MCP servers as Swarm-hosted operator apps that must still be HTTP
  reachable for LLM clients running off-swarm.
- The standard client path is a stable hostname routed through the repo-managed
  edge config, not a raw Swarm published port copied into a client by hand.
- Keep `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`,
  `/mnt/eapp/.tfvars/cloudflare/config.tfvars`, and the matching Codex config
  layer (`~/.codex/config.toml` for global servers or repo-local
  `.codex/config.toml` for workspace-specific servers) aligned with the Swarm
  service port and MCP HTTP path for every host-usable server.
- The Codex host is not part of the Swarm overlay network. Do not point host
  MCP config at Swarm service names, overlay-only addresses, or ad hoc direct
  ports unless the task explicitly documents a temporary fallback.
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

- Credentials belong in `/mnt/eapp/.tfvars/<service>/app.tfvars` or in the
  runtime secret flow that the service already uses. Do not commit live tokens,
  passwords, or service account files into the repo.
- Prefer the narrowest scope that still supports the required tools. Do not
  widen provider access simply because the MCP server can expose more tools.
- When a service already supports a safer default mode such as read-only,
  preserve that default unless the task explicitly requires write access.

## Image Source Rules

- If a service has a repo-local image wrapper under `applications/<service>/`, keep
  the Terraform image reference and the wrapper implementation in sync.
- If Terraform points at a custom tag, the exact referenced image must exist in
  the target registry or Docker engine before apply.
- Services without a repo-local Docker context should continue to pin upstream
  images directly in Terraform.

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

- Runtime root: `terraform/swarm/mcp-atlassian/app`
- Image source: upstream image pinned directly in Terraform
- Listen model: internal `8000`, published `18080`, HTTP path `/mcp`
- Access model: the service is intentionally started with `--read-only`; keep
  that behavior unless the repo intentionally adopts a different upstream mode.
- Scope model: keep `jira_projects_filter` and `confluence_spaces_filter`
  populated when the server should be limited to a subset of Atlassian content.
- Credential model: Jira and Confluence credentials are independent inputs. Do
  not silently drop one side when the service is expected to expose both tool
  families.

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

### `mcp-filesystem-homelab`

- Runtime root: `terraform/swarm/mcp-filesystem-homelab/app`
- Image source: `applications/mcp-filesystem-homelab/` wraps the official
  `@modelcontextprotocol/server-filesystem` reference server behind the
  repo-standard HTTP bridge.
- Listen model: internal `8098`, published `18098`, HTTP path `/mcp`
- Workspace model: bind-mount the shared code tree at `/mnt/eapp/code`
  read-write on both the Swarm host and inside the container; keep the host
  mount root and in-container allowlist root identical so one deployment can
  serve multiple local workspaces.
- Runtime user model: run the container with an unprivileged UID/GID that owns
  the NFS-mounted workspace path. Do not leave this service running as root
  against a root-squashed repo mount.
- Scope model: keep the server restricted to the shared code tree. Workspace
  scoping continues to happen through the explicit `path` arguments passed to
  the filesystem tools; repo-local Codex config may still carry an
  `x-workspace-root` hint for consistency with the other local MCP servers.
- Client config model: this server is workspace-scoped, so prefer a repo-local
  `.codex/config.toml` entry instead of adding it to the global Codex config
  unless a task explicitly promotes it to a shared server. Keep the repo-local
  `http_headers.x-workspace-root` value aligned with the active workspace root.

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
