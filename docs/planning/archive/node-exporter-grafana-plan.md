# Node Exporter Grafana Cross-Platform Plan

## Goal
Make Node Exporter Grafana overview panels work for both Docker Swarm node exporters and Kubernetes node exporters.

## Scope
- Update root disk PromQL in `terraform/swarm/grafana/config/dashboards/node-exporter-overview.json`.
- Use `mountpoint="/"` for `platform="docker"` and `mountpoint="/var"` for `platform="kubernetes"`.
- Apply Terraform Grafana config pipeline to publish dashboard updates.

## Validation Checklist
- [x] Root disk usage query returns series for Docker instances
- [x] Root disk usage query returns series for Kubernetes instances
- [x] Root disk I/O query returns series for Docker instances
- [x] Root disk I/O query returns series for Kubernetes instances

## Completion
- [x] Dashboard updates applied via Terraform pipeline
