locals {
  service_name       = "webserver-image"
  network_name       = "webserver-image"
  data_volume_name   = "webserver-image-data"
  internal_port      = 8080
  published_port     = 18088
  data_mount_target  = "/srv/webserver-image/data"
  nginx_config       = templatefile("${path.module}/nginx.conf.tftpl", { listen_port = local.internal_port, data_root = local.data_mount_target })
  nginx_config_hash  = substr(sha256(local.nginx_config), 0, 12)
  nginx_force_update = parseint(substr(local.nginx_config_hash, 0, 8), 16)
  image_reference    = "nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284"
}

resource "docker_network" "webserver_image" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "webserver_image_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_config" "webserver_image_nginx" {
  name = "webserver-image-nginx-${local.nginx_config_hash}.conf"
  data = base64encode(local.nginx_config)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "webserver_image" {
  name = local.service_name

  task_spec {
    force_update = local.nginx_force_update

    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.webserver_image.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image_reference

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        type   = "volume"
        source = docker_volume.webserver_image_data.name
        target = local.data_mount_target
      }

      configs {
        config_id   = docker_config.webserver_image_nginx.id
        config_name = docker_config.webserver_image_nginx.name
        file_name   = "/etc/nginx/nginx.conf"
      }

      healthcheck {
        test         = ["CMD-SHELL", "wget --spider --quiet http://127.0.0.1:8080/ || exit 1"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 5
        start_period = "20s"
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
