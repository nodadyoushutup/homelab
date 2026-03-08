# Node Exporter Helm Migration Plan

## Goal
Migrate Kubernetes node-exporter from raw manifests to the upstream Prometheus Community Helm chart.

## Scope
- Update Argo CD ApplicationSet config to deploy:
  - chart: `prometheus-node-exporter`
  - repo: `https://prometheus-community.github.io/helm-charts`
  - release: `node-exporter`
- Replace `kubernetes/node-exporter` raw manifests with Helm `values.yaml`.
- Preserve existing runtime behavior (host networking/PID, tolerations, resource limits, scrape annotations, and pinned image digest).

## Validation Checklist
- [x] Terraform config renders `node-exporter-k8s` as a Helm app
- [x] `kubernetes/node-exporter` contains `values.yaml` only
- [x] Existing custom DaemonSet settings are represented in Helm values

## Completion
- [x] Migration changes prepared in repository
