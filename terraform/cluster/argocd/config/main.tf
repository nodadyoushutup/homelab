resource "argocd_application" "argocd_management" {
  lifecycle {
    create_before_destroy = true
  }

  metadata {
    name      = "argocd-management"
    namespace = "argocd"
  }

  spec {
    project                = "default"
    revision_history_limit = 0

    destination {
      namespace = "argocd"
      server    = "https://kubernetes.default.svc"
    }

    source {
      repo_url        = "git@github.com:nodadyoushutup/homelab.git"
      target_revision = "HEAD"
      path            = "kubernetes/argocd-management"
    }

    sync_policy {
      automated {
        # App-of-apps: prune can drop child Application CRs when render mode changes.
        prune     = false
        self_heal = true
      }

      sync_options = [
        "CreateNamespace=true",
        "ServerSideApply=true",
        "SkipDryRunOnMissingResource=true",
      ]
    }
  }
}

# App registry: kubernetes/argocd-management/applications/ (synced recursively).
# Argo ops config: kubernetes/argocd-management/ops/
