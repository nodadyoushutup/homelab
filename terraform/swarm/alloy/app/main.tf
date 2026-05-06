locals {
  alloy_config_hash  = substr(filemd5(var.alloy_config_path), 0, 12)
  alloy_force_update = parseint(substr(local.alloy_config_hash, 0, 8), 16)
}

data "docker_network" "loki" {
  name = "loki"
}

resource "docker_volume" "alloy_data" {
  name = "alloy-data"
}

resource "docker_config" "alloy" {
  name = "alloy-config-${local.alloy_config_hash}"
  data = filebase64(var.alloy_config_path)

  lifecycle {
    create_before_destroy = true
  }
}

resource "docker_service" "alloy" {
  name = "alloy"

  task_spec {
    force_update = local.alloy_force_update

    placement {
      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name        = data.docker_network.loki.id
      aliases     = []
      driver_opts = []
    }

    container_spec {
      image = "grafana/alloy:latest@sha256:51aeb9d829239345070619dad3edd6873186f913c84f45b365b74574fcb38ec0"
      user  = "0:0"

      args = [
        "run",
        "--server.http.listen-addr=0.0.0.0:12345",
        "--storage.path=/var/lib/alloy",
        "/etc/alloy/config.alloy",
      ]

      dns_config {
        nameservers = [
          "192.168.1.1",
          "1.1.1.1",
          "8.8.8.8",
        ]
      }

      mounts {
        target    = "/var/run/docker.sock"
        source    = "/var/run/docker.sock"
        type      = "bind"
        read_only = true
      }

      mounts {
        target = "/var/lib/alloy"
        source = docker_volume.alloy_data.name
        type   = "volume"
      }

      configs {
        config_id   = docker_config.alloy.id
        config_name = docker_config.alloy.name
        file_name   = "/etc/alloy/config.alloy"
      }

      healthcheck {
        test = ["NONE"]
      }

    }
  }

  mode {
    global = true
  }

  update_config {
    order = "stop-first"
  }
}
