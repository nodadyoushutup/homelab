locals {
  casc_yaml = yamlencode(var.casc_config)
  casc_hash = substr(sha256(local.casc_yaml), 0, 12)

  config_force_update = parseint(substr(local.casc_hash, 0, 8), 16)
  extra_mounts_by_name = {
    for mount in var.mounts : mount.name => mount
  }
}

resource "docker_network" "jenkins_controller" {
  name   = var.network_name
  driver = "overlay"
}

resource "docker_volume" "jenkins_controller_home" {
  name   = var.home_volume_name
  driver = "local"
}

resource "docker_volume" "extra_mounts" {
  for_each = local.extra_mounts_by_name

  name        = each.value.name
  driver      = each.value.driver
  driver_opts = each.value.driver_opts
}

resource "docker_config" "jenkins_casc" {
  name = "jenkins-controller-casc-${local.casc_hash}.yaml"
  data = base64encode(local.casc_yaml)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "jenkins_controller" {
  name = var.service_name

  dynamic "auth" {
    for_each = try(var.provider_config.registry_auth, null) == null ? [] : [var.provider_config.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    force_update = local.config_force_update

    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.jenkins_controller.id
      aliases = [var.service_dns_alias]
    }

    container_spec {
      image = var.controller_image
      env   = var.env

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "volume"
        source = docker_volume.jenkins_controller_home.name
        target = var.home_mount_target
      }

      dynamic "mounts" {
        for_each = local.extra_mounts_by_name

        content {
          type   = "volume"
          source = docker_volume.extra_mounts[mounts.key].name
          target = mounts.value.target

          dynamic "volume_options" {
            for_each = mounts.value.no_copy ? [1] : []

            content {
              no_copy = true
            }
          }
        }
      }

      configs {
        config_id   = docker_config.jenkins_casc.id
        config_name = docker_config.jenkins_casc.name
        file_name   = format("%s/jenkins.yaml", var.home_mount_target)
      }

      healthcheck {
        test         = ["CMD-SHELL", "curl --silent --show-error --fail http://127.0.0.1:8080/login > /dev/null || exit 1"]
        interval     = "30s"
        timeout      = "5s"
        retries      = 6
        start_period = "60s"
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
      replicas = var.controller_replicas
    }
  }

  endpoint_spec {
    ports {
      target_port    = var.controller_target_port
      published_port = var.controller_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = var.agent_target_port
      published_port = var.agent_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
