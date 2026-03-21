# Kubernetes Structure Guide

This document defines the repository pattern for Kubernetes so new workloads remain consistent with the existing GitOps layout.

## 1) Top-level Kubernetes layout

All Kubernetes artifacts live under `kubernetes/` and are split by responsibility.

```text
kubernetes/
  bootstrap/            # initial Argo CD root app bootstrap
  argocd-management/    # Argo CD Applications/AppProjects and Argo CD namespace config
  <addon>/              # shared platform addons (helm values + optional manifests)
  <app>/                # app manifests (namespace, deploy, svc, ingress, secrets, pvc, etc.)
  <app-with-kustomize>/ # base + overlays pattern (qbittorrent, cross-seed)
```

## 2) Control-plane ownership model

Kubernetes delivery in this repo is GitOps-first with Argo CD, but there are two layers of ownership:

1. Terraform-managed Argo CD objects (`terraform/cluster/argocd/config`) define:
   - `argocd-management` Application
   - `homelab-addons` ApplicationSet (platform apps like MetalLB, ingress-nginx, external-secrets, node-exporter, plus selected manifests)
2. Git-managed Argo CD app files under `kubernetes/argocd-management/` define additional `AppProject` and `Application` objects per service family.

## 3) Bootstrap flow

Bootstrap starts from:

- `kubernetes/bootstrap/argocd-management-app.yaml`

This template points Argo CD at `kubernetes/argocd-management`, which then fans out to other apps.

## 4) Directory patterns by workload type

### 4.1 Plain-manifest app directories

Most app folders (for example `prowlarr`, `radarr`, `sonarr`, `seerr`, `picsur`, `privatebin`, `thelounge`) follow this shape:

```text
kubernetes/<app>/
  namespace.yaml
  secretstore.yaml          # if app uses External Secrets
  externalsecret.yaml       # if app uses External Secrets
  pvc.yaml
  postgres-deployment.yaml  # when app has in-cluster postgres
  postgres-service.yaml
  postgres-init-configmap.yaml (optional)
  deployment.yaml
  service.yaml
  ingress.yaml
```

### 4.2 Helm-backed addon directories

Addon directories used by Argo CD Helm apps are value-centric:

```text
kubernetes/<addon>/
  values.yaml
  namespace.yaml            # optional; used when needed
  <extra-manifests>.yaml    # optional
```

Examples include `metallb`, `ingress-nginx`, `external-secrets`, `node-exporter`, `democratic-csi-*`, `snapshot-controller`, and `k10`.

### 4.3 Kustomize base/overlay families

`qbittorrent` and `cross-seed` use kustomize composition.

`qbittorrent` pattern:

```text
kubernetes/qbittorrent/
  base/
    kustomization.yaml
    deployment.yaml
    service.yaml
    service-torrent-nodeport.yaml
    ingress.yaml
    pvc.yaml
    qbittorrent-config-template.yaml
  overlays/<instance>/
    kustomization.yaml
    namespace.yaml
    runtime-config.yaml
    secretstore.yaml
    externalsecret.yaml
    ingress-patch.yaml
    deployment-node-patch.yaml
```

`cross-seed` pattern:

```text
kubernetes/cross-seed/
  base/
    kustomization.yaml
    deployment.yaml
    service.yaml
    pvc.yaml
    config-js.yaml
  overlays/<instance>/
    kustomization.yaml
    namespace.yaml
    runtime-config.yaml
    secret.yaml
    deployment-node-patch.yaml
```

## 5) Argo CD app/project conventions

For each new service family, define in `kubernetes/argocd-management`:

- one `AppProject` with allowed source repos and destination namespaces
- one or more `Application` resources pointing to the service path (or specific overlay path)

Existing convention:

- `AppProject` sync wave is lower than the service `Application` wave.
- `destination.namespace` matches the namespace declared in the service manifests.
- `source.path` points to a concrete folder under `kubernetes/`.

## 6) In-app sync wave conventions

Resource ordering inside app folders is usually controlled with `argocd.argoproj.io/sync-wave` annotations.

Common pattern:

- `10`: `SecretStore`
- `15`: `ExternalSecret`
- `18`: DB init `ConfigMap` (if needed)
- `20`: database deployment
- `30`: primary app deployment

Use this as the default unless an app has a clear reason for a different order.

## 7) Network and ingress conventions

- HTTP app exposure uses standard `Ingress` resources.
- BitTorrent peer traffic is not routed through HTTP ingress.
- qBittorrent peer ingress uses dedicated `NodePort` service entries for both TCP and UDP (`service-torrent-nodeport.yaml`) with per-instance unique ports set via overlays.

## 8) How to add a new Kubernetes app (compliant flow)

1. Create `kubernetes/<app>/` with `namespace.yaml` and workload manifests.
2. Add secret manifests (`secretstore.yaml`, `externalsecret.yaml`) if the app requires secrets.
3. Add or update `kubernetes/argocd-management/<app>-project.yaml`.
4. Add or update `kubernetes/argocd-management/<app>-app.yaml` with correct path and namespace.
5. If the app has an endpoint, also update Nginx Proxy Manager + Cloudflare Terraform tfvars/config and deploy via Terraform pipeline.
6. Apply manifests directly with `kubectl apply` for immediate rollout/validation, then let Argo CD reconcile.

## 9) Kustomize decision rule

Use plain manifests when there is one instance and limited variance.

Use kustomize when:

- multiple near-identical instances are required
- only hostnames/node placement/ports/secrets differ per instance
- you need replacements/patches to avoid duplicating a large base

## 10) Existing exceptions

- `cross-seed` overlay currently uses a plain Kubernetes `Secret` (`secret.yaml`) instead of `ExternalSecret`.
- Not every top-level app directory has a local `kustomization.yaml`; Argo CD often points directly at folders of plain manifests.

New work should follow the dominant conventions above unless there is a deliberate reason to diverge.
