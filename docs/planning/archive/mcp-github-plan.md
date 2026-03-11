# MCP GitHub (Swarm) plan

This plan tracks adding a GitHub MCP server in Docker Swarm using the direct stack pattern under `terraform/swarm/mcp-github/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/mcp-github/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/swarm/mcp-atlassian/app` plus `terraform/swarm/dozzle/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-github/app.tfvars`
  Mark complete when: files exist and app pipeline resolves them without custom flags.
- [x] Upstream runtime contract validated for Swarm:
  - image: `ghcr.io/github/github-mcp-server` (multi-arch includes `linux/arm64`)
  - PAT env var: `GITHUB_PERSONAL_ACCESS_TOKEN`
  - HTTP runtime command: `github-mcp-server http --port 8082`
  - `--toolsets=all` OAuth scopes summary: `gist`, `notifications`, `project`, `read:org`, `read:project`, `repo`, `security_events`
  Mark complete when: runtime assumptions are confirmed before Terraform scaffold.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/swarm/mcp-github/app/provider.tf`
  - `terraform/swarm/mcp-github/app/variables.tf`
  - `terraform/swarm/mcp-github/app/main.tf`
  - `terraform/swarm/mcp-github/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - pinned `ghcr.io/github/github-mcp-server` image digest
  - HTTP transport via `--toolsets all http --port 8082` (write operations enabled; no `--read-only`; lockdown mode disabled)
  - PAT sourced only from tfvars (`github_personal_access_token`)
  Mark complete when: stack is deployable with tfvars secret values populated.

- [x] Repository-scope expectation documented.
  - Upstream `github-mcp-server` does not expose a server-side `owner/repo` allowlist flag.
  - Active repository scoping should be enforced with a fine-grained PAT limited to selected repositories (change token in tfvars when switching scope).
  Mark complete when: repo-level scoping approach is explicit for operators.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/docker/purge/mcp-github.sh`
  - aliases in `scripts/docker/purge/purge.sh` for `mcp-github` and underscore/common name variants
  Mark complete when: `scripts/docker/purge/purge.sh mcp-github` resolves correctly.

## Stage 3 - no-client-auth proxy variant

- [x] Replace direct upstream image with a local proxy image:
  - image: `homelab/mcp-github:2026.03.08.4`
  - source: `docker/mcp-github/`
  - runtime: `mcp-proxy` (HTTP streamable endpoint at `/mcp`) launching `github-mcp-server stdio`
  - behavior: proxy passes server-side `GITHUB_PERSONAL_ACCESS_TOKEN` to stdio server so Codex clients do not need `bearer_token_env_var`.
  Mark complete when: unauthenticated MCP client `initialize` request succeeds end-to-end against the proxy.
- [x] Extend app pipeline pre-step to build proxy image on swarm manager:
  - `terraform/swarm/mcp-github/app/pipeline/app.sh`
  - env override: `MCP_GITHUB_REBUILD_IMAGE=1` forces rebuild.
  Mark complete when: pipeline can reuse or rebuild `homelab/mcp-github:2026.03.08.4` before Terraform apply.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt -recursive terraform/swarm/mcp-github/app`
  - `terraform -chdir=terraform/swarm/mcp-github/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/mcp-github/app validate`
  - `bash -n terraform/swarm/mcp-github/app/pipeline/app.sh scripts/docker/purge/mcp-github.sh scripts/docker/purge/purge.sh`
  - `ls -ld /mnt/eapp/.tfvars/mcp-github /mnt/eapp/.tfvars/mcp-github/app.tfvars`
  - `docker manifest inspect ghcr.io/github/github-mcp-server:latest | jq -r '.manifests[]?.platform | "\(.os)/\(.architecture)"'`
  - `docker run --rm ghcr.io/github/github-mcp-server --help`
  - `docker run --rm ghcr.io/github/github-mcp-server http --help`
  - `docker run --rm ghcr.io/github/github-mcp-server list-scopes --toolsets=all --output=summary`
  - `terraform/swarm/mcp-github/app/pipeline/app.sh`
  - `docker build -t homelab/mcp-github:2026.03.08.4 docker/mcp-github`
  - `docker run --rm -d -p 38087:8082 -e GITHUB_PERSONAL_ACCESS_TOKEN=<github-pat> homelab/mcp-github:2026.03.08.4`
  - `curl -X POST http://127.0.0.1:38087/mcp -H 'content-type: application/json' -H 'accept: application/json, text/event-stream' --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"debug","version":"1.0"}}}'`
  - `docker -H ssh://swarm-cp-0.local service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Ports}}'`
  - `docker -H ssh://swarm-cp-0.local service ps mcp-github --no-trunc --format 'table {{.Name}}\t{{.Node}}\t{{.DesiredState}}\t{{.CurrentState}}\t{{.Error}}'`
  - Authenticated MCP smoke test against `http://swarm-cp-0.local:18082/`:
    - `initialize` -> `200`, server `github-mcp-server v0.32.0`
    - `tools/list` -> `200`, `41` tools returned
    - `tools/call get_me` -> `200`, user payload returned

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

github_personal_access_token = "<github-pat>"
```
