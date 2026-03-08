# Picsur Kubernetes rollout plan

This plan tracks deploying Picsur in Kubernetes with Vault-backed External Secrets, ingress routing, Cloudflare DNS, and Nginx Proxy Manager TLS for `picsur.nodadyoushutup.com`.

## Stage 0 - scope lock

- [x] Confirm deployment model: Kubernetes manifests in `kubernetes/picsur`, added to Argo app-of-apps as a manifests app.
  Mark complete when: app entry exists and points to `kubernetes/picsur`.
- [x] Confirm external access path: Cloudflare DNS -> Nginx Proxy Manager TLS -> ingress-nginx -> `picsur` service.
  Mark complete when: each hop is represented in config/manifests.

## Stage 1 - app manifests

- [x] Add `picsur` namespace, postgres PVC/service/deployment, picsur service/deployment, and ingress manifests.
  Mark complete when: `kubectl apply -f kubernetes/picsur` succeeds.
- [x] Use iSCSI storage class for postgres data.
  Mark complete when: PVC uses `storageClassName: truenas-iscsi-csi-retain`.

## Stage 2 - secrets and config

- [x] Add Vault secret payload at `secret/k8s/picsur` via `/mnt/eapp/.tfvars/vault/config.tfvars`.
  Mark complete when: Vault config pipeline applies successfully and secret path resolves.
- [x] Add `SecretStore` + `ExternalSecret` for Picsur.
  Mark complete when: `picsur-secrets` Kubernetes Secret is materialized.
- [x] Create namespace-local Vault reader secret (`picsur-vault-reader`) for External Secrets auth.
  Mark complete when: secret exists in namespace `picsur` with required key(s).

## Stage 3 - edge routing

- [x] Add NPM certificate and proxy host entries for `picsur.nodadyoushutup.com` in `/mnt/eapp/.tfvars/nginx-proxy-manager/config.tfvars`.
  Mark complete when: NPM config pipeline applies successfully.
- [x] Create/ensure Cloudflare DNS record for `picsur.nodadyoushutup.com`.
  Mark complete when: record resolves to homelab public edge IP.

## Stage 4 - validation

- [ ] Verify Kubernetes rollout (`pods`, `svc`, `ingress`, `externalsecret`) is healthy.
  Mark complete when: picsur + postgres pods are Ready and ingress resolves internally.
- [ ] Verify public HTTPS reachability and login page at `https://picsur.nodadyoushutup.com`.
  Mark complete when: endpoint returns HTTP 200 and serves Picsur UI.
