# Sonarr Kubernetes rollout plan

This plan tracks deploying Sonarr to Kubernetes with iSCSI-backed persistent storage, in-cluster PostgreSQL, Argo CD management, and public routing through Cloudflare + Nginx Proxy Manager.

## Stage 0 - scope lock

- [x] Confirm deployment model: Kubernetes manifests in `kubernetes/sonarr` managed by Argo CD.
  Mark complete when: Argo CD `Application` points to `kubernetes/sonarr`.
- [x] Confirm storage model: iSCSI-backed PVCs for both app config and PostgreSQL data.
  Mark complete when: PVCs use `storageClassName: truenas-iscsi-csi-retain`.

## Stage 1 - app manifests

- [x] Add `sonarr` namespace, Vault `SecretStore`/`ExternalSecret`, PVCs, postgres deployment/service, sonarr deployment/service, and ingress manifests.
  Mark complete when: `kubectl apply -f kubernetes/sonarr` succeeds.
- [x] Configure Sonarr to use PostgreSQL from first boot.
  Mark complete when: deployment sets `SONARR__POSTGRES__*` env vars and postgres pod is provisioned with matching DB/user creds.

## Stage 2 - Argo CD integration

- [x] Add a scoped Argo CD `AppProject` for Sonarr.
  Mark complete when: project exists in `kubernetes/argocd-management`.
- [x] Add a child Argo CD `Application` for Sonarr with automated sync (`prune` + `selfHeal`).
  Mark complete when: application exists in `kubernetes/argocd-management` and targets `kubernetes/sonarr`.

## Stage 3 - secrets and edge routing

- [x] Add Vault secret payload at `secret/k8s/sonarr` via `/mnt/eapp/.tfvars/vault/config.tfvars` and apply Vault config pipeline.
  Mark complete when: secret path resolves with required DB fields.
- [x] Ensure Cloudflare DNS points `sonarr.nodadyoushutup.com` at the public homelab edge IP.
  Mark complete when: public resolvers return `96.253.53.3`.
- [x] Ensure Nginx Proxy Manager proxy host for `sonarr.nodadyoushutup.com` forwards to Kubernetes ingress (`192.168.1.241:80`) with TLS cert.
  Mark complete when: NPM config has certificate + proxy host entries for Sonarr.

## Stage 4 - validation

- [x] Verify Kubernetes rollout and storage binding.
  Mark complete when: sonarr + postgres pods are Ready and both PVCs are `Bound`.
- [ ] Verify Argo CD app status from Git source.
  Mark complete when: `application/sonarr` shows `sync=Synced` and `health=Healthy` after commit/push updates `kubernetes/sonarr` in the tracked Git repository.
- [x] Verify public HTTPS reachability.
  Mark complete when: `https://sonarr.nodadyoushutup.com` responds successfully with valid TLS.
