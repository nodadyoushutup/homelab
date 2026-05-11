moved {
  from = docker_network.webserver_image
  to   = docker_network.cloud_image_repository
}

moved {
  from = docker_volume.webserver_image_data
  to   = docker_volume.cloud_image_repository_data
}

moved {
  from = docker_config.webserver_image_index_html
  to   = docker_config.cloud_image_repository_index_html
}

moved {
  from = docker_config.webserver_image_app_js
  to   = docker_config.cloud_image_repository_app_js
}

moved {
  from = docker_config.webserver_image_favicon_svg
  to   = docker_config.cloud_image_repository_favicon_svg
}

moved {
  from = docker_config.webserver_image_server_py
  to   = docker_config.cloud_image_repository_server_py
}

moved {
  from = docker_service.webserver_image
  to   = docker_service.cloud_image_repository
}

locals {
  service_name      = "cloud-image-repository"
  network_name      = "cloud-image-repository"
  data_volume_name  = "webserver-image-data" # legacy Docker volume name retains existing qcow2 data
  internal_port     = 8080
  published_port    = 18088
  data_mount_target = "/srv/cloud-image-repository/data"
  ui_mount_target   = "/srv/cloud-image-repository/ui"
  index_html        = file("${path.module}/index.html")
  app_js            = file("${path.module}/app.js")
  favicon_svg       = file("${path.module}/favicon.svg")
  server_py         = file("${path.module}/server.py")
  index_html_hash   = substr(sha256(local.index_html), 0, 12)
  app_js_hash       = substr(sha256(local.app_js), 0, 12)
  favicon_svg_hash  = substr(sha256(local.favicon_svg), 0, 12)
  server_py_hash    = substr(sha256(local.server_py), 0, 12)
  service_config_hash = substr(
    sha256(
      join(
        "\n",
        [
          local.index_html,
          local.app_js,
          local.favicon_svg,
          local.server_py,
        ],
      ),
    ),
    0,
    12,
  )
  app_force_update = parseint(substr(local.service_config_hash, 0, 8), 16)
  image_reference  = "python:3.12.11-alpine3.22"
}

resource "docker_network" "cloud_image_repository" {
  name   = local.network_name
  driver = "overlay"
}

resource "docker_volume" "cloud_image_repository_data" {
  name   = local.data_volume_name
  driver = "local"
}

resource "docker_config" "cloud_image_repository_index_html" {
  name = "cloud-image-repository-index-${local.index_html_hash}.html"
  data = base64encode(local.index_html)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_config" "cloud_image_repository_app_js" {
  name = "cloud-image-repository-app-${local.app_js_hash}.js"
  data = base64encode(local.app_js)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_config" "cloud_image_repository_favicon_svg" {
  name = "cloud-image-repository-favicon-${local.favicon_svg_hash}.svg"
  data = base64encode(local.favicon_svg)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_config" "cloud_image_repository_server_py" {
  name = "cloud-image-repository-server-${local.server_py_hash}.py"
  data = base64encode(local.server_py)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "cloud_image_repository" {
  name = local.service_name

  task_spec {
    force_update = local.app_force_update

    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.cloud_image_repository.id
      aliases = [local.service_name]
    }

    container_spec {
      image = local.image_reference
      command = [
        "python3",
      ]
      args = [
        "/srv/cloud-image-repository/server.py",
      ]

      env = {
        CLOUD_IMAGE_REPOSITORY_DATA_ROOT = local.data_mount_target
        CLOUD_IMAGE_REPOSITORY_UI_ROOT   = local.ui_mount_target
        CLOUD_IMAGE_REPOSITORY_PORT      = tostring(local.internal_port)
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
        source = docker_volume.cloud_image_repository_data.name
        target = local.data_mount_target
      }

      configs {
        config_id   = docker_config.cloud_image_repository_server_py.id
        config_name = docker_config.cloud_image_repository_server_py.name
        file_name   = "/srv/cloud-image-repository/server.py"
      }

      configs {
        config_id   = docker_config.cloud_image_repository_index_html.id
        config_name = docker_config.cloud_image_repository_index_html.name
        file_name   = "/srv/cloud-image-repository/ui/index.html"
      }

      configs {
        config_id   = docker_config.cloud_image_repository_app_js.id
        config_name = docker_config.cloud_image_repository_app_js.name
        file_name   = "/srv/cloud-image-repository/ui/app.js"
      }

      configs {
        config_id   = docker_config.cloud_image_repository_favicon_svg.id
        config_name = docker_config.cloud_image_repository_favicon_svg.name
        file_name   = "/srv/cloud-image-repository/ui/favicon.svg"
      }

      healthcheck {
        test         = ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/', timeout=5).read(1)"]
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
