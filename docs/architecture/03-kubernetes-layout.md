# Kubernetes layout

This file describes how **`kubernetes/`** is organized: top-level folders,
common manifest patterns, and how that tree relates to **Argo CD** and
**`applications/`**.

Argo CD projects, Applications, and the Git-managed `homelab-addons`
ApplicationSet are documented in [04-argocd-gitops.md](./04-argocd-gitops.md).

## Top-level folders

Everything under `kubernetes/` is **cluster-facing**: YAML, Helm values,
Kustomize roots, or small helper manifests. There is no hard requirement that
every subdirectory has an Argo `Application`—some are only referenced from the
`homelab-addons` ApplicationSet or from another manifest—but in practice most
long-lived workloads are GitOps-driven.

| Folder | Typical role |
| --- | --- |
| `bootstrap/` | **Seed** `Application` manifest (placeholder repo URL/revision) used once to point Argo at `kubernetes/argocd-management`. Not the ongoing source of truth for workloads. |
| `argocd-management/` | **GitOps control plane** for this repo: `AppProject` + `Application` CRs, `homelab-addons` ApplicationSet, plus Argo-local config. Synced via the Terraform-managed root Application—see [04-argocd-gitops.md](./04-argocd-gitops.md). |
| `metallb/`, `ingress-nginx/`, `external-secrets/`, `democratic-csi-*`, `node-exporter/` | **Platform add-ons**: usually `values.yaml` (+ `namespace.yaml` where needed) consumed by the **`homelab-addons`** ApplicationSet in `argocd-management/` (Helm chart from upstream, values from this path). **TrueNAS iSCSI block volumes:** [05-democratic-csi-truenas-iscsi.md](./05-democratic-csi-truenas-iscsi.md). |
| `langgraph/`, `langchain-agent-chat/` | **First-party workloads**: flat manifests (Deployments, Services, Ingress, ExternalSecrets, PVCs, …) and optional local `charts/` / `templates/` when the app ships chart fragments alongside raw YAML. |
| `qbittorrent/`, `cross-seed/` | **Kustomize** layouts: `base/` plus `overlays/<instance>/` when many similar instances differ by namespace, node placement, or secrets. |
| `clusterplex/`, `radarr/`, `sonarr/`, … | **Media and apps** as plain manifest bundles (or mixed patterns) per app. |
| `snapshot-controller/`, `picsur/`, `privatebin/`, `thelounge/`, … | Same idea: one directory per deployable unit or chart-values bundle. |

When you add a **new** app, pick an existing neighbor that matches the same
delivery style (plain YAML vs Kustomize vs values-only) and mirror its layout.

## Manifest patterns

### Plain manifest directory

A set of `*.yaml` files (and optional subfolders) at
`kubernetes/<name>/…` with no Kustomization. Argo uses the directory as a
recursive manifest source. Good for small stacks or generated-style layouts
similar to `kubernetes/langgraph/`.

### Helm values only (`values.yaml` + optional `namespace.yaml`)

Chart lives **outside** this path; Argo (often via the ApplicationSet) wires
`chart` + `chartRepo` + `targetRevision` and points `valueFiles` at
`kubernetes/<addon>/values.yaml`. Examples: `kubernetes/metallb/`,
`kubernetes/ingress-nginx/`.

### Kustomize (`base/` + `overlays/`)

Use when **many instances** share most of the spec. Root `kustomization.yaml`
may aggregate overlays (see `kubernetes/cross-seed/kustomization.yaml`). Each
Argo `Application` then targets a **single overlay path** (for example
`kubernetes/qbittorrent/overlays/books` in
`kubernetes/argocd-management/qbittorrent-books-app.yaml`).

### Helm chart + Git manifests (multi-source)

Upstream chart plus `values.yaml` and extra manifests from this repo in one Argo
`Application`—see `kubernetes/argocd-management/applications/ingress-nginx.yaml`.

## Relationship to `applications/`

- **`applications/`** builds **container images** and holds app logic (Docker
  builds, LangGraph code, MCP servers, etc.).
- **`kubernetes/<workload>/`** declares **how those images run** on the cluster
  (replicas, env, volumes, ingress, ExternalSecrets, resource limits).

Image tags and registry references in Kubernetes manifests should stay aligned
with whatever **CI** (GitHub Actions, Jenkins) publishes; the architecture split
is “build artifact in `applications/`” vs “runtime contract in `kubernetes/`”.

## Secrets and config

Many workloads use **External Secrets** (`ExternalSecret`, `SecretStore`) with
paths under each app directory. Cluster-wide operator install lives under
`kubernetes/external-secrets/` (Helm values pattern). Do not commit raw secret
values; keep examples as `*.example.yaml` where the repo already does so.

## Swarm vs Kubernetes (reminder)

Swarm stacks live under **`terraform/swarm/`**; cluster workloads live here under
**`kubernetes/`**. The same logical product may exist in both places for
different environments (for example LangGraph dev in Compose per `AGENTS.md`,
production under `kubernetes/langgraph/`).
