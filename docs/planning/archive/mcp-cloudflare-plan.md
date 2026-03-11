# MCP Cloudflare DNS (Swarm) plan

This plan tracks adding a Cloudflare DNS MCP server in Docker Swarm using the direct stack pattern under `terraform/swarm/mcp-cloudflare/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/mcp-cloudflare/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/swarm/mcp-github/app` plus `terraform/swarm/mcp-fortigate/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-cloudflare/app.tfvars`
  Mark complete when: files exist and app pipeline resolves them without custom flags.
- [x] Runtime contract validated for DNS management:
  - official package `@cloudflare/mcp-server-cloudflare` is available, but current public release (`0.2.0`) does not expose DNS record CRUD tools
  - selected DNS-focused server: `@thelord/mcp-cloudflare@1.6.0`
  - transport strategy: `mcp-proxy` streamable HTTP endpoint at `/mcp`
  - container image strategy: build pinned local image `homelab/mcp-cloudflare:2026.03.08.1` from `docker/mcp-cloudflare/` in pipeline pre-step
  Mark complete when: runtime assumptions are confirmed before Terraform scaffold.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/mcp-cloudflare/app/provider.tf`
  - `terraform/swarm/mcp-cloudflare/app/variables.tf`
  - `terraform/swarm/mcp-cloudflare/app/main.tf`
  - `terraform/swarm/mcp-cloudflare/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - local pinned image tag `homelab/mcp-cloudflare:2026.03.08.1`
  - HTTP transport on `/mcp` via `mcp-proxy` on published port `18090`
  - Cloudflare auth/context from tfvars (`cloudflare_api_token`, `cloudflare_zone_id`, optional `cloudflare_email`)
  Mark complete when: stack is deployable with tfvars secret values populated.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/docker/purge/mcp-cloudflare.sh`
  - aliases in `scripts/docker/purge/purge.sh` for `mcp-cloudflare` and common variants
  Mark complete when: `scripts/docker/purge/purge.sh mcp-cloudflare` resolves correctly.

## Stage 3 - HTTPS edge in NPM

- [x] Add Nginx Proxy Manager tfvars entries:
  - certificate for `mcp.cloudflare.nodadyoushutup.com`
  - proxy host forwarding to `192.168.1.26:18090`
  Mark complete when: NPM config plan/apply includes Cloudflare MCP cert and proxy host.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt -recursive terraform/swarm/mcp-cloudflare/app`
  - `terraform -chdir=terraform/swarm/mcp-cloudflare/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/mcp-cloudflare/app validate`
  - `bash -n terraform/swarm/mcp-cloudflare/app/pipeline/app.sh scripts/docker/purge/mcp-cloudflare.sh scripts/docker/purge/purge.sh docker/mcp-cloudflare/entrypoint.sh`
  - `docker build --pull -t homelab/mcp-cloudflare:2026.03.08.1 docker/mcp-cloudflare`
  - `docker run -d -p 38089:8084 -e CLOUDFLARE_API_TOKEN=<token> -e CLOUDFLARE_ZONE_ID=<zone-id> homelab/mcp-cloudflare:2026.03.08.1`
  - `curl -X POST http://127.0.0.1:38089/mcp ... initialize`
  - `curl -X POST http://127.0.0.1:38089/mcp ... tools/list | jq -r '.result.tools[].name'`
  - `terraform/swarm/mcp-cloudflare/app/pipeline/app.sh`
  - `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh`
  - `curl -X POST http://192.168.1.26:18090/mcp ... initialize`
  - `curl -X POST https://mcp.cloudflare.nodadyoushutup.com/mcp ... initialize`

- Notes:
  - Local smoke test returned the DNS tools: `list_dns_records`, `get_dns_record`, `create_dns_record`, `update_dns_record`, `delete_dns_record`.
  - Initial startup can return brief `connection reset by peer` while `mcp-proxy` finishes bootstrapping the stdio server; retries succeeded.

## Tfvars schema (sanitized)

```hcl
provider_config = {
  docker = {
    host = "ssh://<user>@<swarm-manager-ip>"
    ssh_opts = [
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-i", "~/.ssh/id_ed25519"
    ]
  }
}

cloudflare_api_token = "<cloudflare-api-token-with-zone-read-and-zone-edit>"
cloudflare_zone_id   = "<cloudflare-zone-id>"
# optional:
# cloudflare_email   = "<cloudflare-account-email>"
```
