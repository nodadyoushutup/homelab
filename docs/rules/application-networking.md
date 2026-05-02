# Application Networking Rules

This document defines the steady-state rules for naming, DNS, reverse proxy,
and reachability of application endpoints in this repo. Use it whenever a new
app, hostname, or externally reachable route is introduced. Use
[docs/workflows/application-networking.md](./../workflows/application-networking.md)
for the operator sequence.

Use this file together with:

- [docs/rules/applications.md](./applications.md) for platform placement
- [docs/rules/kubernetes.md](./kubernetes.md) for Kubernetes-specific ingress rules
- [docs/rules/terraform.md](./terraform.md) for Terraform stage and tfvars rules

## Endpoint Ownership Rule

If an app is considered part of the homelab ecosystem and is meant to be used
through a domain, it must have bound subdomain records and reverse-proxy
configuration represented in code.

That means the app is not considered complete until all of these exist when the
endpoint is HTTP or HTTPS based:

- workload-side ingress or reachable upstream target
- `/mnt/eapp/config/nginx-proxy-manager/config.tfvars`
- `/mnt/eapp/config/cloudflare/config.tfvars`

Do not treat "the wildcard record exists" as sufficient. Each app needs its own
intentional hostname entry.

## Source-of-Truth Rule

Application networking must be expressed in repo-managed config, not manual UI
drift.

The usual sources of truth are:

- app manifests or Terraform service code for the upstream target
- `/mnt/eapp/config/nginx-proxy-manager/config.tfvars` for certificates and
  proxy hosts
- `/mnt/eapp/config/cloudflare/config.tfvars` for DNS records
- Terraform pipeline entrypoints for applying the Nginx Proxy Manager and
  Cloudflare changes

Do not leave a new hostname only in Nginx Proxy Manager UI, Cloudflare UI, or
browser memory.

## Naming Rules

Keep app names, subdomains, and tfvars object keys logically aligned.

Default naming rules:

- single-instance app hostname: `<app>.nodadyoushutup.com`
- multi-instance or role-qualified hostname: use dotted qualifiers that explain
  the instance, for example `qbittorrent.movie.0.nodadyoushutup.com`
- multi-endpoint app hostname set: use a stable product root plus role labels,
  for example `publex.gui.nodadyoushutup.com` and `publex.api.nodadyoushutup.com`

Keep the tfvars object names aligned with the hostname while following the file
format already used in the repo:

- certificate names and Cloudflare keys normally use underscore-delimited
  identifiers such as `qbittorrent_movie_0`
- hostname labels stay dotted in the actual DNS names such as
  `qbittorrent.movie.0.nodadyoushutup.com`

Choose names that match the app's repo identity unless the product already has
an established external name. Do not invent unrelated abbreviations or novelty
hostnames for new apps.

## MCP Server Hostname Rule

- MCP servers are a documented hostname-routed operator exception because the
  Codex host runs outside both the Swarm overlay and Kubernetes service
  networks and must consume them over HTTP.
- Use `mcp.<service>.nodadyoushutup.com` for the standard MCP hostname unless a
  task explicitly defines a different naming pattern.
- Keep the service route, the Nginx Proxy Manager proxy host, the Cloudflare
  record, and `~/.codex/config.toml` aligned for every host-usable MCP server.
- Do not point Codex or other host-side LLM tooling at raw Swarm node ports,
  cluster-only DNS names, or ad hoc NodePorts as the steady-state access
  pattern when a routed hostname exists.

## Internal vs Public DNS Rules

Default to internal-only routing unless a human explicitly asks for public
exposure.

Internal-only rule:

- point the Cloudflare record at the relevant internal RFC1918 address
- use the internal address that should receive the request in normal operation,
  typically the Nginx Proxy Manager host or another LAN-reachable entrypoint
- validate from inside the LAN or from another host that can route to that
  internal address

Public rule:

- use the WAN/public address only when the app is intentionally meant to work
  from outside the network
- ensure the firewall/NAT path is already part of the design before treating the
  domain as public
- validate through the real public path, not only against an internal IP

Current repo guidance:

- almost everything should stay internal-only by default
- `thelounge.nodadyoushutup.com` remains the normal end-user public exception
- MCP hostnames managed under [`docs/rules/mcp-servers.md`](./mcp-servers.md)
  are documented hostname-routed operator exceptions because the client host is
  off-platform

Do not point a new app at the public IP "just in case". Public exposure is an
explicit choice, not the default.

## Reverse Proxy Rules

For HTTP and HTTPS apps, the proxy host definition must match the intended
hostname and point at a stable upstream target.

Expected shape in `/mnt/eapp/config/nginx-proxy-manager/config.tfvars`:

- a certificate entry covering the app hostname or hostnames
- a `proxy_hosts` entry with the same `domain_names`
- `forward_host` and `forward_port` that reach the real app entrypoint

The DNS target and the proxy upstream target are different concerns:

- Cloudflare decides where the domain resolves
- Nginx Proxy Manager decides where the resolved request is forwarded

Keep both aligned with the same hostname set.

## Required Delivery Rule

When a new app or new hostname goes online, deliver the full endpoint in one
change flow:

1. make the app reachable at its upstream target
2. add or update the Nginx Proxy Manager certificate and proxy host entries
3. add or update the Cloudflare record
4. apply the Nginx Proxy Manager pipeline
5. apply the Cloudflare pipeline
6. validate the final hostname

Do not close the task with only the app manifest merged or only the DNS record
added.

## Validation Rule

A new app is not complete until the intended hostname is tested successfully.

Required validation:

- use `curl` or equivalent against the actual domain, not only the service IP
- prefer `curl -I`, `curl --fail`, or a simple application-specific health path
  when the app supports one
- for internal-only apps, run the validation from a host that can reach the
  internal target
- for public apps, validate through the public path

Examples:

```bash
curl -k --fail --silent --show-error -I https://prowlarr.nodadyoushutup.com/
curl -k --fail --silent --show-error https://thelounge.nodadyoushutup.com/
```

If DNS propagation timing is the only blocker, an interim `curl --resolve` check
is acceptable during rollout, but the task is not fully complete until the
normal hostname resolution path works too.
