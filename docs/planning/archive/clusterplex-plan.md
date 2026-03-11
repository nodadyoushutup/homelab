# ClusterPlex Kubernetes rollout plan

This plan tracks deploying ClusterPlex to Kubernetes using the upstream Helm chart, with direct NFS media from TrueNAS, CSI-backed config/transcode storage, ingress routing, and Argo CD integration.

## Stage 0 - scope lock

- [x] Confirm deployment model: upstream `clusterplex` Helm chart with repo-managed values.
  Mark complete when: chart values are defined in-repo and deployment succeeds.
- [x] Confirm media mount model: static NFS mount from `192.168.1.100:/mnt/epool/media`.
  Mark complete when: the media PV/PVC binds and is mounted in both PMS and worker pods.

## Stage 1 - app manifests

- [x] Add namespace + media storage manifests and chart values under `kubernetes/clusterplex`.
  Mark complete when: storage manifests apply cleanly and chart values are ready for install/sync.
- [x] Configure PMS and workers to share identical `/data` and `/transcode` paths.
  Mark complete when: both components mount the same media and transcode volumes.

## Stage 2 - Argo CD integration

- [x] Add a scoped Argo CD `AppProject` for ClusterPlex.
  Mark complete when: project manifest exists in `kubernetes/argocd-management`.
- [x] Add a child Argo CD `Application` for ClusterPlex with automated sync (`prune` + `selfHeal`).
  Mark complete when: application manifest exists in `kubernetes/argocd-management` and targets `kubernetes/clusterplex`.

## Stage 3 - validation

- [x] Verify Kubernetes rollout and storage binding.
  Mark complete when: orchestrator, PMS, and worker pods are Ready; PVCs are `Bound`.
- [x] Verify ingress routing for `clusterplex.nodadyoushutup.com`.
  Mark complete when: ingress is provisioned on the nginx ingress controller address.
- [ ] Verify Argo CD app sync from Git source.
  Mark complete when: `application/clusterplex` reports `sync=Synced` and `health=Healthy` after commit/push updates the tracked Git repository.
