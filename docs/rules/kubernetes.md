# Kubernetes Rules

This document defines the baseline Kubernetes rules for this repo. Use it for
layout, ownership, naming, and guardrails. Use
[docs/rules/applications.md](./applications.md) when deciding whether a new app
belongs in Kubernetes or Swarm. Use
[docs/rules/application-networking.md](./application-networking.md) for app
hostname, DNS, and reverse-proxy rules. Use
[docs/rules/argocd.md](./argocd.md) for Argo CD ownership and GitOps guardrails,
[docs/workflows/kubernetes.md](./../workflows/kubernetes.md) for the operator flow,
and [docs/rules/repo.md](./repo.md) for repo-wide rules that also apply here.

## Top-Level Layout

All Kubernetes code lives under `kubernetes/`. The top-level directories are
split by responsibility rather than by team or environment.

Current patterns in the repo include:

- `kubernetes/bootstrap` for initial root-app bootstrap
- `kubernetes/argocd-management` for `Application` and `AppProject` objects
- addon directories such as `metallb`, `ingress-nginx`, `external-secrets`,
  `node-exporter`, `snapshot-controller`, and `k10`
- app directories such as `prowlarr`, `radarr`, `sonarr`, `seerr`,
  `privatebin`, `picsur`, and `thelounge`
- kustomize families such as `qbittorrent` and `cross-seed`

## Ownership Model

Kubernetes delivery is GitOps-first, but this repo has two control layers:

1. Terraform-managed Argo CD resources under `terraform/cluster/argocd/config`
2. Git-managed application/project definitions under `kubernetes/argocd-management`

That means:

- Argo CD bootstrap and some platform wiring come from Terraform
- service app definitions and projects are maintained in `kubernetes/`

Do not blur those layers when adding new work.

## Bootstrap Rule

The root bootstrap manifest is:

- `kubernetes/bootstrap/argocd-management-app.yaml`

It points Argo CD at `kubernetes/argocd-management`, which is the control point
for additional app and project definitions.

## Directory Patterns

### Plain-manifest applications

Most single-instance applications use a flat manifest directory such as:

```text
kubernetes/<app>/
  namespace.yaml
  secretstore.yaml
  externalsecret.yaml
  pvc.yaml
  postgres-deployment.yaml
  postgres-service.yaml
  deployment.yaml
  service.yaml
  ingress.yaml
```

Not every app needs every file. Keep only the manifests the app actually uses.

### Helm-backed addons

Platform addons are usually value-driven:

```text
kubernetes/<addon>/
  values.yaml
  namespace.yaml
  <extra-manifests>.yaml
```

When an upstream chart needs repo-local companion manifests or repo-owned
values as the source of truth, a local wrapper Helm chart is also acceptable:

```text
kubernetes/<app>/
  Chart.yaml
  values.yaml
  templates/
```

## Helm Versus Custom App Rule

When adding a new Kubernetes workload, assess whether an upstream `Helm` chart
is actually an easy fit or whether the workload should be a repo-owned custom
app under `kubernetes/`.

Repo preference:

- default application workloads to repo-owned custom manifests
- use `Helm` when the chart already matches the desired deployment shape with
  minimal overrides
- use a repo-local wrapper chart when the upstream chart is the right runtime
  but the repo still needs companion manifests such as namespace, secrets,
  database, or ingress-adjacent wiring kept alongside values
- keep treating `k10`, `snapshot-controller`, and similar platform addons as
  the reference pattern for Helm-backed installs
- treat `radarr`, `sonarr`, `privatebin`, `clusterplex`, and `qbittorrent` as
  the reference pattern for repo-owned app workloads

Why this repo usually prefers custom apps:

- direct control of containers, config, and repo-local assets is clearer in our
  own manifests
- direct `nfs:` mounts from known exports are often simpler here than forcing
  the workload through provisioned NFS PVC patterns
- storage paths, service layout, and app-specific wiring stay explicit in code

If the app needs repo-specific storage wiring, direct NFS bindings, or custom
container composition, prefer a repo-owned app even if a community chart
exists.

### Kustomize families

Use a `base/` plus `overlays/<instance>/` structure when there are multiple
near-identical instances with a shared base.

Use [docs/workflows/kubernetes-kustomize-patterns.md](./../workflows/kubernetes-kustomize-patterns.md)
for the qBittorrent reference workflow.

Existing examples:

- `kubernetes/qbittorrent/base` plus `kubernetes/qbittorrent/overlays/*`
- `kubernetes/cross-seed/base` plus `kubernetes/cross-seed/overlays/*`

For a new Kubernetes app, agents must not decide on their own whether the app
should be a plain manifest app or a `Kustomize app`. That shape decision is
human-gated and must be explicitly provided by the human for new app work.

## Argo CD Rules

For a new service family managed through Argo CD:

1. create or update an `AppProject` in `kubernetes/argocd-management`
2. create one or more `Application` objects in `kubernetes/argocd-management`
3. point each `Application.spec.source.path` at the exact manifest or overlay path
4. keep `destination.namespace` aligned with the namespace defined in the workload

Existing repo conventions:

- project sync waves are lower than application sync waves
- applications commonly use automated sync with `prune` and `selfHeal`
- `CreateNamespace=true` and `ServerSideApply=true` are normal sync options
- repo-managed applications normally track `HEAD` from the homelab repo
- the persistent delivery path is commit plus push, then Argo CD autosync

## Sync Wave Rules

This repo uses `argocd.argoproj.io/sync-wave` annotations to order resources.
The common in-app pattern is:

- `10` for `SecretStore`
- `15` for `ExternalSecret`
- `18` for DB init `ConfigMap`
- `20` for database deployment
- `30` for the primary app deployment

Use this as the default ordering unless the workload has a specific reason to
deviate.

## Kustomize Decision Rule

For existing design guidance after the human has chosen the app shape:

Use plain manifests for a `standard app` when:

- there is one instance
- the workload shape is simple
- per-instance variation is low

Use `Kustomize app` when:

- there are multiple similar instances
- hostnames, ports, namespaces, or node placement vary by instance
- replacements or patches are cleaner than duplicating full manifests

The qBittorrent overlays are the reference pattern for `Kustomize app`
families.

## Networking Rules

- Standard web applications should use `Ingress`.
- New public endpoints must also be represented in Terraform-managed Nginx Proxy
  Manager and Cloudflare config.
- Every app that is intended to be reachable through a domain must have explicit
  bound subdomains created in code.
- Default new app DNS targets to internal RFC1918 addresses unless a human
  explicitly asks for public exposure.
- BitTorrent peer traffic must not use HTTP reverse proxying.

For qBittorrent-style torrent ingress:

- expose a dedicated `NodePort` service for both TCP and UDP
- keep per-instance torrent ports unique
- represent the external FortiGate VIP and firewall policy in code
- validate both in-cluster reachability and external forwarded-port reachability

## Secrets Rules

Prefer External Secrets where the app already follows that model. The common
pattern is:

- `secretstore.yaml`
- `externalsecret.yaml`

For Vault-backed Kubernetes secrets, the source of truth is:

- `/mnt/eapp/.tfvars/vault/config.tfvars`
- `terraform/swarm/vault/config`

Use [docs/workflows/kubernetes-vault-secrets.md](./../workflows/kubernetes-vault-secrets.md)
for the operator workflow.

That Terraform stage writes grouped `secrets` and `secret_files` entries into
Vault KV v2 under:

- `<group>/<secret_name>`

The default mount path is currently `secret`, and the common Kubernetes group is
`k8s`, so most app manifests should reference paths such as `k8s/prowlarr`,
`k8s/argocd`, or `k8s/qbittorrent_movie_10`.

Repo rules for this pattern:

- `SecretStore` should point at the Vault `secret` mount using KV `v2`
- each namespace needs its own Vault token secret, usually named
  `<app>-vault-reader`
- that token secret must exist in the same namespace as the `SecretStore`
- `ExternalSecret.spec.data[].remoteRef.key` must match the Vault path exactly
- tfvars-driven group and secret names are restricted to lowercase alphanumeric,
  `-`, and `_` by Terraform validation, so new Terraform-driven secret paths
  should stay in the supported `<group>/<name>` shape
- do not introduce new deeper path segments such as `k8s/<app>/<instance>` in
  tfvars-driven workflows; flatten multi-instance names instead

If a workload already uses a plain Kubernetes `Secret`, treat that as an
existing exception rather than the default pattern.

## Operational Rules

- Kubernetes delivery should end with a committed and pushed Git revision that
  Argo CD can reconcile.
- For Argo CD-managed apps, commit and push all relevant workload,
  `argocd-management`, and doc files together when they are part of one change.
- Use clear commit subjects that name the service and intent.
- Direct `kubectl apply` is an exception path for bootstrap, debugging, or
  recovery, not the steady-state way to lock in app changes.
- After cluster-wide disruptive work, verify Argo CD health before closing the task.

## Storage and Safety Rules

- Do not delete, rename, or destroy datasets.
- New Kubernetes-related datasets may only be created under `eapp/k8s/...`.
- Dataset deletion is manual-only by a human.

## Existing Exceptions

- `cross-seed` currently uses a plain `secret.yaml`
- `k10/secret-k10-s3-secret.example.yaml` is an example static secret manifest,
  not a Vault-backed automation path
- not every top-level Kubernetes app directory has its own local
  `kustomization.yaml`
- some apps are plain manifest folders while Argo CD points directly at that
  folder instead of a kustomize root
