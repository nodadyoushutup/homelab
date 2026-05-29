# Argo CD applications and sync waves

How **`AppProject`** and **`Application`** CRs are shaped in this repo, how
**sync waves** order platform vs app rollouts, and how to register a new stack.

GitOps layout (bootstrap, Terraform root): [gitops-layout.md](./gitops-layout.md).

## AppProject vs Application

| Kind | Purpose |
| --- | --- |
| **`AppProject`** | Trust boundary — allowed `sourceRepos`, destination namespaces/clusters, resource whitelists. |
| **`Application`** | Binds a Git `path` or Helm `sources` to a destination namespace and `project`. |

Typical file: `kubernetes/argocd-management/applications/<name>.yaml` contains
**both** documents separated by `---`.

**Projects** scope what Argo may deploy. **Applications** declare what to deploy
and where.

### Multi-namespace families

Stacks with many instances (qBittorrent overlays) use **one `AppProject`**
listing every allowed namespace and **one `Application` per overlay**, each
with `spec.source.path` set to `kubernetes/qbittorrent/overlays/<instance>`.

See `kubernetes/argocd-management/applications/qbittorrent.yaml`.

## Source patterns

### Plain Git directory

```yaml
spec:
  source:
    repoURL: git@github.com:nodadyoushutup/homelab.git
    targetRevision: HEAD
    path: kubernetes/langgraph
```

**Examples:** `langgraph.yaml`, `radarr.yaml`, `clusterplex.yaml`.

### Helm multi-source (platform add-ons)

Upstream chart + values file from this repo + optional extra manifests:

```yaml
spec:
  sources:
    - repoURL: https://democratic-csi.github.io/charts
      chart: democratic-csi
      helm:
        valueFiles:
          - $values/kubernetes/democratic-csi-iscsi/values.yaml
    - repoURL: git@github.com:nodadyoushutup/homelab.git
      ref: values
    - repoURL: git@github.com:nodadyoushutup/homelab.git
      path: kubernetes/democratic-csi-iscsi
```

**Examples:** `metallb.yaml`, `ingress-nginx.yaml`, `democratic-csi-iscsi.yaml`,
`external-secrets.yaml`.

Mirror an existing platform file when adding another upstream chart.

## Sync waves

Resources and Applications use:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "25"
```

**Lower waves run first.** Leave gaps between numbers so new stacks can slot in
without renumbering everything.

### Illustrative platform ordering (repo today)

| Wave (approx.) | Stack |
| --- | --- |
| 9–10 | MetalLB |
| 19–20 | ingress-nginx |
| 24–26 | democratic-csi-iscsi, democratic-csi-nfs |
| 26–27 | external-secrets |
| 27–28 | node-exporter |
| 29 | snapshot-controller |
| 30+ | Media apps, Clusterplex, Velero, … |
| 47–48 | LangGraph |

**Storage drivers (waves ~24–29) must be Healthy before** PVC-backed apps that
use `truenas-iscsi-csi-retain`. See [storage-truenas-iscsi.md](./storage-truenas-iscsi.md).

Workload manifests can also carry sync-wave annotations (for example
`argocd.argoproj.io/sync-wave: "30"` on a Deployment) so resources inside an
Application apply in order.

## Default sync policy

Most Applications use:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

Match this unless a workload forbids automated prune/selfHeal.

The **root** `argocd-management` Application is the exception (`prune: false`) —
see [gitops-layout.md](./gitops-layout.md).

## Platform add-ons

MetalLB, ingress-nginx, democratic-csi (iSCSI + NFS), External Secrets,
node-exporter, snapshot-controller, and Velero are **individual files** under
`kubernetes/argocd-management/applications/`, not a single ApplicationSet.

Values and extra manifests live under `kubernetes/<addon>/`.

## Adding a new app (checklist)

1. Add manifests (or Kustomize overlay) under `kubernetes/<app>/` —
   [kubernetes/manifest-patterns.md](../kubernetes/manifest-patterns.md).
2. Add **`applications/<app>.yaml`** with:
   - **`AppProject`** (recommended for non-trivial apps) — restrict `destinations`
     and `sourceRepos`.
   - **`Application`** — `spec.project`, `path` or `sources`, destination namespace.
   - **Sync wave** after the project wave and **after** platform dependencies
     (CSI before PVC consumers).
3. For **upstream Helm + values in this repo**, copy `applications/metallb.yaml`
   or `applications/democratic-csi-iscsi.yaml`.
4. Commit, push, confirm root **`argocd-management`** syncs the new file, then
   confirm the child Application is **Healthy** / **Synced**.
5. If the app needs a **public hostname**, align ingress with DNS —
   [edge-dns-and-nginx-proxy.md](../../workflows/edge-dns-and-nginx-proxy.md).

## Hand-written Application specs

Some stacks need `ignoreDifferences`, extra Helm repos, or multi-source wiring.
Keep those as full YAML under `applications/` — for example
`ingress-nginx.yaml`, `qbittorrent.yaml`.

LangGraph and Agent Chat each use a dedicated **`AppProject`** and an
**`Application`** whose `path` is `kubernetes/langgraph` or
`kubernetes/langchain-agent-chat`.
