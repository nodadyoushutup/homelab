locals {
  eapp_nfs_options = "addr=192.168.1.100,nfsvers=4.1,proto=tcp,rsize=1048576,wsize=1048576,hard,noatime,actimeo=1"
  default_mounts = [
    {
      name   = "jenkins-eapp-code"
      target = "/home/jenkins/code"
      driver = "local"
      driver_opts = {
        type   = "nfs"
        o      = local.eapp_nfs_options
        device = ":/mnt/eapp/home/code"
      }
      no_copy = true
    },
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
        startswith(mount.name, "jenkins-") ? replace(mount.name, "jenkins-", format("jenkins-agent-%s-", var.name)) : format("%s-agent-%s", mount.name, var.name),
        substr(sha256(jsonencode({
          driver      = mount.driver
          driver_opts = mount.driver_opts
          target      = mount.target
          no_copy     = mount.no_copy
        })), 0, 8)
      )
    })
  ]
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

resource "docker_volume" "agent" {
  name = format(
    "jenkins-agent-%s-%s",
    var.name,
    substr(sha256(var.controller_service_id), 0, 8)
  )
}

resource "docker_volume" "agent_nfs" {
  for_each = { for mount in local.mounts : mount.name => mount }

  name        = each.value.name
  driver      = lookup(each.value, "driver", "local")
  driver_opts = lookup(each.value, "driver_opts", {})
}

resource "terraform_data" "controller_service" {
  input = var.controller_service_id
}

resource "terraform_data" "controller_image" {
  input = var.controller_image
}

resource "terraform_data" "platforms" {
  input = local.allowed_platforms
}

resource "docker_service" "agent" {
  name = "jenkins-agent-${var.name}"
  depends_on = [
    docker_volume.agent,
    docker_volume.agent_nfs,
    terraform_data.controller_service,
    terraform_data.platforms,
  ]

  task_spec {
    container_spec {
      image = "ghcr.io/nodadyoushutup/jenkins-agent:0.0.7@sha256:932b7568a2847b5a0545525e961b6073384ff76bcc3f40b08bd3c339c6ab9f69"

      env = merge(
        var.env,
        {
          JENKINS_URL        = try(var.provider_config.jenkins.server_url, "")
          JENKINS_AGENT_NAME = var.name
        }
      )

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target = "/home/jenkins"
        source = docker_volume.agent.name
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

      dynamic "mounts" {
        for_each = { for mount in local.mounts : mount.name => mount }
        content {
          target = mounts.value.target
          source = docker_volume.agent_nfs[mounts.key].name
          type   = "volume"

          volume_options {
            driver_name    = mounts.value.driver
            driver_options = mounts.value.driver_opts
            no_copy        = mounts.value.no_copy
          }
        }
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

  lifecycle {
    ignore_changes = [
      task_spec[0].placement[0].platforms,
    ]
    replace_triggered_by = [
      terraform_data.controller_service,
      terraform_data.controller_image,
      terraform_data.platforms,
    ]
  }
}
