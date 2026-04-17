# Application Placement Rules

This document defines how to decide where a new application belongs in this
repo.

Use this file before creating a new app. Use
[`docs/workflows/new-application.md`](./../workflows/new-application.md) for
the execution flow after the decision is made. Use
[`docs/rules/application-networking.md`](./application-networking.md) for app
hostname, DNS, and proxy rules after the platform decision is made.

## Two Application Classes

This homelab currently has two application platforms:

- `Swarm app`: a Docker Swarm application delivered from
  `terraform/swarm/<service>/<stage>`
- `Cluster app`: a Kubernetes application delivered from `kubernetes/` and
  usually managed by Argo CD from `kubernetes/argocd-management`

Compose-only stacks such as MinIO backend and Renovate are existing exceptions,
not a third default platform for new apps.

## Default Placement Rule

New applications default to `Cluster app` unless there is a clear reason they
must keep running during a Kubernetes failure or they primarily exist to manage,
observe, or recover infrastructure.

If the prompt says "add a new app" without naming the platform, the first
decision is:

1. does this app need to stay up when Kubernetes is broken
2. is this app mainly infrastructure, observability, control-plane support, or
   server-management tooling
3. if neither is true, place it in Kubernetes

Do not choose Swarm just because Terraform is familiar or because a single
container feels simpler there.

## What Belongs In Swarm

Use `Swarm app` when the service is part of the supporting platform and should
remain available during Kubernetes outages or recovery work.

Typical Swarm categories in this repo:

- monitoring and observability
- log collection and inspection
- registry and CI infrastructure
- secrets or control-plane support services
- MCP servers and other server-management tooling

Repo examples:

- observability: `terraform/swarm/grafana`, `prometheus`, `loki`, `alloy`,
  `graphite`, `dozzle`, `node_exporter`, `telegraf_docker_metrics`
- infrastructure: `terraform/swarm/harbor`, `vault`,
  `nginx_proxy_manager`, `gha-runner`, `jenkins-controller`
- management tooling: `terraform/swarm/mcp-argocd`, `mcp-atlassian`,
  `mcp-ast-grep`, `mcp-cloudflare`, `mcp-filesystem-homelab`,
  `mcp-fortigate`, `mcp-github`, `mcp-google-workspace`, `mcp-redis`,
  `mcp-agent-protocol`, `mcp-langflow`

If the Swarm service is an MCP server, use
[`docs/rules/mcp-servers.md`](./mcp-servers.md) for its service-specific
guardrails after the platform decision is made.

Custom MCP servers should normally have:

- `terraform/swarm/<service>/app` for the Swarm runtime
- `applications/<service>/` when a repo-local HTTP wrapper or proxy variant is
  needed
- hostname routing and host Codex config aligned through the MCP workflow docs

## What Belongs In Kubernetes

Use `Cluster app` for almost all normal application workloads.

This is the default home for:

- end-user applications
- media and content applications
- internal tools that are not required for cluster recovery
- most new product-style services

Repo examples:

- single-instance apps: `kubernetes/prowlarr`, `radarr`, `sonarr`, `seerr`,
  `privatebin`, `picsur`, `thelounge`, `tautulli`
- multi-instance families: `kubernetes/qbittorrent`,
  `kubernetes/cross-seed`

Cluster addons such as `metallb`, `ingress-nginx`, `external-secrets`, and
`snapshot-controller` are also Kubernetes-managed, but they are platform
components rather than normal app onboarding examples.

## Kubernetes App Shape Rule

Once an app has been classified as a `Cluster app`, there is a second decision:

- `standard app`: a normal single-app manifest directory such as
  `kubernetes/<app>/`
- `Kustomize app`: a `base/` plus `overlays/` layout for a multi-instance or
  multi-variant family

This second decision is human-gated.

Agents must not choose `standard app` versus `Kustomize app` on their own for a
new Kubernetes app. The human must explicitly tell the agent which shape to
use.

Normal default expectation:

- most new Kubernetes apps will be `standard app`
- some new Kubernetes app families will be `Kustomize app` when multiple
  variants or instances are expected

## Decision Checklist

Choose `Swarm app` only when one or more of these are true:

- the app is needed to monitor, debug, or recover Kubernetes
- the app is part of infrastructure or server-management rather than an
  end-user workload
- the app should stay reachable while the cluster is degraded or offline

Choose `Cluster app` when one or more of these are true:

- the app is a normal workload consumed by users or other apps
- the app is not required to recover Kubernetes
- the app fits the existing GitOps pattern under `kubernetes/`

If the answer is mixed, bias toward Kubernetes unless the failure-domain reason
for Swarm is explicit and strong.

## Implementation Boundaries

After platform selection, keep the implementation in the matching part of the
repo:

- Swarm runtime and config live under `terraform/swarm/<service>/<stage>`
- optional Swarm image sources live under `applications/<service>/`
- Cluster `standard app` manifests live under `kubernetes/<app>/`
- Cluster `Kustomize app` manifests live under
  `kubernetes/<family>/{base,overlays}`
- Cluster GitOps definitions live under `kubernetes/argocd-management`

Do not split one new app across both platforms unless the architecture truly has
separate components with different failure-domain requirements.

## External Endpoint Rule

For both application classes, a new externally reachable HTTP endpoint is not
complete until the edge routing is represented in code:

- Nginx Proxy Manager tfvars under `/mnt/eapp/.tfvars/nginx-proxy-manager/`
- Cloudflare tfvars under `/mnt/eapp/.tfvars/cloudflare/`

Every app that is intended to be reachable through a domain must have explicit
bound subdomains represented in those files. Do not rely on only a wildcard DNS
record.

Default to internal-only DNS targets unless a human explicitly asks for public
exposure or the service follows the documented MCP hostname pattern.
`thelounge.nodadyoushutup.com` remains the current normal public end-user
exception; MCP hostnames are the documented operator exception.

For torrent peer traffic, follow the direct L4 forwarding rule instead of HTTP
proxy routing.
