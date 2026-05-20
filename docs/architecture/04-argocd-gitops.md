# Argo CD and GitOps

This file describes how **Argo CD** is wired in this repo: bootstrap, the
**`argocd-management`** bundle, **AppProject** vs **Application**, sync waves,
and how **Terraform** bootstraps the single root **`argocd-management`** Application.

Kubernetes directory roles are summarized in
[03-kubernetes-layout.md](./03-kubernetes-layout.md).

## Layers (who owns what)

1. **`kubernetes/bootstrap/`** — One **root `Application`** manifest with
   placeholders (`__ARGOCD_GITOPS_*__`) for repo URL and revision. Used to teach
   a fresh Argo installation which path in Git contains the rest of the GitOps
   definitions. See `kubernetes/bootstrap/argocd-management-app.yaml`.

2. **`terraform/cluster/argocd/config/`** — Terraform **Argo CD provider**
   manages only the **`argocd_management`** `Application` that tracks
   `kubernetes/argocd-management`. Everything under that path (including
   platform add-ons) is GitOps-managed.

3. **`kubernetes/argocd-management/`** — Git-tracked Argo registry synced recursively
   by the root Application (`spec.source.directory.recurse: true` — required because
   manifests live only under `applications/` and `ops/`, not the directory root).
   Layout:
   - **`applications/`** — one `<name>.yaml` per stack (AppProject + Application,
     or Application-only when using `default`)
   - **`ops/`** — Argo-local config (notifications, terminal RBAC, healer CronJob,
     ingress, ExternalSecrets, MCP viewer RBAC)

## `argocd-management` contents

Typical file naming under **`applications/`**:

| Pattern | Purpose |
| --- | --- |
| `<logical-name>.yaml` | Combined `AppProject` + `Application` (or Application only for `default`) |

**Projects** scope trust: which Git URLs and which namespaces Argo may touch.
**Applications** bind a path (or Helm sources) in Git to a destination namespace.

Multi-namespace families (for example many qBittorrent instances) use one
**project** listing every allowed namespace and **one Application per overlay**
each pointing at `kubernetes/qbittorrent/overlays/<instance>`.

## Sync waves

Manifests use the standard annotation so projects apply before applications
that depend on them, for example:

```7:8:kubernetes/argocd-management/langgraph-project.yaml
  annotations:
    argocd.argoproj.io/sync-wave: "47"
```

```7:8:kubernetes/argocd-management/langgraph-app.yaml
  annotations:
    argocd.argoproj.io/sync-wave: "48"
```

Use **lower waves** for cluster-scoped prerequisites (projects, RBAC) and
**higher waves** for workloads. Keep gaps (`40`, `47`, `48`, …) so new resources
can slot between existing waves without renumbering everything.

## Platform add-ons

MetalLB, ingress-nginx, CSI, External Secrets, and similar stacks live as
individual files under `applications/` (for example `applications/metallb.yaml`),
each with the same Helm multi-source or manifest pattern used elsewhere.

## Hand-written `Application` examples

Some stacks need **one-off** spec (`ignoreDifferences`, or multi-source Helm +
Git). Those live as full YAML under `argocd-management/`—see
`kubernetes/argocd-management/applications/ingress-nginx.yaml`.

LangGraph and Agent Chat use a **dedicated AppProject** each, `sourceRepos`
including this homelab repo (and extra Helm repo URLs when the app chart is
external), and an `Application` whose `path` is the workload directory—for
example `kubernetes/langgraph` in `kubernetes/argocd-management/applications/langgraph.yaml`.

## Adding a new first-party app (checklist)

1. Add manifests (or Kustomize overlay) under `kubernetes/<app>/`.
2. Add `<app>-project.yaml` if you need isolation from `default` (recommended
   for anything non-trivial): restrict destinations and repos.
3. Add `applications/<app>.yaml` with `spec.project` set to that project, `path`
   pointing at the new tree, and a sync wave **after** the project’s wave.
4. Prefer `syncPolicy.automated` with `CreateNamespace=true` and
   `ServerSideApply=true` to match existing Applications unless the workload
   forbids it.

If the new app is another **upstream Helm chart + values in this repo**, add
`applications/<app>.yaml` following the platform files (for example
`applications/metallb.yaml`).

## Related Terraform

Only the root **`argocd_management`** `Application` lives in
`terraform/cluster/argocd/config/`. All other Argo CRs belong under
`kubernetes/argocd-management/`.
