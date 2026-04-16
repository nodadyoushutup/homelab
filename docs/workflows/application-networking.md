# Application Networking Workflow

This document defines the operator workflow for putting an app online through a
domain in this repo. Use [docs/rules/application-networking.md](./../rules/application-networking.md)
for the steady-state rules that govern naming, DNS targets, and validation.

Use this workflow whenever:

- a new app gets a domain
- an existing app gets an additional hostname
- an app changes from internal-only to public exposure
- a proxy or DNS target changes for an app hostname

## Standard Flow

1. decide whether the hostname is internal-only or public
2. choose a hostname that matches the app naming pattern
3. make sure the upstream app target is reachable
4. update Nginx Proxy Manager tfvars
5. update Cloudflare tfvars
6. apply the edge pipelines
7. validate the final hostname with `curl`

The default answer in step 1 is internal-only unless a human explicitly asks
for public exposure.

If the app is a Swarm MCP server, also use
[`docs/workflows/mcp-servers.md`](./mcp-servers.md) because hostname routing
and `~/.codex/config.toml` alignment are part of the required delivery flow.

## Step 1: Choose Exposure Level

Decide the DNS target before editing records.

Internal-only:

- preferred for almost every app
- point the Cloudflare record at the relevant internal RFC1918 address
- validate from inside the network

Public:

- use only when the app must work from outside the network
- point the Cloudflare record at the WAN/public IP
- confirm the firewall/NAT path is part of the design
- validate through the public route

Current documented exception:

- `thelounge.nodadyoushutup.com` is public
- Swarm MCP hostnames are documented hostname-routed operator exceptions; keep
  them aligned with the host Codex config rather than treating them as raw-port
  only services

## Step 2: Choose The Hostname

Prefer hostnames that line up with the app identity.

Use these patterns:

- single-instance app: `<app>.nodadyoushutup.com`
- multi-instance app: `<family>.<class>.<instance>.nodadyoushutup.com`
- multi-endpoint app: `<product>.<role>.nodadyoushutup.com`

Examples already in use:

- `prowlarr.nodadyoushutup.com`
- `qbittorrent.movie.0.nodadyoushutup.com`
- `publex.api.nodadyoushutup.com`

When you add the tfvars objects:

- keep certificate names and Cloudflare keys underscore-delimited
- keep actual DNS labels dotted

## Step 3: Make The Upstream Reachable

Do not start with DNS first. The app should already be reachable behind the
proxy before the hostname is published.

Typical upstream preparation:

- Kubernetes app: apply the `Ingress`, `Service`, and related manifests
- Swarm app: apply the app stage so the service is listening on its target port
- special-case apps: confirm any custom Host header or upstream behavior first

If the app is not reachable by IP and port yet, stop and fix that before moving
to Nginx Proxy Manager or Cloudflare.

## Step 4: Update Nginx Proxy Manager tfvars

Edit `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`.

For each new hostname set:

1. add or update the matching `certificates` entry
2. add or update the matching `proxy_hosts` entry
3. keep `domain_names` aligned between the certificate and proxy host
4. set `forward_host` and `forward_port` to the real upstream target

If the hostname belongs to an MCP server, keep the proxy path assumptions
aligned with the MCP HTTP path the client will use.

The normal pipeline is:

```bash
terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh
```

## Step 5: Update Cloudflare tfvars

Edit `/mnt/eapp/.tfvars/cloudflare/config.tfvars`.

For each hostname:

1. add or update an explicit record in `records`
2. choose the correct target IP based on the exposure decision
3. keep the record key aligned with the app naming pattern

If the hostname belongs to an MCP server, use the same final hostname that the
host Codex config will reference.

Do not rely on the wildcard record as the only entry for a new app.

The normal pipeline is:

```bash
terraform/remote/cloudflare/config/pipeline/config.sh
```

## Step 6: Apply In Order

Use this order for a new endpoint:

1. app-side workload changes
2. `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh`
3. `terraform/remote/cloudflare/config/pipeline/config.sh`

This keeps the upstream and proxy path ready before publishing the DNS target.

If the app is an MCP server, update `~/.codex/config.toml` after the route is
ready and before closing the task.

## Step 7: Validate Through The Domain

Every new app that goes online must be tested through the intended domain.

Minimum validation:

- use `curl` against the actual hostname
- fail the task if the domain does not connect
- record whether the route is internal-only or public in the task summary when
  it matters

Examples:

```bash
curl -k --fail --silent --show-error -I https://radarr.nodadyoushutup.com/
curl -k --fail --silent --show-error https://thelounge.nodadyoushutup.com/
```

Validation expectations:

- internal-only hostnames must succeed from a LAN-reachable host
- public hostnames must succeed through the public route
- MCP hostnames must also succeed from the Codex host using the exact URL stored
  in `~/.codex/config.toml`
- if propagation is still settling, `curl --resolve` can be used as an interim
  rollout check, but normal hostname resolution must still be verified before
  the task is done

## Failure Handling

If the domain test fails:

1. confirm the upstream app target works by IP and port
2. confirm the Nginx Proxy Manager `domain_names`, `forward_host`, and
   `forward_port` are correct
3. confirm the Cloudflare record points at the intended internal or public IP
4. rerun the relevant pipeline
5. rerun the domain-level `curl` test

Do not close the task with "the service works locally" if the domain still
fails.
