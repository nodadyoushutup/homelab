# GitHub Actions Runner (Swarm) plan

This plan tracks adding a custom self-hosted GitHub Actions runner in Docker Swarm using the direct stack pattern under `terraform/swarm/gha-runner/app`.

## Stage 0 - scope and inputs

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/gha-runner/app`) with one state.
- [x] Runtime source locked: local image from `docker/gha-runner` based on `ubuntu:24.04`.
- [x] Tfvars path locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/gha-runner/app.tfvars`

## Stage 1 - stack scaffold

- [x] Add stack files:
  - `terraform/swarm/gha-runner/app/provider.tf`
  - `terraform/swarm/gha-runner/app/variables.tf`
  - `terraform/swarm/gha-runner/app/main.tf`
  - `terraform/swarm/gha-runner/app/pipeline/app.sh`
- [x] Service runtime implemented:
  - overlay network + replicated service
  - arm64 placement on `swarm-cp-0`
  - healthcheck from runner readiness file
  - env-driven runner registration settings

## Stage 2 - deploy and verify

- [x] Build image on Swarm manager via pipeline pre-step.
- [x] Apply Terraform stack and verify service reaches healthy running state.
- [ ] Update `github_runner_url` and `github_runner_token` in tfvars and re-apply for real GitHub registration.

## Stage 3 - docker buildx readiness (multi-arch)

- [x] Install source-of-truth scripts added under `scripts/install/`:
  - `scripts/install/docker.sh` (Docker install with host + container-friendly modes)
  - `scripts/install/packages.sh` (OS-detected package installer; currently Debian/Ubuntu apt)
- [x] `docker/gha-runner/Dockerfile` switched from `packages.apt` to install scripts.
- [x] Removed `docker/gha-runner/packages.apt` (script-based package installation only).
- [x] Runner runtime wired for Docker access:
  - bind mount `/var/run/docker.sock`
  - set `RUNNER_ALLOW_RUNASROOT=1`
  - run task user as `0:0` so Docker socket access is reliable for Buildx/QEMU setup.
- [x] Runner entrypoint now supports GitHub API-backed token minting via `GH_RUNNER_ACCESS_TOKEN` (registration + remove token endpoints) to avoid single-use token exhaustion.
- [ ] Rebuild/redeploy `gha-runner` image + service and re-run failing Jenkins build workflow.

## Stage 4 - ghcr image source of truth

- [x] Added dedicated workflow `.github/workflows/gha_runner_build_push.yml` for manual versioned multi-arch builds to GHCR.
- [x] Workflow requires `workflow_dispatch` input `version`.
- [x] Terraform runner service now uses variable `github_runner_image` (registry image reference) instead of local `docker build` in pipeline.
- [x] Removed local image-build pre-step from `terraform/swarm/gha-runner/app/pipeline/app.sh`.
- [ ] Set `/mnt/eapp/.tfvars/gha-runner/app.tfvars` `github_runner_image` to a published GHCR tag and apply.

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `bash -n scripts/install/docker.sh scripts/install/packages.sh`
  - `terraform fmt terraform/swarm/gha-runner/app`
  - `bash -n terraform/swarm/gha-runner/app/pipeline/app.sh docker/gha-runner/entrypoint.sh scripts/docker/purge/gha-runner.sh scripts/docker/purge/purge.sh`
  - `terraform -chdir=terraform/swarm/gha-runner/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/gha-runner/app validate`
  - `terraform/swarm/gha-runner/app/pipeline/app.sh`
  - `docker -H ssh://swarm-cp-0.local service ls`
  - `docker -H ssh://swarm-cp-0.local service ps gha-runner --no-trunc`
  - `docker -H ssh://swarm-cp-0.local ps --filter label=com.docker.swarm.service.name=gha-runner`
  - `docker -H ssh://swarm-cp-0.local service logs --tail 40 gha-runner`
  - `docker build --pull -f docker/gha-runner/Dockerfile -t homelab/gha-runner:verify-20260308 .`
  - `docker run --rm -u 0:0 -v /var/run/docker.sock:/var/run/docker.sock --entrypoint bash homelab/gha-runner:verify-20260308 -lc 'docker version --format "client={{.Client.Version}} server={{.Server.Version}}" && docker buildx version'`
  - `terraform/swarm/gha-runner/app/pipeline/app.sh`

## Current blocker

- Swarm service update is paused because new tasks require fresh GitHub runner registration and the configured `GH_RUNNER_TOKEN` returns `404` on `POST /actions/runner-registration`.
- To resolve permanently for replicated runners, set `github_runner_access_token` in `/mnt/eapp/.tfvars/gha-runner/app.tfvars` to a GitHub token with runner admin rights for the target repo/org.
- Existing `gha-runner:2026.03.08.3` task remains up; latest runner image code validated locally with working `docker` and `buildx` against mounted socket.
