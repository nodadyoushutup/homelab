resource "docker_network" "mcp_kubernetes" {
  name   = local.service_name
  driver = "overlay"
}

resource "docker_service" "mcp_kubernetes" {
  name = local.service_name

  dynamic "auth" {
    for_each = local.docker_service_pull_auth_map
    content {
      server_address = auth.value.server_address
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
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
      aliases = [local.service_name]
    }
    container_spec {
      image    = var.image_reference
      env      = local.effective_env
      user     = "65532"
      cap_drop = ["ALL"]
      args = [
        "--port",
        "8106",
        "--kubeconfig",
        local.kubeconfig_container_path,
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
      dynamic "mounts" {
        for_each = local.swarm_nfs_config_mounts
        content {
          type      = mounts.value.type
          source    = mounts.value.source
          target    = mounts.value.target
          read_only = try(mounts.value.read_only, false)
          dynamic "volume_options" {
            for_each = try(mounts.value.volume_options, null) != null ? [mounts.value.volume_options] : []
            content {
              driver_name    = volume_options.value.driver_name
              driver_options = volume_options.value.driver_options
              no_copy        = try(volume_options.value.no_copy, false)
            }
          }
        }
      }
    }
    restart_policy {
      condition    = "on-failure"
      delay        = "10s"
      max_attempts = 3
      window       = "2m"
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
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
