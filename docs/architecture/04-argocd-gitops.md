# Argo CD and GitOps

This file describes how **Argo CD** is wired in this repo: bootstrap, the
**`argocd-management`** bundle, **AppProject** vs **Application**, sync waves,
and how **Terraform** complements Git for a subset of cluster add-ons.

Kubernetes directory roles are summarized in
[03-kubernetes-layout.md](./03-kubernetes-layout.md).

## Layers (who owns what)

1. **`kubernetes/bootstrap/`** — One **root `Application`** manifest with
   placeholders (`__ARGOCD_GITOPS_*__`) for repo URL and revision. Used to teach
   a fresh Argo installation which path in Git contains the rest of the GitOps
   definitions. See `kubernetes/bootstrap/argocd-management-app.yaml`.

2. **`terraform/cluster/argocd/config/`** — Terraform **Argo CD provider**
   resources that manage specific high-level objects: for example the
   **`argocd_management`** `Application` that tracks
   `kubernetes/argocd-management`, and the **`homelab_addons`** `ApplicationSet`
   that expands into many Helm-or-manifest Applications with ordered sync waves.
   This keeps platform add-ons versioned in Terraform while still pulling chart
   values from the same Git repo.

3. **`kubernetes/argocd-management/`** — Git-tracked **projects**, workload
   **Applications**, and small Argo-facing config (notifications, exec RBAC,
   and similar). This is the main place to add a new first-party app’s Argo
   wiring once the workload manifests exist under `kubernetes/<app>/`.

## `argocd-management` contents

Typical file naming:

| Pattern | Purpose |
| --- | --- |
| `<logical-name>-project.yaml` | `AppProject`: allowed `sourceRepos`, allowed `destinations` (cluster + namespaces), resource whitelists. |
| `<logical-name>-app.yaml` or `<instance>-app.yaml` | `Application`: `spec.project`, `spec.source` (`repoURL`, `targetRevision`, `path` or Helm chart), `spec.destination`, `syncPolicy`. |

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

## ApplicationSet (`homelab-addons`)

Terraform defines an `argocd_application_set` whose **list generator** entries
describe add-ons: chart repo, chart version, destination namespace, Git path
for values, and `syncWave`. A **Go template** in `template_patch` switches
between:

- **`helm`** — multi-source Application: upstream chart + same homelab Git
  repo for `values.yaml` (and sometimes extra ref paths), and
- **`manifests`** — single-source Application pointing at a plain manifest
  directory in this repo.

That pattern keeps MetalLB, ingress-nginx, CSI drivers, External Secrets, and
similar stacks **consistent and ordered** without hand-writing dozens of nearly
identical Application YAML files. New entries of those types belong in the
ApplicationSet list in `terraform/cluster/argocd/config/main.tf` unless there is
a strong reason to promote them to a bespoke `Application` under
`argocd-management/`.

## Hand-written `Application` examples

Some stacks need **one-off** spec (inline Helm values, `ignoreDifferences`, or
non-standard sources). Those live as full YAML under `argocd-management/`, for
example the K10 Application that pulls `https://charts.kasten.io/` with inline
values—see `kubernetes/argocd-management/k10-app.yaml`.

LangGraph and Agent Chat use a **dedicated AppProject** each, `sourceRepos`
including this homelab repo (and extra Helm repo URLs when the app chart is
external), and an `Application` whose `path` is the workload directory—for
example `kubernetes/langgraph` in `kubernetes/argocd-management/langgraph-app.yaml`.

## Adding a new first-party app (checklist)

1. Add manifests (or Kustomize overlay) under `kubernetes/<app>/`.
2. Add `<app>-project.yaml` if you need isolation from `default` (recommended
   for anything non-trivial): restrict destinations and repos.
3. Add `<app>-app.yaml` with `spec.project` set to that project, `path` pointing
   at the new tree, and a sync wave **after** the project’s wave.
4. Prefer `syncPolicy.automated` with `CreateNamespace=true` and
   `ServerSideApply=true` to match existing Applications unless the workload
   forbids it.

If the new app is another **upstream Helm chart + values in this repo**, weigh
whether it belongs in the **ApplicationSet** list (platform-style, many similar
apps) or as its own **Application** under `argocd-management/` (special options).

## Related Terraform

The Argo CD **application** and **application set** resources live in
`terraform/cluster/argocd/config/`. Other Argo tuning (projects not in Git,
server settings) may also be represented there or in separate slices—follow
what already exists for the same concern before introducing a third pattern.
