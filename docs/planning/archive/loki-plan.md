# Loki (Swarm) plan

This plan tracks bringing up a first-pass Loki deployment on Docker Swarm using filesystem storage under `terraform/swarm/loki/app`.

## Stage 0 - scope and inputs

- [x] Taxonomy locked: app-only Swarm service (`terraform/swarm/loki/app`) with one state.
- [x] Runtime source locked: `grafana/loki` container image with pinned digest.
- [x] Initial storage mode locked: filesystem-backed Docker volume (temporary until S3 migration).
- [x] Tfvars path locked and created:
  - backend: `/mnt/eapp/.tfvars/minio.backend.hcl`
  - app tfvars: `/mnt/eapp/.tfvars/loki/app.tfvars`
  - config file: `/mnt/eapp/.tfvars/loki/config.yaml`

## Stage 1 - stack scaffold

- [x] Add stack files:
  - `terraform/swarm/loki/app/provider.tf`
  - `terraform/swarm/loki/app/variables.tf`
  - `terraform/swarm/loki/app/main.tf`
  - `terraform/swarm/loki/app/pipeline/app.sh`
- [x] Service runtime implemented:
  - overlay network + named volume
  - single replica placement on `swarm-cp-0` (arm64)
  - Loki config delivered as Docker config with hash-based force update
  - HTTP port `3100` published via ingress

## Stage 2 - deploy and verify

- [x] Apply Terraform stack and verify Loki reaches running state on `swarm-cp-0`.
- [x] Verify readiness and API:
  - `curl -fsS http://192.168.1.26:3100/ready`
  - `curl -fsS http://192.168.1.26:3100/loki/api/v1/status/buildinfo`
- [x] End-to-end API smoke:
  - `POST /loki/api/v1/push` succeeded (HTTP 204) for a `bootstrap_test` stream.
  - `GET /loki/api/v1/query_range` returned the pushed log line.

## Stage 3 - external hostname

- [x] Added Nginx Proxy Manager certificate + proxy host for `loki.nodadyoushutup.com` forwarding to `192.168.1.26:3100`.
- [x] Added explicit Cloudflare DNS `A` record:
  - `loki.nodadyoushutup.com -> 192.168.1.26` (non-proxied).
- [x] Verified HTTPS endpoint through hostname:
  - `curl -fsS https://loki.nodadyoushutup.com/ready`
  - `curl -fsS https://loki.nodadyoushutup.com/loki/api/v1/status/buildinfo`
- [x] Workaround note:
  - Full NPM config pipeline currently errors on an existing certificate refresh (`argocd` with 403 via provider).
  - Applied targeted Terraform for the new Loki cert + proxy host in `terraform/swarm/nginx_proxy_manager/config` to avoid blocking rollout.
- [x] Post-deploy config correction:
  - Added `common.instance_addr: 127.0.0.1` in `/mnt/eapp/.tfvars/loki/config.yaml` to eliminate internal scheduler/ingester timeout noise in single-binary mode.

## Validation notes

- Date: 2026-03-10
- Commands run:
  - `bash -n terraform/swarm/loki/app/pipeline/app.sh`
  - `terraform -chdir=terraform/swarm/loki/app init -backend=false -input=false`
  - `terraform -chdir=terraform/swarm/loki/app validate`
  - `docker run --rm -v /mnt/eapp/.tfvars/loki/config.yaml:/etc/loki/config.yaml:ro grafana/loki:3.4.2 -config.file=/etc/loki/config.yaml -verify-config=true`
  - `terraform/swarm/loki/app/pipeline/app.sh`
  - `docker -H ssh://swarm-cp-0.local service ls --format 'table {{.Name}}\t{{.Replicas}}\t{{.Ports}}' | rg 'NAME|loki'`
  - `docker -H ssh://swarm-cp-0.local service ps loki --no-trunc`
  - `docker -H ssh://swarm-cp-0.local service logs --since 2m --tail 120 loki`
  - `curl -fsS http://192.168.1.26:3100/ready`
  - `curl -fsS http://192.168.1.26:3100/loki/api/v1/status/buildinfo`
  - `curl -X POST http://192.168.1.26:3100/loki/api/v1/push ...`
  - `curl -G http://192.168.1.26:3100/loki/api/v1/query_range ...`
  - `terraform -chdir=terraform/swarm/nginx_proxy_manager/config apply ... -target='nginxproxymanager_certificate_letsencrypt.this["loki"]' -target='nginxproxymanager_proxy_host.this["loki_nodadyoushutup_com"]'`
  - `curl -fsS https://loki.nodadyoushutup.com/ready`
  - `curl -fsS https://loki.nodadyoushutup.com/loki/api/v1/status/buildinfo`
