# MCP Google Workspace (Swarm) plan

This plan tracks adding a Google Workspace MCP server in Docker Swarm using the direct stack pattern under `terraform/swarm/mcp-google-workspace/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/mcp-google-workspace/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/swarm/mcp-github/app` plus `terraform/swarm/mcp-atlassian/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-google-workspace/app.tfvars`
  - service account json: `/mnt/eapp/.tfvars/mcp-google-workspace/service_account.json`
  Mark complete when: files exist and app pipeline resolves them without custom flags.
- [x] Runtime contract validated for service-account mode:
  - base package: `workspace-mcp==1.14.2`
  - custom patch: `docker/mcp-google-workspace/sitecustomize.py` forces delegated service-account auth (`WORKSPACE_MCP_USE_SERVICE_ACCOUNT=true`)
  - transport strategy: native streamable HTTP endpoint (`/mcp`) on container port `8086`
  - container image strategy: local pinned image `homelab/mcp-google-workspace:2026.03.09.1` for debug/cutover
  Mark complete when: runtime assumptions are confirmed before Terraform scaffold.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/mcp-google-workspace/app/provider.tf`
  - `terraform/swarm/mcp-google-workspace/app/variables.tf`
  - `terraform/swarm/mcp-google-workspace/app/main.tf`
  - `terraform/swarm/mcp-google-workspace/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - local pinned image tag `homelab/mcp-google-workspace:2026.03.09.1`
  - HTTP transport on `/mcp` with published port `18086`
  - service-account auth from tfvars (`workspace_service_account_file`, `workspace_delegated_user`)
  Mark complete when: stack is deployable with tfvars values populated.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/docker/purge/mcp-google-workspace.sh`
  - aliases in `scripts/docker/purge/purge.sh` for `mcp-google-workspace` and common variants
  Mark complete when: `scripts/docker/purge/purge.sh mcp-google-workspace` resolves correctly.

## Stage 3 - image publishing workflow

- [x] Add dedicated GH Actions build/push workflow:
  - `.github/workflows/mcp_google_workspace_build_push.yml`
  - image name: `ghcr.io/<owner>/mcp-google-workspace`
  Mark complete when: workflow parses and supports multi-arch publish (`linux/amd64`, `linux/arm64`).

## Validation notes

- Date: 2026-03-09
- Commands run:
  - `terraform fmt -recursive terraform/swarm/mcp-google-workspace/app`
  - `terraform -chdir=terraform/swarm/mcp-google-workspace/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/mcp-google-workspace/app validate`
  - `bash -n terraform/swarm/mcp-google-workspace/app/pipeline/app.sh scripts/docker/purge/mcp-google-workspace.sh docker/mcp-google-workspace/entrypoint.sh`
  - `docker build -t homelab/mcp-google-workspace:2026.03.09.1 docker/mcp-google-workspace`
  - `docker run --rm -d -p 38086:8086 -e WORKSPACE_MCP_DELEGATED_USER=user@example.com -e WORKSPACE_MCP_SERVICE_ACCOUNT_FILE=/run/workspace-mcp/service_account.json -v $(pwd)/.tmp/service_account.json:/run/workspace-mcp/service_account.json:ro homelab/mcp-google-workspace:2026.03.09.1`
  - `curl -sS http://127.0.0.1:38086/health`
  - `curl -sS -X POST http://127.0.0.1:38086/mcp -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"debug","version":"1.0"}}}'`

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

workspace_delegated_user      = "admin@example.com"
workspace_service_account_file = "/mnt/eapp/.tfvars/mcp-google-workspace/service_account.json"
workspace_tool_tier           = "complete"
workspace_read_only           = false
# optional:
# workspace_tools = "gmail drive calendar docs sheets"
```
