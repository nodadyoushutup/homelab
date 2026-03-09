# Harbor (Swarm) plan

This plan tracks building and publishing custom multi-arch Harbor images for Docker Swarm, then wiring Harbor deployment in Terraform.

## Stage 1 - image factory bootstrap
- [x] Create `docker/harbor/` workspace with version pinning and scripts.
- [x] Add upstream sync workflow that materializes Harbor component Dockerfiles under `docker/harbor/<component>/`.
- [x] Add multi-arch build/publish script for `linux/amd64` and `linux/arm64` image manifests.
- [ ] Run first real push for all Harbor runtime components to the target registry namespace.

## Stage 2 - Swarm Terraform stack
- [ ] Create direct Swarm stages under `terraform/swarm/harbor/<stage>` (no module abstraction).
- [ ] Deploy Harbor data services (DB/Redis) and app services with pinned custom image tags.
- [ ] Configure persistent volumes, overlay networks, secrets/config, and health checks.
- [ ] Add pipeline entrypoints under `terraform/swarm/harbor/*/pipeline/`.

## Stage 3 - ingress and validation
- [ ] Add Nginx Proxy Manager cert/proxy config for Harbor hostname(s).
- [ ] Validate `docker login`, push, and pull over TLS.
- [ ] Validate Trivy scanner health and background jobs.

## Stage 4 - operations
- [ ] Add backup/restore runbook for Harbor DB + registry data.
- [ ] Add documented upgrade path for Harbor version bumps.
- [ ] Add image lifecycle policy (retention + garbage collection cadence).

## Notes
- Current Swarm nodes are `aarch64`; image builds must publish both `amd64` and `arm64` manifests.
- Terraform deployment work is intentionally staged after image factory success.
