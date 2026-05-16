resource "docker_network" "harbor" {
  name   = var.network_name
  driver = "overlay"
}

resource "docker_service" "log" {
  name = "harbor-log"

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["log"]
    }

    container_spec {
      image = var.images.log

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "DAC_OVERRIDE", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = local.log_root_path
        target = "/var/log/docker"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/log/logrotate.conf"
        target    = "/etc/logrotate.d/logrotate.conf"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/log/rsyslog_docker.conf"
        target    = "/etc/rsyslog.d/rsyslog_docker.conf"
        read_only = true
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
      target_port    = 10514
      published_port = var.log_syslog_published_port
      protocol       = "tcp"
      publish_mode   = "host"
    }
  }
}

resource "docker_service" "registry" {
  name = "registry"

  depends_on = [docker_service.log]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "registry" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["registry"]
    }

    container_spec {
      image = var.images.registry

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/registry"
        target = "/storage"
      }

      mounts {
        type   = "bind"
        source = "${local.config_root_path}/registry"
        target = "/etc/registry"
      }

      mounts {
        type      = "bind"
        source    = "${local.data_root_path}/secret/registry/root.crt"
        target    = "/etc/registry/root.crt"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}

resource "docker_service" "registryctl" {
  name = "registryctl"

  depends_on = [docker_service.log]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "registryctl" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["registryctl"]
    }

    container_spec {
      image = var.images.registryctl
      env   = local.effective_env.registryctl

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/registry"
        target = "/storage"
      }

      mounts {
        type   = "bind"
        source = "${local.config_root_path}/registry"
        target = "/etc/registry"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/registryctl/config.yml"
        target    = "/etc/registryctl/config.yml"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_env.registryctl) > 0
      error_message = "registryctl env is empty. Set env.registryctl or env_file_paths.registryctl."
    }
  }
}

resource "docker_service" "postgresql" {
  name = "postgresql"

  depends_on = [docker_service.log]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "postgresql" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["postgresql"]
    }

    container_spec {
      image = var.images.db
      env   = local.effective_env.db

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "DAC_OVERRIDE", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/database"
        target = "/var/lib/postgresql/data"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_env.db) > 0
      error_message = "db env is empty. Set env.db or env_file_paths.db."
    }
  }
}

resource "docker_service" "redis" {
  name = "redis"

  depends_on = [docker_service.log]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "redis" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["redis"]
    }

    container_spec {
      image = var.images.redis

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/redis"
        target = "/var/lib/redis"
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}

resource "docker_service" "core" {
  name = "core"

  depends_on = [
    docker_service.log,
    docker_service.registry,
    docker_service.redis,
    docker_service.postgresql,
  ]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "core" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["core"]
    }

    container_spec {
      image = var.images.core
      env   = local.effective_env.core

      cap_drop = ["ALL"]
      cap_add  = ["SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/ca_download"
        target = "/etc/core/ca"
      }

      mounts {
        type   = "bind"
        source = local.data_root_path
        target = "/data"
      }

      mounts {
        type   = "bind"
        source = "${local.config_root_path}/core/certificates"
        target = "/etc/core/certificates"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/core/app.conf"
        target    = "/etc/core/app.conf"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.data_root_path}/secret/core/private_key.pem"
        target    = "/etc/core/private_key.pem"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.data_root_path}/secret/keys/secretkey"
        target    = "/etc/core/key"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_env.core) > 0
      error_message = "core env is empty. Set env.core or env_file_paths.core."
    }
  }
}

resource "docker_service" "portal" {
  name = "portal"

  depends_on = [docker_service.log]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "portal" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["portal"]
    }

    container_spec {
      image = var.images.portal

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID", "NET_BIND_SERVICE"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/portal/nginx.conf"
        target    = "/etc/nginx/nginx.conf"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }
}

resource "docker_service" "jobservice" {
  name = "jobservice"

  depends_on = [docker_service.core]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "jobservice" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["jobservice"]
    }

    container_spec {
      image = var.images.jobservice
      env   = local.effective_env.jobservice

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/job_logs"
        target = "/var/log/jobs"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/jobservice/config.yml"
        target    = "/etc/jobservice/config.yml"
        read_only = true
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_env.jobservice) > 0
      error_message = "jobservice env is empty. Set env.jobservice or env_file_paths.jobservice."
    }
  }
}

resource "docker_service" "proxy" {
  name = "proxy"

  depends_on = [
    docker_service.registry,
    docker_service.core,
    docker_service.portal,
    docker_service.log,
  ]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "proxy" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["proxy", "nginx"]
    }

    container_spec {
      image = var.images.proxy

      cap_drop = ["ALL"]
      cap_add  = ["CHOWN", "SETGID", "SETUID", "NET_BIND_SERVICE"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.config_root_path}/nginx"
        target = "/etc/nginx"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
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
      target_port    = 8080
      published_port = var.proxy_published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}

resource "docker_service" "trivy_adapter" {
  name = "trivy-adapter"

  depends_on = [
    docker_service.log,
    docker_service.redis,
  ]

  task_spec {
    placement {
      constraints = [var.node_constraint]

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    log_driver {
      name    = "syslog"
      options = merge(local.syslog_driver_defaults, { tag = "trivy-adapter" })
    }

    networks_advanced {
      name    = docker_network.harbor.id
      aliases = ["trivy-adapter"]
    }

    container_spec {
      image = var.images.trivy_adapter
      env   = local.effective_env.trivy

      cap_drop = ["ALL"]

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/trivy-adapter/trivy"
        target = "/home/scanner/.cache/trivy"
      }

      mounts {
        type   = "bind"
        source = "${local.data_root_path}/trivy-adapter/reports"
        target = "/home/scanner/.cache/reports"
      }

      mounts {
        type      = "bind"
        source    = "${local.config_root_path}/shared/trust-certificates"
        target    = "/harbor_cust_cert"
        read_only = true
      }
    }
  }

  mode {
    replicated {
      replicas = 1
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.effective_env.trivy) > 0
      error_message = "trivy env is empty. Set env.trivy or env_file_paths.trivy."
    }
  }
}
