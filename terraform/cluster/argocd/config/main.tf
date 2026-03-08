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
        prune     = true
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

resource "argocd_application_set" "homelab_addons" {
  lifecycle {
    ignore_changes = [
      metadata[0].annotations,
      spec[0].template_patch,
    ]
  }

  metadata {
    name      = "homelab-addons"
    namespace = "argocd"
  }

  spec {
    go_template         = true
    go_template_options = ["missingkey=error"]

    generator {
      list {
        elements = [
          {
            appType              = "helm"
            chartName            = "metallb"
            chartRepo            = "https://metallb.github.io/metallb"
            chartVersion         = "0.15.3"
            destinationNamespace = "metallb-system"
            gitPath              = "kubernetes/metallb"
            helmReleaseName      = "metallb"
            name                 = "metallb"
            syncWave             = "10"
          },
          {
            appType              = "helm"
            chartName            = "ingress-nginx"
            chartRepo            = "https://kubernetes.github.io/ingress-nginx"
            chartVersion         = "4.14.3"
            destinationNamespace = "ingress-nginx"
            gitPath              = "kubernetes/ingress-nginx"
            helmReleaseName      = "ingress-nginx"
            name                 = "ingress-nginx"
            syncWave             = "20"
          },
          {
            appType              = "helm"
            chartName            = "democratic-csi"
            chartRepo            = "https://democratic-csi.github.io/charts"
            chartVersion         = "0.15.1"
            destinationNamespace = "democratic-csi"
            gitPath              = "kubernetes/democratic-csi-iscsi"
            helmReleaseName      = "democratic-csi"
            name                 = "democratic-csi-iscsi"
            syncWave             = "25"
          },
          {
            appType              = "helm"
            chartName            = "democratic-csi"
            chartRepo            = "https://democratic-csi.github.io/charts"
            chartVersion         = "0.15.1"
            destinationNamespace = "democratic-csi-nfs"
            gitPath              = "kubernetes/democratic-csi-nfs"
            helmReleaseName      = "democratic-csi-nfs"
            name                 = "democratic-csi-nfs"
            syncWave             = "26"
          },
          {
            appType              = "helm"
            chartName            = "external-secrets"
            chartRepo            = "https://charts.external-secrets.io"
            chartVersion         = "2.1.0"
            destinationNamespace = "external-secrets"
            gitPath              = "kubernetes/external-secrets"
            helmReleaseName      = "external-secrets"
            name                 = "external-secrets"
            syncWave             = "27"
          },
          {
            appType              = "manifests"
            destinationNamespace = "monitoring"
            gitPath              = "kubernetes/node-exporter"
            name                 = "node-exporter-k8s"
            syncWave             = "28"
          },
          {
            appType              = "manifests"
            destinationNamespace = "thelounge"
            gitPath              = "kubernetes/thelounge"
            name                 = "thelounge"
            syncWave             = "30"
          },
          {
            appType              = "manifests"
            destinationNamespace = "picsur"
            gitPath              = "kubernetes/picsur"
            name                 = "picsur"
            syncWave             = "31"
          },
        ]
      }
    }

    template {
      metadata {
        name      = "{{.name}}"
        namespace = "argocd"
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{.syncWave}}"
        }
      }

      spec {
        project                = "default"
        revision_history_limit = 0

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{.destinationNamespace}}"
        }

        source {
          repo_url        = "git@github.com:nodadyoushutup/homelab.git"
          target_revision = "HEAD"
          path            = "{{.gitPath}}"
        }

        sync_policy {
          automated {
            prune     = true
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

    template_patch = <<-EOT
      spec:
        {{- if eq .appType "helm" }}
        source: null
        sources:
          - repoURL: '{{.chartRepo}}'
            chart: '{{.chartName}}'
            targetRevision: '{{.chartVersion}}'
            helm:
              releaseName: '{{.helmReleaseName}}'
              valueFiles:
                - '$values/{{.gitPath}}/values.yaml'
          - repoURL: git@github.com:nodadyoushutup/homelab.git
            targetRevision: HEAD
            ref: values
          - repoURL: git@github.com:nodadyoushutup/homelab.git
            targetRevision: HEAD
            path: '{{.gitPath}}'
        {{- else if eq .appType "manifests" }}
        source:
          repoURL: git@github.com:nodadyoushutup/homelab.git
          targetRevision: HEAD
          path: '{{.gitPath}}'
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
        {{- end }}
    EOT
  }
}
