# Container Image Workflow

This document is the source-of-truth workflow for repo-managed container image
builds, registry targets, and Harbor-specific image publishing. Use it when a
task touches:

- `.github/workflows/docker_build_push.yml`
- `applications/**/Dockerfile`
- `applications/harbor/**`
- `terraform/swarm/**` image references
- `/mnt/eapp/.tfvars/<service>/*.tfvars` registry auth or image tags

Use [docs/workflows/terraform.md](./terraform.md) when the task also deploys the
new image tag into Swarm. Use [docs/rules/mcp-servers.md](./../rules/mcp-servers.md)
for MCP-specific runtime guardrails.

## Current Harbor State

The repo and live environment currently agree on these Harbor basics:

- Terraform service roots: `terraform/swarm/harbor/app` and
  `terraform/swarm/harbor/config`
- Runtime host paths:
  `/mnt/eapp/harbor-manual/{harbor,data,log}`
- Live internal API URL:
  `http://192.168.1.120:35080`
- Live edge hostname:
  `http://harbor.nodadyoushutup.com`
- Live Harbor version from `/api/v2.0/systeminfo` on `2026-04-16`:
  `v2.14.2-3a2df66d`
- Live auth mode:
  `db_auth`
- Live project creation restriction:
  `everyone`

The Nginx Proxy Manager entry for `harbor.nodadyoushutup.com` forwards to
`192.168.1.120:35080` and disables request buffering so large pushes work.

Live Harbor projects reported by the API on `2026-04-16` after the Harbor
config apply:

- `langchain-agent-chat`
- `gha-runner`
- `harbor`
- `harbor-core`
- `harbor-db`
- `harbor-exporter`
- `harbor-jobservice`
- `harbor-log`
- `harbor-portal`
- `harbor-registryctl`
- `jenkins-agent`
- `jenkins-controller`
- `library`
- `mcp-argocd`
- `mcp-atlassian`
- `mcp-cloudflare`
- `mcp-fortigate`
- `mcp-github`
- `mcp-google-workspace`
- `nginx-photon`
- `prepare`
- `redis-photon`
- `registry-photon`
- `trivy-adapter-photon`
- `webserver-image`

## Current Registry Consumers

Current Swarm image consumption is mixed. Do not assume every custom image is on
the same registry.

| Runtime | Current image source | Source of truth |
| --- | --- | --- |
| `langchain-agent-chat` | Harbor | `kubernetes/langchain-agent-chat/deployment.yaml` plus `/mnt/eapp/.tfvars/harbor/config.tfvars` |
| `mcp-filesystem` | Harbor | `kubernetes/mcp-filesystem/deployment.yaml` plus `/mnt/eapp/.tfvars/harbor/config.tfvars` and `/mnt/eapp/.tfvars/vault/config.tfvars` |
| `gha-runner` | Harbor | `/mnt/eapp/.tfvars/gha-runner/app.tfvars` |
| `jenkins-controller` | Harbor | `/mnt/eapp/.tfvars/jenkins-controller/app.tfvars` |
| `mcp-cloudflare` | Harbor | `terraform/swarm/mcp-cloudflare/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-cloudflare/app.tfvars` |
| `mcp-ast-grep` | Local engine tag (`homelab/...`) | `terraform/swarm/mcp-ast-grep/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-ast-grep/app.tfvars` |
| `mcp-filesystem-homelab` | Local engine tag (`homelab/...`) | `terraform/swarm/mcp-filesystem-homelab/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-filesystem-homelab/app.tfvars` |
| `mcp-git-homelab` | Local engine tag (`homelab/...`) | `terraform/swarm/mcp-git-homelab/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-git-homelab/app.tfvars` |
| `mcp-github` | GHCR | `terraform/swarm/mcp-github/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-github/app.tfvars` |
| `mcp-fortigate` | GHCR | `terraform/swarm/mcp-fortigate/app/main.tf` plus `/mnt/eapp/.tfvars/mcp-fortigate/app.tfvars` |
| `mcp-google-workspace` | Local engine tag (`homelab/...`) | `terraform/swarm/mcp-google-workspace/app/main.tf` |
| Harbor runtime services | Local `goharbor/*:2.14.2-custom.1-arm64` tags on the Swarm node | `/mnt/eapp/.tfvars/harbor/app.tfvars` |

That last row matters: Harbor now has a publish path for its component images,
but the Harbor Swarm runtime does not yet consume those registry-backed tags.

## Shared GitHub Actions Workflow

The standard publish workflow is:

```text
.github/workflows/docker_build_push.yml
```

`workflow_dispatch` inputs:

- `version`: required output tag
- `target_registry`: `github` or `harbor`
- `build_target`:
  `langchain-agent-chat`, `harbor-runtime-set`, `mcp-cloudflare`, `mcp-filesystem`,
  `mcp-fortigate`, `mcp-github`, `mcp-google-workspace`, `gha-runner`, `jenkins-agent`,
  `jenkins-controller`

Registry naming rules:

- GHCR direct-image targets publish as:
  `ghcr.io/<owner>/<image>:<version>` and `:latest`
- Harbor direct-image targets publish as:
  `harbor.nodadyoushutup.com/<image>/<image>:<version>` and `:latest`
- `harbor-runtime-set` publishes all Harbor component images in one run:
  - GHCR:
    `ghcr.io/<owner>/<component>:<version>`
  - Harbor:
    `harbor.nodadyoushutup.com/<component>/<component>:<version>`

Harbor workflow credentials come from these GitHub Actions secrets:

- `HARBOR_ROBOT_USERNAME`
- `HARBOR_ROBOT_SECRET`

GHCR publishes use the repository-scoped `GITHUB_TOKEN`.

## Harbor Image Factory

Harbor component images are not built like the other direct Dockerfiles. They
are synced from upstream Harbor source and built as a coordinated runtime set.

Source of truth:

- `applications/harbor/versions.env`
- `applications/harbor/scripts/sync-components.sh`
- `applications/harbor/scripts/build-multiarch.sh`

Important behavior:

- `sync-components.sh` refreshes the component build files from the pinned
  Harbor upstream tag.
- `build-multiarch.sh` builds the full runtime set for `linux/amd64` and
  `linux/arm64`.
- `build-multiarch.sh` uses host `make` when available and otherwise falls back
  to a disposable `docker:27-cli` helper container, so older runners do not
  fail solely because GNU Make is missing.
- The script now supports registry-aware publish layouts:
  - `namespace-component` for GHCR-style paths
  - `project-per-image` for Harbor-style project-per-image paths

Harbor component set covered by the script:

- `harbor-core`
- `harbor-portal`
- `harbor-jobservice`
- `harbor-registryctl`
- `harbor-db`
- `registry-photon`
- `redis-photon`
- `nginx-photon`
- `harbor-log`
- `trivy-adapter-photon`
- `harbor-exporter`
- `prepare`

## Harbor Projects And Robot Access

Harbor project management is driven by:

- `terraform/swarm/harbor/config/main.tf`
- `terraform/swarm/harbor/config/config.tfvars.example`
- `/mnt/eapp/.tfvars/harbor/config.tfvars`

The `gha-publish` system robot is the publish account for repo-managed Harbor
images. The desired Harbor-managed project set now includes:

- Existing repo images:
  `langchain-agent-chat`, `gha-runner`, `harbor`, `jenkins-agent`, `jenkins-controller`,
  `mcp-argocd`, `mcp-atlassian`, `mcp-cloudflare`, `mcp-filesystem`, `mcp-fortigate`,
  `mcp-github`, `mcp-google-workspace`, `webserver-image`
- Harbor component images:
  `harbor-core`, `harbor-db`, `harbor-exporter`, `harbor-jobservice`,
  `harbor-log`, `harbor-portal`, `harbor-registryctl`, `nginx-photon`,
  `prepare`, `redis-photon`, `registry-photon`, `trivy-adapter-photon`

If Harbor config changes are meant to go live, run:

```bash
terraform/swarm/harbor/config/pipeline/config.sh
```

## Standard Change Flow

When adding or changing a repo-managed image:

1. Identify whether it is a direct Dockerfile build or part of the Harbor
   runtime set.
2. Update the Dockerfile or Harbor image factory sources under `applications/`.
3. If the image should publish to Harbor, make sure the Harbor project exists in
   `/mnt/eapp/.tfvars/harbor/config.tfvars` and the example tfvars.
4. If the workflow needs a new selectable target, add it to
   `.github/workflows/docker_build_push.yml`.
5. Publish the image through `workflow_dispatch`.
6. Update the Terraform image reference or tfvars for the consumer.
7. Run the matching Terraform app stage if deployment is part of the task.
8. Update this doc if the stable registry or build pattern changes.

## Validation

After changing image publish behavior:

1. Confirm the workflow still supports the expected build target and registry.
2. For Harbor publishes, confirm the target project exists before the push.
3. Confirm the published tag exists in the target registry.
4. If the image is deployed in Swarm or Kubernetes, confirm the matching
   Terraform config or manifest references that published tag.
