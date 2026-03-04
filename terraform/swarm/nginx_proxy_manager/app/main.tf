locals {
  stack_name      = "nginx-proxy-manager"
  image_reference = "jc21/nginx-proxy-manager:2.12.6@sha256:6ab097814f54b1362d5fd3c5884a01ddd5878aaae9992ffd218439180f0f92f3"
}

resource "docker_network" "nginx_proxy_manager" {
  name   = "nginx-proxy-manager"
  driver = "overlay"
}

resource "docker_volume" "nginx_proxy_manager_data" {
  name   = "nginx-proxy-manager-data"
  driver = "local"
}

resource "docker_volume" "nginx_proxy_manager_letsencrypt" {
  name   = "nginx-proxy-manager-letsencrypt"
  driver = "local"
}

resource "docker_service" "nginx_proxy_manager" {
  name = "nginx-proxy-manager"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.nginx_proxy_manager.id
      aliases = ["nginx-proxy-manager"]
    }

    container_spec {
      image = local.image_reference
      env = {
        INITIAL_ADMIN_EMAIL    = var.env.INITIAL_ADMIN_EMAIL
        INITIAL_ADMIN_PASSWORD = var.env.INITIAL_ADMIN_PASSWORD
      }

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

  endpoint_spec {
    ports {
      target_port    = 80
      published_port = 80
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 443
      published_port = 443
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 81
      published_port = 81
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
