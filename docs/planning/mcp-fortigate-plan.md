# MCP FortiGate (Swarm) plan

This plan tracks adding a FortiGate MCP server in Docker Swarm using the direct stack pattern under `terraform/swarm/mcp-fortigate/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/mcp-fortigate/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/swarm/mcp-atlassian/app` plus `terraform/swarm/mcp-github/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-fortigate/app.tfvars`
  Mark complete when: files exist and app pipeline resolves them without custom flags.
- [x] Upstream runtime contract validated for Swarm:
  - source: `juststank/ftg_mcp` (no published public multi-arch image contract)
  - service transport: HTTP MCP endpoint path `/mcp`
  - container image strategy: build pinned local image `homelab/mcp-fortigate:2026.03.08.5` from `docker/mcp-fortigate/` in pipeline pre-step
  Mark complete when: runtime assumptions are confirmed before Terraform scaffold.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/mcp-fortigate/app/provider.tf`
  - `terraform/swarm/mcp-fortigate/app/variables.tf`
  - `terraform/swarm/mcp-fortigate/app/main.tf`
  - `terraform/swarm/mcp-fortigate/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - local pinned image tag `homelab/mcp-fortigate:2026.03.08.5`
  - HTTP transport on `/mcp` and published port `18084`
  - FortiGate auth from tfvars (`fortigate_api_token` or `fortigate_username`+`fortigate_password`)
  Mark complete when: stack is deployable with tfvars secret values populated.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/purge/mcp-fortigate.sh`
  - aliases in `scripts/purge/purge.sh` for `mcp-fortigate` and common variants
  Mark complete when: `scripts/purge/purge.sh mcp-fortigate` resolves correctly.

## Stage 3 - HTTPS edge in NPM

- [x] Add Nginx Proxy Manager tfvars entries:
  - certificate for `mcp.fortigate.nodadyoushutup.com`
  - proxy host forwarding to `192.168.1.26:18084`
  Mark complete when: NPM config plan/apply includes FortiGate MCP cert and proxy host.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt -recursive terraform/swarm/mcp-fortigate/app terraform/module/nginx_proxy_manager/config`
  - `terraform -chdir=terraform/swarm/mcp-fortigate/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/mcp-fortigate/app validate`
  - `terraform -chdir=terraform/swarm/nginx_proxy_manager/config init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/nginx_proxy_manager/config validate`
  - `bash -n terraform/swarm/mcp-fortigate/app/pipeline/app.sh scripts/purge/mcp-fortigate.sh scripts/purge/purge.sh`
  - `ls -ld /mnt/eapp/.tfvars/mcp-fortigate /mnt/eapp/.tfvars/mcp-fortigate/app.tfvars`
  - `MCP_FORTIGATE_REBUILD_IMAGE=1 terraform/swarm/mcp-fortigate/app/pipeline/app.sh`
  - `terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh`
  - `docker -H ssh://swarm-cp-0.local service inspect mcp-fortigate --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}'`
  - `docker -H ssh://swarm-cp-0.local service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Ports}}' | rg 'mcp-fortigate|nginx-proxy-manager'`
  - `docker -H ssh://swarm-cp-0.local service ps mcp-fortigate --no-trunc --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'`
  - `curl -X POST http://192.168.1.26:18084/mcp ... initialize`
  - `curl --resolve mcp.fortigate.nodadyoushutup.com:443:192.168.1.26 -k -X POST https://mcp.fortigate.nodadyoushutup.com/mcp ... initialize`

- Notes:
  - `terraform/swarm/nginx_proxy_manager/config` initially failed because `terraform/module/nginx_proxy_manager/config` was missing from the repo; module files were restored under that path before re-running the config pipeline.
  - Upstream `juststank/ftg_mcp` currently pulls `mcp` from GitHub `main`; this was incompatible with `fastmcp` at runtime. Image build now pins `mcp==1.24.0` after installing upstream package to keep `server_http` bootable.

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

fortigate_host        = "<fortigate-mgmt-ip-or-hostname>"
fortigate_port        = 443
fortigate_vdom        = "root"
fortigate_verify_ssl  = false
fortigate_timeout     = 30
fortigate_api_token   = "<fortigate-api-token>"
# Optional alternative auth:
# fortigate_username = "<username>"
# fortigate_password = "<password>"
```
