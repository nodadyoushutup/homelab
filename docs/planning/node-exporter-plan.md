# Node Exporter on Kubernetes Plan

## Goal
Deploy Kubernetes node-exporter as a DaemonSet so Prometheus/Grafana can monitor all Kubernetes nodes.

## Scope
- Add `kubernetes/node-exporter` manifests:
  - `namespace.yaml`
  - `serviceaccount.yaml`
  - `daemonset.yaml`
  - `service.yaml`
- Add `node-exporter-k8s` entry to `kubernetes/argocd/app-of-apps.yaml`.
- Apply manifests directly with `kubectl apply` for immediate rollout/validation.

## Validation Checklist
- [x] Namespace `monitoring` exists
- [x] DaemonSet `monitoring/node-exporter` is created
- [x] Desired/current/ready pod counts match schedulable node count
- [x] Service `monitoring/node-exporter` has endpoints
- [x] `/metrics` responds from at least one pod

## Notes
- This cluster currently has no in-cluster Prometheus Operator CRDs (`ServiceMonitor`/`PodMonitor`), so this change exposes scrape targets for external Prometheus configuration.

## Completion
- [x] Applied to cluster
- [x] Verified healthy
