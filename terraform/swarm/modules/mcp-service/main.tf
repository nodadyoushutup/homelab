terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.6.2"
    }
  }
}

locals {
  network_name = coalesce(var.network_name, var.service_name)
}

resource "docker_network" "this" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_service" "this" {
  name = var.service_name

  dynamic "auth" {
    for_each = var.registry_auth == null ? [] : [var.registry_auth]

    content {
      server_address = try(auth.value.address, var.registry_address)
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.this.id
      aliases = [var.service_name]
    }

    container_spec {
      image    = var.image_reference
      command  = var.command
      args     = var.args
      env      = var.env
      user     = var.user
      cap_drop = var.cap_drop

      dns_config {
        nameservers = var.dns_nameservers
      }

      dynamic "mounts" {
        for_each = var.mounts

        content {
          type      = mounts.value.type
          source    = mounts.value.source
          target    = mounts.value.target
          read_only = try(mounts.value.read_only, false)
        }
      }

      dynamic "healthcheck" {
        for_each = var.healthcheck == null ? [] : [var.healthcheck]

        content {
          test         = healthcheck.value.test
          interval     = try(healthcheck.value.interval, "15s")
          timeout      = try(healthcheck.value.timeout, "5s")
          retries      = try(healthcheck.value.retries, 10)
          start_period = try(healthcheck.value.start_period, "30s")
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
      target_port    = var.internal_port
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
