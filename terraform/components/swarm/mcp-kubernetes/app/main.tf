# main.tf
# Overlay network, kubeconfig Swarm config, and mcp-kubernetes Swarm service.

resource "docker_network" "mcp_kubernetes" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_config" "kubeconfig" {
  name = local.kubeconfig_config_name
  data = filebase64(local.kubeconfig_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "mcp_kubernetes" {
  name = local.service_name

  task_spec {
    force_update = local.kubeconfig_force

    dynamic "placement" {
      for_each = local.placement == null ? [] : [local.placement]

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
      aliases = [local.network_alias]
    }

    container_spec {
      # Literal tag for Renovate (not a var/local; no digest).
      image    = "quay.io/containers/kubernetes_mcp_server:v0.0.60"
      user     = local.container_user
      cap_drop = local.cap_drop
      args     = local.args

      dns_config {
        nameservers = local.dns_nameservers
      }

      configs {
        config_id   = docker_config.kubeconfig.id
        config_name = docker_config.kubeconfig.name
        file_name   = local.kubeconfig_mount
      }
    }
  }

  mode {
    replicated {
      replicas = local.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.target_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
