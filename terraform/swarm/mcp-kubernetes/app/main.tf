locals {
  service_name                  = "mcp-kubernetes"
  network_name                  = "mcp-kubernetes"
  internal_port                 = 8106
  published_port                = 18106
  http_path                     = "/mcp"
  image                         = "quay.io/containers/kubernetes_mcp_server:v0.0.60@sha256:766a7282e0536d951d805f72b562d89707eefb84d35dcfd96e31c410071f6164"
  kubeconfig_target             = "/run/secrets/kubeconfig"
  kubeconfig_secret_file_name   = "kubeconfig"
  kubeconfig_file_content       = (trimspace(var.kubeconfig_file) != "" && fileexists(var.kubeconfig_file)) ? file(var.kubeconfig_file) : ""
  kubeconfig_secret_data_base64 = base64encode(local.kubeconfig_file_content)
  kubeconfig_secret_name        = "mcp-kubernetes-kubeconfig-${substr(sha256(local.kubeconfig_file_content), 0, 12)}"

  base_args = concat(
    [
      "--port", tostring(local.internal_port),
      "--kubeconfig", local.kubeconfig_target,
      "--toolsets", var.toolsets,
      "--list-output", var.list_output,
    ],
    var.mcp_read_only ? ["--read-only"] : [],
    var.disable_multi_cluster ? ["--disable-multi-cluster"] : [],
    var.stateless ? ["--stateless"] : []
  )
}

resource "docker_network" "mcp_kubernetes" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_secret" "kubeconfig" {
  name = local.kubeconfig_secret_name
  data = local.kubeconfig_secret_data_base64

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "mcp_kubernetes" {
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
      name    = docker_network.mcp_kubernetes.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image
      args  = local.base_args

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      secrets {
        secret_id   = docker_secret.kubeconfig.id
        secret_name = docker_secret.kubeconfig.name
        file_name   = local.kubeconfig_secret_file_name
      }

      healthcheck {
        test = [
          "CMD-SHELL",
          "code=$(curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:8106/mcp || echo 000); [ \"$code\" -lt 500 ]",
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

  lifecycle {
    precondition {
      condition     = trimspace(var.kubeconfig_file) != "" && fileexists(var.kubeconfig_file)
      error_message = "kubeconfig_file must be set to an existing local file path on the Terraform runner."
    }

    precondition {
      condition     = trimspace(var.toolsets) != ""
      error_message = "toolsets must not be empty."
    }

    precondition {
      condition     = contains(["yaml", "table"], var.list_output)
      error_message = "list_output must be either yaml or table."
    }

    replace_triggered_by = [
      docker_secret.kubeconfig
    ]
  }
}
