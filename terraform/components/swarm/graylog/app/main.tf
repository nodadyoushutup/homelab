# main.tf
# Overlay network, volumes, and Graylog datanode + server Swarm services.

data "docker_network" "graylog_mongodb" {
  name = local.mongodb_network_name
}

resource "docker_network" "graylog_app" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "graylog_datanode" {
  name = local.datanode_volume_name
}

resource "docker_volume" "graylog_server" {
  name = local.server_volume_name
}

resource "docker_service" "graylog_datanode" {
  name = local.datanode_service_name

  task_spec {
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
      name    = docker_network.graylog_app.id
      aliases = [local.datanode_network_alias]
    }

    networks_advanced {
      name    = data.docker_network.graylog_mongodb.id
      aliases = []
    }

    container_spec {
      hostname = local.datanode_hostname
      # Literal tag for Renovate (not a var/local; no digest).
      image = "graylog/graylog-datanode:7.1.6"

      env = {
        GRAYLOG_DATANODE_NODE_ID_FILE    = local.datanode_node_id_file
        GRAYLOG_DATANODE_PASSWORD_SECRET = local.graylog_password_secret
        GRAYLOG_DATANODE_MONGODB_URI     = local.graylog_mongodb_uri
      }

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.datanode_data_mount
        source = docker_volume.graylog_datanode.name
        type   = "volume"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }
}

resource "docker_service" "graylog" {
  name = local.server_service_name

  task_spec {
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
      name    = docker_network.graylog_app.id
      aliases = [local.server_network_alias]
    }

    networks_advanced {
      name    = data.docker_network.graylog_mongodb.id
      aliases = []
    }

    container_spec {
      hostname = local.server_hostname
      # Literal tag for Renovate (not a var/local; no digest).
      image = "graylog/graylog:7.1.5"

      command = local.server_command

      env = {
        GRAYLOG_NODE_ID_FILE       = local.server_node_id_file
        GRAYLOG_PASSWORD_SECRET    = local.graylog_password_secret
        GRAYLOG_ROOT_PASSWORD_SHA2 = local.graylog_root_password
        GRAYLOG_HTTP_BIND_ADDRESS  = local.graylog_http_bind
        GRAYLOG_HTTP_EXTERNAL_URI  = local.graylog_http_external
        GRAYLOG_MONGODB_URI        = local.graylog_mongodb_uri
        GRAYLOG_SELFSIGNED_STARTUP = local.graylog_selfsigned_startup
      }

      dns_config {
        nameservers = local.dns_nameservers
      }

      mounts {
        target = local.server_data_mount
        source = docker_volume.graylog_server.name
        type   = "volume"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.ui_target_port
      published_port = local.published_port_ui
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.syslog_target_port
      published_port = local.published_port_syslog_tcp
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.gelf_target_port
      published_port = local.published_port_gelf_tcp
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
