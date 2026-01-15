locals {
  casc_config_yaml = yamlencode(var.casc_config)
  casc_config_sha  = sha256(local.casc_config_yaml)
  casc_config      = var.casc_config
  eapp_nfs_options = "addr=192.168.1.100,nfsvers=4.1,proto=tcp,rsize=1048576,wsize=1048576,hard,noatime,actimeo=1"
  default_mounts = [
    {
      name   = "jenkins-eapp-tfvars"
      target = "/home/jenkins/.tfvars"
      driver = "local"
      driver_opts = {
        type   = "nfs"
        o      = local.eapp_nfs_options
        device = ":/mnt/eapp/home/.tfvars"
      }
      no_copy = true
    },
    {
      name   = "jenkins-eapp-kube"
      target = "/home/jenkins/.kube"
      driver = "local"
      driver_opts = {
        type   = "nfs"
        o      = local.eapp_nfs_options
        device = ":/mnt/eapp/home/.kube"
      }
      no_copy = true
    },
    {
      name   = "jenkins-eapp-jenkins"
      target = "/home/jenkins/.jenkins"
      driver = "local"
      driver_opts = {
        type   = "nfs"
        o      = local.eapp_nfs_options
        device = ":/mnt/eapp/home/.jenkins"
      }
      no_copy = true
    }
  ]
  effective_mounts = concat(local.default_mounts, var.mounts)
  mounts = [
    for mount in local.effective_mounts : merge(mount, {
      name = format(
        "%s-%s",
        startswith(mount.name, "jenkins-") ? replace(mount.name, "jenkins-", "jenkins-controller-") : format("%s-controller", mount.name),
        substr(sha256(jsonencode({
          driver      = mount.driver
          driver_opts = mount.driver_opts
          target      = mount.target
          no_copy     = mount.no_copy
        })), 0, 8)
      )
    })
  ]
  healthcheck_endpoint = format("%s/whoAmI/api/json?tree=authenticated", var.provider_config.jenkins.server_url)
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
}

resource "docker_volume" "controller" {
  name = format("jenkins-controller-%s", substr(local.casc_config_sha, 0, 8))
}

resource "docker_volume" "controller_nfs" {
  for_each = { for mount in local.mounts : mount.name => mount }

  name        = each.value.name
  driver      = lookup(each.value, "driver", "local")
  driver_opts = lookup(each.value, "driver_opts", {})
}

resource "docker_config" "casc_config" {
  name = format("jenkins-%s.yaml", substr(local.casc_config_sha, 0, 12))
  data = base64encode(local.casc_config_yaml)

  lifecycle {
    create_before_destroy = true
  }
}

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_service" "controller" {
  name = "jenkins-controller"
  depends_on = [
    docker_config.casc_config,
    docker_volume.controller,
    docker_volume.controller_nfs,
    terraform_data.platforms,
  ]

  update_config {
    order = "stop-first"
  }

  task_spec {
    container_spec {
      image = "ghcr.io/nodadyoushutup/jenkins-controller:0.0.14@sha256:06eb6bd3aa3456696739ddbea1a3f10d5a285dfd32b83fdd452ba8508b611778"

      env = var.env

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/home/jenkins"
        source = docker_volume.controller.name
        type   = "volume"
      }

      mounts {
        target = "/dev/kvm"
        source = "/dev/kvm"
        type   = "bind"
      }
      mounts {
        target    = "/home/jenkins/.ssh"
        source    = pathexpand("~/.ssh")
        type      = "bind"
        read_only = true
      }
      mounts {
        target    = "/etc/ssh/ssh_known_hosts"
        source    = "/etc/ssh/ssh_known_hosts"
        type      = "bind"
        read_only = true
      }
      # Bind the same Jenkins data volume at /var/jenkins_home so the upstream
      # VOLUME instruction does not create an anonymous volume.
      mounts {
        target = "/var/jenkins_home"
        source = docker_volume.controller.name
        type   = "volume"
      }

      dynamic "mounts" {
        for_each = { for mount in local.mounts : mount.name => mount }
        content {
          target = mounts.value.target
          source = docker_volume.controller_nfs[mounts.key].name
          type   = "volume"

          volume_options {
            driver_name    = mounts.value.driver
            driver_options = mounts.value.driver_opts
            no_copy        = mounts.value.no_copy
          }
        }
      }

      configs {
        config_id   = docker_config.casc_config.id
        config_name = docker_config.casc_config.name
        file_name   = "/home/jenkins/jenkins.yaml"
      }

      healthcheck {
        test         = ["CMD", "curl", "-fsS", "http://127.0.0.1:8080/whoAmI/api/json?tree=authenticated"]
        interval     = "10s"
        timeout      = "5s"
        retries      = 30
        start_period = "1m"
      }
    }

    placement {
      dynamic "platforms" {
        for_each = local.allowed_platforms

        content {
          os           = platforms.value.os
          architecture = platforms.value.architecture
        }
      }
      constraints = ["node.labels.role==swarm-cp-0"]
    }
  }

  endpoint_spec {
    ports {
      target_port    = 8080
      published_port = 8080
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 50000
      published_port = 50000
      publish_mode   = "ingress"
    }
  }

  lifecycle {
    ignore_changes = [
      task_spec[0].placement[0].platforms,
    ]
    replace_triggered_by = [
      docker_config.casc_config,
      terraform_data.platforms,
    ]
  }
}

module "healthcheck" {
  source = "../../healthcheck"

  endpoint = local.healthcheck_endpoint
  triggers = {
    casc_config_sha = local.casc_config_sha
    service_id      = docker_service.controller.id
  }

  depends_on = [docker_service.controller]
}
