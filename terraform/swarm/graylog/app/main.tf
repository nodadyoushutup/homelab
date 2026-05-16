data "docker_network" "graylog_database" {
  name = "graylog-database"
}

resource "docker_network" "graylog_app" {
  name   = "graylog-app"
  driver = "overlay"
}

resource "docker_volume" "graylog_datanode" {
  name = "graylog-datanode-data"
}

resource "docker_volume" "graylog_server" {
  name = "graylog-server-data"
}

resource "docker_service" "graylog_datanode" {
  name = "graylog-datanode"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.graylog_app.id
      aliases = ["datanode"]
    }

    networks_advanced {
      name    = data.docker_network.graylog_database.id
      aliases = []
    }

    container_spec {
      hostname = "datanode"
      image    = "graylog/graylog-datanode:7.1.1@sha256:cd5f5ec598c9f4ac5f8c856b90dda925998f0568d04b40ee928819aee747762d"

      env = {
        GRAYLOG_DATANODE_NODE_ID_FILE     = "/var/lib/graylog-datanode/node-id"
        GRAYLOG_DATANODE_PASSWORD_SECRET   = local.graylog_password_secret
        GRAYLOG_DATANODE_MONGODB_URI       = local.graylog_mongodb_uri
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/var/lib/graylog-datanode"
        source = docker_volume.graylog_datanode.name
        type   = "volume"
      }

      ulimits {
        name = "memlock"
        soft = -1
        hard = -1
      }

      ulimits {
        name = "nofile"
        soft = 65536
        hard = 65536
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }
}

resource "docker_service" "graylog" {
  name = "graylog"

  task_spec {
    placement {
      constraints = ["node.labels.role==swarm-cp-0"]

      platforms {
        os           = "linux"
        architecture = "aarch64"
      }
    }

    networks_advanced {
      name    = docker_network.graylog_app.id
      aliases = ["graylog"]
    }

    networks_advanced {
      name    = data.docker_network.graylog_database.id
      aliases = []
    }

    container_spec {
      hostname = "server"
      image    = "graylog/graylog:7.1.1@sha256:e5cdb5cda5adadc56c28ce0e34ede9875b911387a7dc87dcce7ee3282fba1ce3"

      command = ["/usr/bin/tini", "--", "/docker-entrypoint.sh"]

      env = {
        GRAYLOG_NODE_ID_FILE         = "/usr/share/graylog/data/data/node-id"
        GRAYLOG_PASSWORD_SECRET      = local.graylog_password_secret
        GRAYLOG_ROOT_PASSWORD_SHA2   = local.graylog_root_password
        GRAYLOG_HTTP_BIND_ADDRESS    = local.graylog_http_bind
        GRAYLOG_HTTP_EXTERNAL_URI    = local.graylog_http_external
        GRAYLOG_MONGODB_URI          = local.graylog_mongodb_uri
      }

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        target = "/usr/share/graylog/data"
        source = docker_volume.graylog_server.name
        type   = "volume"
      }

      healthcheck {
        test         = ["CMD-SHELL", "wget -q -O- http://127.0.0.1:9000/api/system/lbstatus | grep -q ALIVE || wget -q -O- http://127.0.0.1:9000/api | grep -q graylog"]
        interval     = "20s"
        timeout      = "10s"
        retries      = 15
        start_period = "120s"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = 9000
      published_port = var.published_port_ui
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 5140
      published_port = var.published_port_syslog_tcp
      protocol       = "tcp"
      publish_mode   = "ingress"
    }

    ports {
      target_port    = 12201
      published_port = var.published_port_gelf_tcp
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
