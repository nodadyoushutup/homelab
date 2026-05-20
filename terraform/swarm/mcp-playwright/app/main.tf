resource "docker_network" "mcp_playwright" {
  name   = local.service_name
  driver = "overlay"
}

resource "docker_service" "mcp_playwright" {
  name = local.service_name

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
      name    = docker_network.mcp_playwright.id
      aliases = [local.service_name]
    }

    container_spec {
      image = var.image_reference
      dir   = var.screenshot_dir

      args = [
        "--port",
        tostring(local.internal_port),
        "--host",
        "0.0.0.0",
        "--allowed-hosts",
        join(",", var.allowed_hosts),
        "--output-dir",
        var.output_dir,
        "--config",
        var.config_file,
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      dynamic "mounts" {
        for_each = local.swarm_nfs_code_mounts

        content {
          type      = mounts.value.type
          source    = mounts.value.source
          target    = mounts.value.target
          read_only = mounts.value.read_only

          volume_options {
            driver_name    = mounts.value.volume_options.driver_name
            driver_options = mounts.value.volume_options.driver_options
            no_copy        = mounts.value.volume_options.no_copy
          }
        }
      }

      healthcheck {
        test = [
          "CMD",
          "node",
          "-e",
          "const net=require('net');const s=net.connect(${local.internal_port},'127.0.0.1',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);",
        ]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "45s"
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
      target_port    = local.internal_port
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
