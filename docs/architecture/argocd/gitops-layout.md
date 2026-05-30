# Argo CD GitOps layout

Who owns what across bootstrap, Terraform, and the Git-tracked
**`argocd-management`** bundle.

Workload manifests live under `kubernetes/<app>/` — see
[kubernetes/README.md](../kubernetes/README.md). This file covers **Argo
registration** only.

## Three layers

### 1. Bootstrap seed — `kubernetes/bootstrap/`

One **root `Application`** manifest with placeholders (`__ARGOCD_GITOPS_*__`) for
repo URL and revision. Used on a **fresh Argo install** to teach Argo which Git
path contains the rest of GitOps.

File: `kubernetes/bootstrap/argocd-management-app.yaml`.

This is a **one-time bootstrap** artifact, not the ongoing source of truth for
individual workloads.

### 2. Terraform root Application — `terraform/cluster/argocd/config/`

The **Argo CD provider** manages a single `Application` named
**`argocd-management`** that tracks **`kubernetes/argocd-management`** recursively
(`directory.recurse: true` — required because manifests live under `applications/`
and `ops/`, not the directory root).

```20:28:terraform/cluster/argocd/config/main.tf
    source {
      repo_url        = "git@github.com:nodadyoushutup/homelab.git"
      target_revision = "HEAD"
      path            = "kubernetes/argocd-management"

      # Manifests live under applications/ and ops/ only; directory sources do not recurse by default.
      directory {
        recurse = true
      }
    }
```

**Prune is disabled** on this root app (`prune = false`) so a render-mode change
does not drop child `Application` CRs from the cluster.

**Everything else** Argo-related — per-stack `Application`s, `AppProject`s,
platform add-ons — is **Git-only** under `kubernetes/argocd-management/`.

### 3. Git registry — `kubernetes/argocd-management/`

| Subpath | Role |
| --- | --- |
| **`applications/`** | One `<name>.yaml` per stack — usually combined `AppProject` + `Application` (multi-doc YAML separated by `---`). |
| **`ops/`** | Argo-local config: notifications, terminal RBAC, healer CronJob, ingress, ExternalSecrets, MCP viewer RBAC. |

Argo syncs this tree **recursively** when the Terraform-managed root Application
is healthy.

## How a change reaches the cluster

1. Edit manifests under `kubernetes/<app>/` and/or
   `kubernetes/argocd-management/applications/<app>.yaml`.
2. Commit and push to the Git remote Argo watches.
3. Root **`argocd-management`** Application syncs new/updated child Applications.
4. Each child Application syncs its `path` or Helm `sources` to the destination
   namespace.
5. **Sync waves** order platform prerequisites before consumers — see
   [applications-and-sync-waves.md](./applications-and-sync-waves.md).

## Related paths

| Path | Role |
| --- | --- |
| `terraform/cluster/argocd/config/` | Terraform slice — bootstraps root Application only |
| `kubernetes/bootstrap/` | Initial Argo → Git path wiring |
| `kubernetes/argocd-management/` | All ongoing Application / AppProject CRs |
| `kubernetes/<app>/` | Workload manifests each Application points at |

Do not register workloads only in Terraform unless you are intentionally
extending the **single** root Application pattern.
