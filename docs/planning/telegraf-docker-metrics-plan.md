# Telegraf Docker Metrics Migration Plan

## Goal
Replace cAdvisor in Docker Swarm with a Telegraf-based exporter that provides reliable per-container Docker metrics to Prometheus.

## Why
- cAdvisor is running but repeatedly fails container mapping (`mount-id` lookup errors) on current Docker runtime layout.
- Prometheus targets are `up`, but per-container cAdvisor series are effectively missing (`id!="/"` queries return no data).
- Telegraf `inputs.docker` reads from the Docker API socket and is compatible with this runtime pattern.
- Migration intent is permanent replacement: cAdvisor should be fully removed.

## Target Design
- Deploy Telegraf as a **global Swarm service** (one task per node), similar to node-exporter deployment model.
- Telegraf collects Docker metrics via `/var/run/docker.sock`.
- Telegraf exposes Prometheus metrics via `outputs.prometheus_client` on a dedicated host port.
- Prometheus scrapes Telegraf targets for all Swarm nodes.
- cAdvisor is removed immediately after Telegraf validation (no overlap window).

## Scope
- Add direct Swarm Terraform stage:
  - `terraform/swarm/telegraf_docker_metrics/app/provider.tf`
  - `terraform/swarm/telegraf_docker_metrics/app/variables.tf`
  - `terraform/swarm/telegraf_docker_metrics/app/main.tf`
  - `terraform/swarm/telegraf_docker_metrics/app/pipeline/app.sh`
- Add Telegraf config as a Terraform-managed Docker config (checked in repo, mounted into container).
- Add purge integration:
  - `scripts/docker/purge/telegraf-docker-metrics.sh`
  - register in `scripts/docker/purge/purge.sh`
- Update external Prometheus config (`/mnt/eapp/.tfvars/prometheus/prometheus.yaml`) to add Telegraf scrape job.
- Remove cAdvisor stack and scrape job in same migration once Telegraf validation passes.

## Non-Goals
- No Kubernetes changes.
- No Grafana dashboard rewrite in this phase (only data-source continuity checks and minimal query validation).

## Proposed Ports and Naming
- Service name: `telegraf-docker-metrics`
- Metrics endpoint: `:19273/metrics` (host publish mode)
- Prometheus job name: `telegraf_docker_metrics`

## Implementation Steps
1. Add Terraform stack for Telegraf global service.
2. Add Telegraf config with:
   - `[[inputs.docker]] endpoint = "unix:///var/run/docker.sock"`
   - `[[outputs.prometheus_client]]`
   - conservative scrape/collection intervals aligned with Prometheus.
3. Run Terraform plan/apply for Telegraf stack.
4. Validate Swarm service/task health on all nodes.
5. Add Prometheus scrape job for all Swarm node IPs on `19273`.
6. Apply Prometheus stack to reload config.
7. Validate data quality:
   - all Telegraf targets `up`
   - per-container series present (non-root container metrics)
   - basic CPU/memory/network per-container queries return expected values
8. Remove cAdvisor scrape job from Prometheus.
9. Remove cAdvisor Swarm stack via Terraform.

## Validation Checklist
- [x] `terraform plan` for Telegraf stage showed expected resource creation/update only.
- [x] Telegraf service is global and running on all eligible Swarm nodes.
- [x] `curl http://<node-ip>:19273/metrics` returns Prometheus-formatted metrics on every node (validated from swarm manager network plane).
- [x] Prometheus shows all `telegraf_docker_metrics` targets `up`.
- [x] Per-container metrics exist for running containers (not only host/root cgroup).
- [x] Existing host/node monitoring remains healthy (`node_exporter`, Prometheus).
- [x] cAdvisor removed after Telegraf validation.

## Risks and Mitigations
- Risk: Metric names differ from cAdvisor-backed dashboards.
  - Mitigation: validate key production queries before removing cAdvisor.
- Risk: Port conflict on chosen Telegraf host port.
  - Mitigation: verify current Swarm port usage before finalizing publish port.
- Risk: Docker socket access hardening differences across nodes.
  - Mitigation: validate on all nodes before cutover.

## Completion
- [x] Telegraf global stack deployed and healthy
- [x] Prometheus scraping Telegraf successfully
- [x] cAdvisor scrape removed
- [x] cAdvisor stack removed
- [x] Final verification complete
