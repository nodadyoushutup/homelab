resource "docker_network" "mcp_kubernetes" {
  name   = "mcp-kubernetes"
  driver = "overlay"
}

resource "docker_config" "kubeconfig" {
  name = "mcp-kubernetes-kubeconfig-${local.kubeconfig_hash}"
  data = filebase64(var.kubeconfig_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "mcp_kubernetes" {
  name = "mcp-kubernetes"

  task_spec {
    force_update = local.kubeconfig_force

    dynamic "placement" {
      for_each = var.placement == null ? [] : [var.placement]

      content {
        constraints = try(placement.value.constraints, null)

        dynamic "platforms" {
          for_each = try(placement.value.platforms, [])

          content {
            os           = platforms.value.os
            architecture = platforms.value.architecture
          }
        }
      }
    }

    networks_advanced {
      name    = docker_network.mcp_kubernetes.id
      aliases = ["mcp-kubernetes"]
    }

    container_spec {
      image    = "quay.io/containers/kubernetes_mcp_server:v0.0.60@sha256:766a7282e0536d951d805f72b562d89707eefb84d35dcfd96e31c410071f6164"
      user     = "65532"
      cap_drop = ["ALL"]
      args = [
        "--port",
        "8106",
        "--kubeconfig",
        "/etc/kubernetes/kubeconfig",
        "--cluster-provider",
        "kubeconfig",
        "--toolsets",
        "core,config",
        "--list-output",
        "yaml",
        "--read-only",
        "--disable-multi-cluster",
        "--stateless",
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      configs {
        config_id   = docker_config.kubeconfig.id
        config_name = docker_config.kubeconfig.name
        file_name   = "/etc/kubernetes/kubeconfig"
      }
    }
  }

  mode {
    replicated {
      replicas = var.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = 8106
      published_port = 18210
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
