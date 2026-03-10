# Prowlarr Kubernetes rollout plan

This plan tracks deploying Prowlarr to Kubernetes with iSCSI-backed persistent storage, in-cluster PostgreSQL, Argo CD management, and public routing through Cloudflare + Nginx Proxy Manager.

## Stage 0 - scope lock

- [x] Confirm deployment model: Kubernetes manifests in `kubernetes/prowlarr` managed by Argo CD.
  Mark complete when: Argo CD `Application` points to `kubernetes/prowlarr`.
- [x] Confirm storage model: iSCSI-backed PVCs for both app config and PostgreSQL data.
  Mark complete when: PVCs use `storageClassName: truenas-iscsi-csi-retain`.

## Stage 1 - app manifests

- [x] Add `prowlarr` namespace, Vault `SecretStore`/`ExternalSecret`, PVCs, postgres deployment/service, prowlarr deployment/service, and ingress manifests.
  Mark complete when: `kubectl apply -f kubernetes/prowlarr` succeeds.
- [x] Configure Prowlarr to use PostgreSQL from first boot.
  Mark complete when: deployment sets `PROWLARR__POSTGRES__*` env vars and postgres pod is provisioned with matching DB/user creds.

## Stage 2 - Argo CD integration

- [x] Add a scoped Argo CD `AppProject` for Prowlarr.
  Mark complete when: project exists in `kubernetes/argocd-management`.
- [x] Add a child Argo CD `Application` for Prowlarr with automated sync (`prune` + `selfHeal`).
  Mark complete when: application exists in `kubernetes/argocd-management` and targets `kubernetes/prowlarr`.

## Stage 3 - secrets and edge routing

- [x] Add Vault secret payload at `secret/k8s/prowlarr` via `/mnt/eapp/.tfvars/vault/config.tfvars` and apply Vault config pipeline.
  Mark complete when: secret path resolves with required DB fields.
- [x] Ensure Cloudflare DNS points `prowlarr.nodadyoushutup.com` at the public homelab edge IP.
  Mark complete when: public resolvers return `96.253.53.3`.
- [x] Ensure Nginx Proxy Manager proxy host for `prowlarr.nodadyoushutup.com` forwards to Kubernetes ingress (`192.168.1.241:80`) with TLS cert.
  Mark complete when: NPM config has certificate + proxy host entries for Prowlarr.

## Stage 4 - validation

- [x] Verify Kubernetes rollout and storage binding.
  Mark complete when: prowlarr + postgres pods are Ready and both PVCs are `Bound`.
- [ ] Verify Argo CD app status from Git source.
  Mark complete when: `application/prowlarr` shows `sync=Synced` and `health=Healthy` after commit/push updates `kubernetes/prowlarr` in the tracked Git repository.
- [x] Verify public HTTPS reachability.
  Mark complete when: `https://prowlarr.nodadyoushutup.com` responds successfully with valid TLS.
