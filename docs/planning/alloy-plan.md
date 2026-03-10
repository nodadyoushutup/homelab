# Alloy (Swarm) plan

This plan tracks deploying Grafana Alloy as a global Docker Swarm service to ship container logs from all Swarm nodes into Loki.

## Stage 0 - scope and inputs

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/alloy/app`) with one state.
- [x] Runtime source locked: `grafana/alloy` image with pinned digest.
- [x] Loki endpoint target locked: `http://loki:3100/loki/api/v1/push` over Swarm overlay network.
- [ ] Tfvars path locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/alloy/app.tfvars`
  - config file: `/mnt/eapp/.tfvars/alloy/config.alloy`

## Stage 1 - stack scaffold

- [x] Add stack files:
  - `terraform/swarm/alloy/app/provider.tf`
  - `terraform/swarm/alloy/app/variables.tf`
  - `terraform/swarm/alloy/app/main.tf`
  - `terraform/swarm/alloy/app/pipeline/app.sh`
- [x] Service runtime implemented:
  - global mode across Swarm nodes
  - arm64 platform targeting
  - Docker socket bind mount for local container discovery/log streaming
  - Alloy config delivered as Docker config with hash-based force update
  - attached to existing `loki` overlay network

## Stage 2 - deploy and verify

- [ ] Validate Alloy config syntax.
- [ ] Apply Terraform stack and verify Alloy tasks are healthy on all Swarm nodes.
- [ ] Verify logs are ingested into Loki from Alloy.

## Validation notes

- Date: 2026-03-10
- Commands planned:
  - `docker run --rm --entrypoint /bin/alloy grafana/alloy:latest validate /etc/alloy/config.alloy`
  - `terraform/swarm/alloy/app/pipeline/app.sh`
  - `docker -H ssh://swarm-cp-0.local service ls --format 'table {{.Name}}\t{{.Replicas}}' | rg alloy`
  - `docker -H ssh://swarm-cp-0.local service ps alloy --no-trunc`
  - `curl -G -fsS --data-urlencode 'query={cluster="swarm",collector="alloy"}' --data-urlencode "start=<ns>" --data-urlencode "end=<ns>" --data-urlencode 'limit=20' http://192.168.1.26:3100/loki/api/v1/query_range`
