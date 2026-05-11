locals {
  service_name  = "playwright-mcp"
  network_name  = "playwright-mcp"
  internal_port = 8931
  config_file   = "${var.config_dir}/config.json"
}

module "code_nfs" {
  source = "../../../modules/homelab-nfs-mount"

  volume_name = "${local.service_name}-mnt-eapp-code"
  target      = "/mnt/eapp/code"
  device      = var.nfs_code_device
  nfs_server  = var.nfs_server
  read_only   = false
}

resource "docker_network" "playwright_mcp" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "playwright_mcp" {
  name = local.service_name

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.playwright_mcp.id
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
        local.config_file,
      ]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type      = module.code_nfs.mount.type
        source    = module.code_nfs.mount.source
        target    = module.code_nfs.mount.target
        read_only = module.code_nfs.mount.read_only

        volume_options {
          driver_name    = module.code_nfs.mount.volume_options.driver_name
          driver_options = module.code_nfs.mount.volume_options.driver_options
          no_copy        = module.code_nfs.mount.volume_options.no_copy
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
