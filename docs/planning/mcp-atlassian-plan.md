# MCP Atlassian (Swarm) plan

This plan tracks adding the first MCP server in Docker Swarm using the direct stack pattern under `terraform/swarm/mcp-atlassian/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/mcp-atlassian/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/swarm/dozzle/app` and `terraform/swarm/graphite/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-atlassian/app.tfvars`
  Mark complete when: files exist and app pipeline resolves them without custom flags.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/mcp-atlassian/app/provider.tf`
  - `terraform/swarm/mcp-atlassian/app/variables.tf`
  - `terraform/swarm/mcp-atlassian/app/main.tf`
  - `terraform/swarm/mcp-atlassian/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - pinned `ghcr.io/sooperset/mcp-atlassian` image digest
  - healthcheck on `/healthz`
  - non-secret runtime config hardcoded in Terraform (`transport`, `toolsets`, ports, read-only mode, logging)
  - tfvars inputs reduced to provider config + Jira/Confluence URL/username/token fields
  Mark complete when: stack is deployable with tfvars secret values populated.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/purge/mcp-atlassian.sh`
  - aliases in `scripts/purge/purge.sh` for `mcp-atlassian` and legacy spelling variants
  Mark complete when: `scripts/purge/purge.sh mcp-atlassian` resolves correctly.

## Validation notes

- Date: 2026-03-07
- Commands run:
  - `terraform fmt -recursive terraform/swarm/mcp-atlassian/app`
  - `terraform -chdir=terraform/swarm/mcp-atlassian/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/mcp-atlassian/app validate`
  - `bash -n terraform/swarm/mcp-atlassian/app/pipeline/app.sh scripts/purge/mcp-atlassian.sh scripts/purge/purge.sh`
  - `ls -ld /mnt/eapp/.tfvars/mcp-atlassian /mnt/eapp/.tfvars/mcp-atlassian/app.tfvars`

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

jira_url        = "https://<tenant>.atlassian.net"
jira_username   = "<email>"
jira_api_token  = "<token>"

confluence_url        = "https://<tenant>.atlassian.net/wiki"
confluence_username   = "<email>"
confluence_api_token  = "<token>"
```
