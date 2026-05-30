# Docker images: GitHub Actions build and pull

This is the **default discipline** for publishing homelab-maintained container
images from this repository. Follow it whenever work produces or requires a new
**production** image (Swarm, Kubernetes, or shared GHCR tags).

## Principles

- **Do not** run local `docker build` / `docker push` to GHCR for these images
  unless the user explicitly asks for a **local-only** debug build. The canonical
  path is **GitHub Actions**.
- **Always** drive the workflow **Docker - Build and Push Image**
  (file `.github/workflows/docker_build_push.yml`) via `workflow_dispatch`.
- **Always** set **`target_registry`** to **`github`** unless the user explicitly
  requires Zot or both registries.
- **Always** set **`build_platforms`** to **`both`** so the workflow builds
  **linux/amd64** and **linux/arm64** when the selected `build_target` supports
  both. The workflow intersects this with per-target support (see exceptions).
- **Always** bump the publish **version** by **one patch** level: `1.2.3` →
  `1.2.4` (three-part semver). Do not skip versions or bump minor/major unless
  the user directs a different scheme for that release.
- **After** the workflow run **succeeds**, **pull** the image using the **same
  version tag** you dispatched (multi-arch manifest), then **deploy it and prove
  it is healthy online**. A finished build is **not** done until production (or
  the user’s target environment) is actually running the new tag and passing
  health checks.
- **Commit and push** are normal and expected to land image pins and GitOps
  changes—do not treat them as optional overhead for this flow.
- **Let CI run** on those commits when applicable; failing checks block calling
  the rollout complete.

## Workflow inputs (reference)

| Input | Required value (unless user overrides) |
| --- | --- |
| `version` | New semver after **+0.0.1** patch bump |
| `target_registry` | `github` |
| `build_platforms` | `both` |
| `build_target` | One of the workflow choices (default `cloud-image-repository`; e.g. `rag-engine`, `mcp-rag`, `langgraph`, …) |

Optional: read the workflow file for the authoritative list of `build_target`
values and special cases.

## Version source

Before bumping:

1. Identify the **image name** implied by `build_target` (e.g. `rag-engine`).
2. Derive the **current** published version from the **source of truth** you are
   updating—commonly:
   - **GHCR / GitHub Packages** tags for `ghcr.io/<owner>/<image_name>`,
   - **Terraform Swarm** `container_spec.image` in **`terraform/components/swarm/<svc>/<slice>/main.tf`**
     (or the documented tfvars exceptions: `controller_image`, `image_reference`,
     runner `image` / `agent_image`),
   - **Kubernetes** `image:` pins in manifests or Helm values,
   - or the **last successful** workflow run inputs (if nothing else is pinned).

Then set the dispatch `version` to **current patch + 1**. Update **every pin**
that selects the image (Swarm **`main.tf`** image strings, runner/tfvars
exceptions above, Kubernetes `Deployment`/`StatefulSet` **`image:`**, Argo-managed
manifests, etc.), **commit, push**, and drive the **deploy path** for that stack
(see below) so the running workload matches the tag you built.

## Architecture exceptions

Some `build_target` values only support **linux/amd64** in the workflow
(`langgraph`, `langchain-agent-chat`). For those, choose **`build_platforms`**
**`both`** anyway; the **prepare** job **filters** to supported platforms, so
only amd64 is built. Do not treat that as an error.

**Coordinator jobs** (`prepare`, `publish_direct_manifest`) use
`runs-on: [self-hosted, linux, homelab, build]`—no `amd64` / `arm64` label—so
either runner pool can execute checkout, bash, or manifest work when one
architecture pool is offline. Per-arch **build** jobs still require `amd64` or
`arm64` as appropriate.

## Published tags (GHCR)

For typical **direct** builds publishing to GitHub:

- **Multi-arch manifest:** `ghcr.io/<github_owner>/<image_name>:<version>` and
  `:latest`.
- **Per-arch:** `:<version>-amd64` and `:<version>-arm64` when both were built.

Prefer **`docker pull ghcr.io/<owner>/<image_name>:<version>`** so the local
engine selects the correct architecture from the manifest.

## Zot registry layout

When **`target_registry`** is **`zot`** or **`both`**, direct builds push to
**`<ZOT_REGISTRY>/<image_name>`** (flat namespace, no project prefix). The workflow sets
**`ZOT_REGISTRY`** to **`zot.nodadyoushutup.com`** (see `.github/workflows/docker_build_push.yml`).
The Jenkins/bash mirror **`scripts/docker/build_push.sh`** uses the same
layout via environment **`ZOT_REGISTRY`**. Pins in Terraform/Kubernetes should use that path
(for example **`zot.nodadyoushutup.com/langgraph:<tag>`**). Zot requires htpasswd auth;
set repository secrets **`ZOT_REGISTRY_USERNAME`** and **`ZOT_REGISTRY_PASSWORD`**
(matching **`.config/terraform/components/**`** `registry_auths` for
`zot.nodadyoushutup.com`). The workflow logs in to Zot before push when
`target_registry` is **`zot`** or **`both`**.

## Deploy and health (mandatory end state)

Publishing a tag is only half the job. **Finish** with whatever combination of
**Terraform apply**, **git commit/push + Argo CD sync**, **Swarm service
update**, or **Kubernetes rollout** actually moves the live workload to the new
image—and **confirm health**.

Pick the path that matches where the service runs:

| Where it runs | Typical repo touchpoints | How to roll forward |
| --- | --- | --- |
| **Docker Swarm** (Terraform-managed) | `terraform/components/swarm/<svc>/<slice>/main.tf` for image pins; slice tfvars under your config path for `env` / `placement` | Bump **`container_spec.image`** in **`main.tf`** (see [swarm-slices.md](../architecture/terraform/swarm-slices.md)), **`terraform apply`** (or `terraform/components/swarm/<svc>/pipeline/*.sh`). Exceptions: `jenkins-controller` (`controller_image`), `prometheus-pve-exporter` (`image_reference`), and `terraform/components/runners/*` (`image` / `agent_image` in tfvars). If the app exposes a **new public hostname**, also update Cloudflare and Nginx Proxy Manager tfvars—see [edge-dns-and-nginx-proxy.md](edge-dns-and-nginx-proxy.md). |
| **Kubernetes (Argo CD)** | `kubernetes/**`, `kubernetes/argocd-management/**` | Edit the manifest or Helm values that set **`image`**, **commit**, **push**, then **sync** the Argo CD application (CLI, UI, or **Argo CD MCP** when configured). Wait for sync healthy / rollout complete. For a **new `Ingress` host**, align **Cloudflare** (or DNS) with the ingress/LB target—see [edge-dns-and-nginx-proxy.md](edge-dns-and-nginx-proxy.md); Nginx Proxy Manager applies only when you front the name through the Swarm edge. |
| **Kubernetes (non-GitOps manual)** | manifests in repo or cluster-only | Apply or rollout per your process; still verify pods and probes. |

**Health expectations** (adapt to the service):

- HTTP apps: **`/healthz`**, **`/ready`**, or documented probe path returns success.
- Swarm: service tasks running, **`docker service ps`** stable, no failed tasks.
- Kubernetes: **`kubectl rollout status`**, pods **Ready**, failing probes resolved.
- Argo CD: application **Healthy** and **Synced** (or your org’s equivalent).

If a deploy step requires secrets, state backends, or cluster credentials the
agent cannot use, say exactly what is blocked and what a human must run; still
complete every automated step (pins, push, pipeline trigger, sync API) first.

## Agent / operator procedure

1. **`rag_search`** (or read this doc + `.github/workflows/docker_build_push.yml`)
   to confirm inputs, naming, and **where this image is deployed** (Swarm
   **`main.tf`** pins, runner/tfvars exceptions, K8s manifests, Argo app name).
2. Determine **next patch** `version` and **all pins** that must move; route
   file edits to the **`code`** specialist when needed.
3. Use **GitHub MCP** (or authenticated `gh workflow run`) to **dispatch** the
   workflow with the inputs above. Workflow id: **`docker_build_push.yml`**.
4. **Wait** for completion: poll with **`actions_list`** (`list_workflow_runs`)
   and/or watch the run returned from dispatch; use **`get_job_logs`** if the
   run fails.
5. On success, run **`docker pull`** on `ghcr.io/<owner>/<image_name>:<version>`
   (after `docker login ghcr.io` if required) when a local pull is part of your
   validation; **the required outcome is live rollout health**, not only a local
   pull.
6. **Commit and push** pin updates if they were not already merged; **watch**
   repository checks / follow-on **GitHub Actions** workflows triggered by the
   push when they gate quality.
7. **Apply Terraform** and/or **sync Argo CD** (and any other deploy step) so the
   environment runs the new tag.
8. **Verify health** with probes, service status, or Argo CD application status.
   Only then treat the container work as **complete**.

## GHCR `permission_denied: write_package`

The image **built** but **`docker push` to `ghcr.io/...` failed**. That is registry auth or package ACL—not a Dockerfile problem.

1. **Repo workflow token** — **Settings → Actions → General → Workflow permissions** must be **Read and write** (not read-only). The workflow also sets job-level `packages: write`.
2. **Orphan package** — A **`ghcr.io/<owner>/<image_name>`** package created outside the **`homelab`** workflow (for example via a personal PAT) may not appear under the repo **Packages** tab and can block `write_package`. Delete it under [your packages](https://github.com/users?tab=packages) or **Package settings → Manage Actions access** (grant **`homelab`** **Write**), then re-run the workflow so **`GITHUB_TOKEN`** publishes and links it like other images.
3. **Self-hosted runners** — Stale `~/.docker/config.json` creds can block push after a successful login. The workflow runs `docker logout ghcr.io` before login; re-run after pulling workflow fixes.
4. **Optional PAT** — Add repo secret **`GHCR_TOKEN`**: classic PAT with **`write:packages`**. The workflow uses `secrets.GHCR_TOKEN || github.token` for `docker/login-action`.
5. **Zot unblock** — Dispatch with **`target_registry`** **`zot`** or **`both`** and pin **`zot.nodadyoushutup.com/<image_name>:<version>`** in Terraform until GHCR is fixed.

## Break-glass

- **Compose dev** bind mounts (`docker/docker-compose.yml`) do not require this
  workflow for day-to-day code iteration; they also do not replace **prod**
  deploy + health when you were asked to ship a new image.
- Local **`docker compose build`** is fine when the user only needs a **dev**
  image on disk, not a published GHCR tag.

## Related

- RAG stack operators: [docs/rag/operators-and-clients.md](../rag/operators-and-clients.md)
- Technology index: [docs/resources/official-docs.md](../resources/official-docs.md)
  (Terraform, Argo CD, and Swarm entry points)
