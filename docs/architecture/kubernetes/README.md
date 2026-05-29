# Kubernetes layout

How **`kubernetes/`** is organized: workload classes, manifest delivery, GitOps
registration, and how the tree relates to **`applications/`**.

## Topics in this folder

| File | What it covers |
| --- | --- |
| [placement.md](./placement.md) | **Classify cluster workloads** (platform vs media vs first-party) and **node** pinning with `kubernetes.io/hostname`. |
| [manifest-patterns.md](./manifest-patterns.md) | Plain YAML, Helm values, Kustomize overlays, External Secrets, and `applications/` vs `kubernetes/` split. |

Argo CD registration and sync waves:
[argocd/README.md](../argocd/README.md).

## Adding a new app

Do **not** copy manifests before classifying the workload. Work through this order:

1. **Runtime** — Swarm, Kubernetes, or runner pool?
   [01-repository-layout.md](../01-repository-layout.md#swarm-versus-kubernetes)
2. **K8s workload class** — platform add-on, media/library app, or first-party
   production — and whether to pin a node.
   [placement.md](./placement.md)
3. **Delivery style** — plain YAML vs Kustomize vs Helm values-only.
   [manifest-patterns.md](./manifest-patterns.md)
4. **GitOps** — `AppProject` + `Application` under
   `kubernetes/argocd-management/applications/`.
   [argocd/applications-and-sync-waves.md](../argocd/applications-and-sync-waves.md)
5. **Image pin** — update manifest `image:` (or Helm values) after CI publish;
   commit, push, Argo sync. See
   [docker-build-github-actions.md](../../workflows/docker-build-github-actions.md).
6. **Public hostname** — cluster ingress + DNS when the app is edge-published
   ([edge-dns-and-nginx-proxy.md](../../workflows/edge-dns-and-nginx-proxy.md);
   Nginx Proxy Manager applies only when fronting through Swarm edge).

## Top-level folders under `kubernetes/`

Everything here is **cluster-facing**: YAML, Helm values, Kustomize roots, or
small helper manifests. Long-lived workloads are GitOps-driven through Argo CD.

| Folder | Typical role |
| --- | --- |
| `bootstrap/` | **Seed** `Application` with placeholder repo URL/revision — points a fresh Argo install at `kubernetes/argocd-management`. Not the ongoing workload source of truth. |
| `argocd-management/` | **GitOps control plane**: `applications/` (one file per stack), `ops/` (Argo-local config). Synced by the Terraform-managed root Application — [argocd/README.md](../argocd/README.md). |
| `metallb/`, `ingress-nginx/`, `external-secrets/`, `democratic-csi-*`, `node-exporter/`, `snapshot-controller/`, `velero/` | **Platform add-ons** — usually `values.yaml` (+ `namespace.yaml` where needed), wired from `argocd-management/applications/*.yaml`. Block storage: [argocd/storage-truenas-iscsi.md](../argocd/storage-truenas-iscsi.md). |
| `langgraph/`, `langchain-agent-chat/` | **First-party production** — flat manifests (Deployments, Services, Ingress, ExternalSecrets, PVCs). Images built from `applications/`. |
| `qbittorrent/`, `cross-seed/` | **Kustomize** — `base/` + `overlays/<instance>/` when many similar instances differ by namespace, node, or secrets. |
| `clusterplex/`, `radarr/`, `sonarr/`, `prowlarr/`, `seerr/`, `tautulli/`, `picsur/`, `privatebin/`, `thelounge/` | **Media and apps** — plain manifest bundles per deployable unit. |

When you add a directory, mirror a **neighbor in the same class and delivery
style** — see [manifest-patterns.md](./manifest-patterns.md).

## Swarm vs Kubernetes (reminder)

| Concern | Where it lives |
| --- | --- |
| Edge proxy, Swarm observability, MCP/RAG on Swarm | `terraform/swarm/` — [terraform/swarm-placement.md](../terraform/swarm-placement.md) |
| CI/CD (Jenkins, GHA runners) | Swarm `swarm-wk-1` + `terraform/runners/` — not Kubernetes |
| Production LangGraph + Agent Chat | `kubernetes/langgraph/`, `kubernetes/langchain-agent-chat/` |
| Media *arr stack, qBittorrent, Clusterplex | `kubernetes/<app>/` |
| Cluster ingress, CSI, MetalLB, ESO | `kubernetes/` platform add-ons |

LangGraph **dev** runs in Compose (`docker/docker-compose.yml` per `AGENTS.md`);
**prod** graph and chat run on Kubernetes only. Do not point dev chat at prod
backends.
