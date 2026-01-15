locals {
  stack_name = "nginx-proxy-manager"
  # Order matches Swarm's platform reporting (aarch64 then arm64) to avoid churny platform diffs.
  allowed_platforms = [
    {
      os           = "linux"
      architecture = "aarch64"
    },
    {
      os           = "linux"
      architecture = "arm64"
    }
  ]

  timezone = coalesce(
    try(var.provider_config.timezone, null),
    "UTC",
  )

  puid = coalesce(
    try(var.provider_config.puid, null),
    "1000",
  )

  pgid = coalesce(
    try(var.provider_config.pgid, null),
    "1000",
  )

  published_ports = {
    http  = 80
    https = 443
    admin = 81
  }

  initial_admin_email = coalesce(
    try(var.provider_config.nginx_proxy_manager.username, null),
    "admin@example.com",
  )

  initial_admin_password = coalesce(
    try(var.provider_config.nginx_proxy_manager.password, null),
    "changeme",
  )

  env = {
    INITIAL_ADMIN_EMAIL    = local.initial_admin_email
    INITIAL_ADMIN_PASSWORD = local.initial_admin_password
  }
}

resource "docker_network" "nginx_proxy_manager" {
  name   = local.stack_name
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_data" {
  name   = "${local.stack_name}-data"
  driver = "local"
}

resource "docker_volume" "nginx_proxy_manager_letsencrypt" {
  name   = "${local.stack_name}-letsencrypt"
  driver = "local"
}

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_service" "nginx_proxy_manager" {
  name = local.stack_name
  depends_on = [terraform_data.platforms]

  labels {
    label = "com.docker.stack.namespace"
    value = local.stack_name
  }

  labels {
    label = "com.docker.service"
    value = local.stack_name
  }

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      dynamic "platforms" {
        for_each = local.allowed_platforms

        content {
          os           = platforms.value.os
          architecture = platforms.value.architecture
        }
      }
    }

    networks_advanced {
      name    = docker_network.nginx_proxy_manager.id
      aliases = ["nginx-proxy-manager", "npm"]
    }

    container_spec {
      image = "jc21/nginx-proxy-manager:2.12.6@sha256:6ab097814f54b1362d5fd3c5884a01ddd5878aaae9992ffd218439180f0f92f3"
      env   = local.env

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_data.name
        target = "/data"
      }

      mounts {
        type   = "volume"
        source = docker_volume.nginx_proxy_manager_letsencrypt.name
        target = "/etc/letsencrypt"
      }

      healthcheck {
        test         = ["CMD", "/usr/bin/check-health"]
        interval     = "15s"
        timeout      = "5s"
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
      target_port    = local.published_ports.http
      published_port = local.published_ports.http
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.published_ports.https
      published_port = local.published_ports.https
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = local.published_ports.admin
      published_port = local.published_ports.admin
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }

  lifecycle {
    ignore_changes = [
      task_spec[0].placement[0].platforms,
    ]
    replace_triggered_by = [
      terraform_data.platforms,
    ]
  }
}
