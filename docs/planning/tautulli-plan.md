# Tautulli Kubernetes rollout plan

This plan tracks deploying Tautulli to Kubernetes with iSCSI-backed persistent storage and Argo CD management.

## Stage 0 - scope lock

- [x] Confirm deployment model: Kubernetes manifests in `kubernetes/tautulli` managed by Argo CD.
  Mark complete when: Argo CD `Application` points to `kubernetes/tautulli`.
- [x] Confirm storage class: iSCSI-backed PVC.
  Mark complete when: PVC uses `storageClassName: truenas-iscsi-csi-retain`.

## Stage 1 - app manifests

- [x] Add `tautulli` namespace, PVC, deployment, service, and ingress manifests.
  Mark complete when: `kubectl apply -f kubernetes/tautulli` succeeds.
- [x] Pin to the latest stable upstream image tag.
  Mark complete when: deployment image is `tautulli/tautulli:v2.16.1` (latest release as of 2026-03-10).

## Stage 2 - Argo CD integration

- [x] Add a scoped Argo CD `AppProject` for Tautulli.
  Mark complete when: project exists in `kubernetes/argocd-management`.
- [x] Add a child Argo CD `Application` for Tautulli with automated sync (`prune` + `selfHeal`).
  Mark complete when: application exists in `kubernetes/argocd-management` and targets `kubernetes/tautulli`.

## Stage 3 - validation

- [x] Verify workload rollout and service exposure.
  Mark complete when: deployment is Available and pod Ready.
- [x] Verify storage binding.
  Mark complete when: `tautulli-config` PVC is `Bound`.
- [x] Verify Argo CD app is `Synced` and `Healthy` from Git source.
  Mark complete when: Argo CD `application/tautulli` shows `sync=Synced` and `health=Healthy`.

## Stage 4 - edge routing

- [x] Ensure Cloudflare DNS points `tautulli.nodadyoushutup.com` at the public homelab edge IP.
  Mark complete when: public resolvers return `96.253.53.3`.
- [x] Ensure Nginx Proxy Manager proxy host for `tautulli.nodadyoushutup.com` forwards to Kubernetes ingress (`192.168.1.241:80`).
  Mark complete when: NPM proxy host forward target is `192.168.1.241:80`.
- [x] Verify public HTTPS reachability.
  Mark complete when: `https://tautulli.nodadyoushutup.com` returns an app response and serves a valid cert.
