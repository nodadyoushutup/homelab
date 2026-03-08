locals {
  service_name      = "webserver-image"
  network_name      = "webserver-image"
  data_volume_name  = "webserver-image-data"
  internal_port     = 8080
  published_port    = 18088
  data_mount_target = "/srv/webserver-image/data"
  nginx_config      = templatefile("${path.module}/nginx.conf.tftpl", { listen_port = local.internal_port, data_root = local.data_mount_target })
  index_html        = file("${path.module}/index.html")
  app_js            = file("${path.module}/app.js")
  favicon_svg       = file("${path.module}/favicon.svg")
  nginx_config_hash = substr(sha256(local.nginx_config), 0, 12)
  index_html_hash   = substr(sha256(local.index_html), 0, 12)
  app_js_hash       = substr(sha256(local.app_js), 0, 12)
  favicon_svg_hash  = substr(sha256(local.favicon_svg), 0, 12)
  service_config_hash = substr(
    sha256(
      join(
        "\n",
        [
          local.nginx_config,
          local.index_html,
          local.app_js,
          local.favicon_svg,
        ],
      ),
    ),
    0,
    12,
  )
  nginx_force_update = parseint(substr(local.service_config_hash, 0, 8), 16)
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

resource "docker_config" "webserver_image_index_html" {
  name = "webserver-image-index-${local.index_html_hash}.html"
  data = base64encode(local.index_html)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_config" "webserver_image_app_js" {
  name = "webserver-image-app-${local.app_js_hash}.js"
  data = base64encode(local.app_js)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_config" "webserver_image_favicon_svg" {
  name = "webserver-image-favicon-${local.favicon_svg_hash}.svg"
  data = base64encode(local.favicon_svg)

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

      configs {
        config_id   = docker_config.webserver_image_index_html.id
        config_name = docker_config.webserver_image_index_html.name
        file_name   = "/usr/share/nginx/html/index.html"
      }

      configs {
        config_id   = docker_config.webserver_image_app_js.id
        config_name = docker_config.webserver_image_app_js.name
        file_name   = "/usr/share/nginx/html/app.js"
      }

      configs {
        config_id   = docker_config.webserver_image_favicon_svg.id
        config_name = docker_config.webserver_image_favicon_svg.name
        file_name   = "/usr/share/nginx/html/favicon.svg"
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
