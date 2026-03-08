# MCP ArgoCD (Swarm) plan

This plan tracks adding an Argo CD MCP server in Docker Swarm using the direct stack pattern under `terraform/docker/mcp-argocd/app`.

## Stage 0 - scope, references, and tfvars/backend

- [x] Taxonomy locked: app-only Swarm service (`terraform/docker/mcp-argocd/app`) with one state.
  Mark complete when: service path and stage boundary are explicit in this plan.
- [x] Reference implementation chosen: `terraform/docker/mcp-atlassian/app` plus `terraform/docker/mcp-github/app`.
  Mark complete when: new stack follows the same `provider.tf`, `variables.tf`, `main.tf`, and `pipeline/app.sh` surfaces.
- [x] Tfvars/backend paths locked:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/mcp-argocd/app.tfvars`
  Mark complete when: files exist and app pipeline resolves them without custom flags.
- [x] Upstream runtime contract validated for Swarm:
  - image: `ghcr.io/argoproj-labs/mcp-for-argocd` (multi-arch includes `linux/arm64`)
  - pinned digest: `sha256:ef703dc15d0534c5368f835ae4948ac212055a3486481a56b05e9eb042a4ea6f`
  - env vars: `ARGOCD_BASE_URL`, `ARGOCD_API_TOKEN`, optional `MCP_READ_ONLY`
  - HTTP endpoint path: `/mcp` on runtime port `3000`
  Mark complete when: runtime assumptions are confirmed before Terraform scaffold.

## Stage 1 - stack scaffold

- [x] Create stack files:
  - `terraform/docker/mcp-argocd/app/provider.tf`
  - `terraform/docker/mcp-argocd/app/variables.tf`
  - `terraform/docker/mcp-argocd/app/main.tf`
  - `terraform/docker/mcp-argocd/app/pipeline/app.sh`
  Mark complete when: Terraform init/validate and shell syntax checks pass.
- [x] App runtime spec implemented:
  - overlay network + replicated service
  - arm64 placement default on `swarm-cp-0`
  - pinned `ghcr.io/argoproj-labs/mcp-for-argocd` image digest
  - HTTP transport via `node dist/index.js http --port 3000`
  - healthcheck probes `/mcp` and accepts non-5xx response
  - read-only mode defaults to enabled (`mcp_read_only = true`)
  - optional TLS skip verify (`argocd_insecure_skip_verify = true` sets `NODE_TLS_REJECT_UNAUTHORIZED=0`)
  - pipeline token bootstrap: when `argocd_api_token` is missing/placeholder in tfvars, pipeline uses `argocd --core` to mint managed admin token id `mcp-argocd-swarm` and injects it via `-var` for plan/apply
  Mark complete when: stack is deployable with tfvars secret values populated.

## Stage 2 - operational parity

- [x] Add purge script and command routing:
  - `scripts/purge/mcp-argocd.sh`
  - aliases in `scripts/purge/purge.sh` for `mcp-argocd` and common name variants
  Mark complete when: `scripts/purge/purge.sh mcp-argocd` resolves correctly.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt -recursive terraform/docker/mcp-argocd/app`
  - `terraform -chdir=terraform/docker/mcp-argocd/app init -backend=false -input=false`
  - `terraform -chdir=terraform/docker/mcp-argocd/app validate`
  - `bash -n terraform/docker/mcp-argocd/app/pipeline/app.sh scripts/purge/mcp-argocd.sh scripts/purge/purge.sh`
  - `ls -ld /mnt/eapp/.tfvars/mcp-argocd /mnt/eapp/.tfvars/mcp-argocd/app.tfvars`
  - `docker buildx imagetools inspect ghcr.io/argoproj-labs/mcp-for-argocd:latest`
  - `npx -y argocd-mcp@0.5.0 http --help`

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

argocd_base_url              = "https://argocd.<domain>"
argocd_api_token             = "<argocd-api-token>"
mcp_read_only                = true
argocd_insecure_skip_verify  = false
```
