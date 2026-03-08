locals {
  service_name   = "mcp-argocd"
  network_name   = "mcp-argocd"
  internal_port  = 3000
  published_port = 18086

  runtime_env = merge(
    {
      ARGOCD_BASE_URL  = var.argocd_base_url
      ARGOCD_API_TOKEN = var.argocd_api_token
      MCP_READ_ONLY    = tostring(var.mcp_read_only)
    },
    var.argocd_insecure_skip_verify ? { NODE_TLS_REJECT_UNAUTHORIZED = "0" } : {}
  )
}

resource "docker_network" "mcp_argocd" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "mcp_argocd" {
  name = local.service_name

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.mcp_argocd.id
      aliases = [local.service_name]
    }

    container_spec {
      image = "ghcr.io/argoproj-labs/mcp-for-argocd:latest@sha256:ef703dc15d0534c5368f835ae4948ac212055a3486481a56b05e9eb042a4ea6f"

      command = [
        "node",
        "dist/index.js",
        "http",
        "--port",
        tostring(local.internal_port),
      ]

      env = local.runtime_env

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      healthcheck {
        test = [
          "CMD",
          "node",
          "-e",
          "fetch('http://127.0.0.1:3000/mcp',{headers:{'mcp-session-id':'healthcheck'}}).then(r=>process.exit(r.status<500?0:1)).catch(()=>process.exit(1))",
        ]

        interval     = "30s"
        timeout      = "10s"
        retries      = 5
        start_period = "30s"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  endpoint_spec {
    ports {
      target_port    = local.internal_port
      published_port = local.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
