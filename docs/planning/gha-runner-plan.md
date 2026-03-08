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

## Validation notes

- Date: 2026-03-08
- Commands run:
  - `terraform fmt terraform/swarm/gha-runner/app`
  - `bash -n terraform/swarm/gha-runner/app/pipeline/app.sh docker/gha-runner/entrypoint.sh scripts/docker/purge/gha-runner.sh scripts/docker/purge/purge.sh`
  - `terraform -chdir=terraform/swarm/gha-runner/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/gha-runner/app validate`
  - `terraform/swarm/gha-runner/app/pipeline/app.sh`
  - `docker -H ssh://swarm-cp-0.local service ls`
  - `docker -H ssh://swarm-cp-0.local service ps gha-runner --no-trunc`
  - `docker -H ssh://swarm-cp-0.local ps --filter label=com.docker.swarm.service.name=gha-runner`
  - `docker -H ssh://swarm-cp-0.local service logs --tail 40 gha-runner`
