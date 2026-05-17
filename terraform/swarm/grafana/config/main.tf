resource "terraform_data" "node_exporter_file_hash" {
  triggers_replace = local.node_exporter_file_hash
}

resource "terraform_data" "truenas_file_hash" {
  triggers_replace = local.truenas_file_hash
}

resource "terraform_data" "telegraf_docker_overview_file_hash" {
  triggers_replace = local.telegraf_docker_overview_file_hash
}

resource "terraform_data" "telegraf_docker_cpu_file_hash" {
  triggers_replace = local.telegraf_docker_cpu_file_hash
}

resource "terraform_data" "telegraf_docker_memory_file_hash" {
  triggers_replace = local.telegraf_docker_memory_file_hash
}

resource "terraform_data" "telegraf_docker_network_file_hash" {
  triggers_replace = local.telegraf_docker_network_file_hash
}

resource "terraform_data" "telegraf_docker_storage_file_hash" {
  triggers_replace = local.telegraf_docker_storage_file_hash
}

resource "terraform_data" "telegraf_docker_processes_file_hash" {
  triggers_replace = local.telegraf_docker_processes_file_hash
}

resource "terraform_data" "proxmox_qemu_overview_file_hash" {
  triggers_replace = local.proxmox_qemu_overview_file_hash
}

resource "terraform_data" "proxmox_storage_overview_file_hash" {
  triggers_replace = local.proxmox_storage_overview_file_hash
}

resource "terraform_data" "velero_overview_file_hash" {
  triggers_replace = local.velero_overview_file_hash
}

resource "terraform_data" "qbittorrent_overview_file_hash" {
  triggers_replace = local.qbittorrent_overview_file_hash
}

resource "grafana_data_source" "prometheus" {
  name              = "Prometheus"
  uid               = "prometheus"
  type              = "prometheus"
  url               = "http://192.168.1.121:8428"
  is_default        = true
  json_data_encoded = jsonencode({ httpMethod = "POST" })
}

resource "grafana_data_source" "graphite" {
  name              = "Graphite"
  uid               = "graphite"
  type              = "graphite"
  url               = "http://192.168.1.28:8081"
  is_default        = false
  json_data_encoded = jsonencode({ httpMethod = "POST" })
}

resource "grafana_folder" "docker" {
  title = "Docker"
  uid   = "docker-folder"
}

resource "grafana_folder" "proxmox" {
  title = "Proxmox"
  uid   = "proxmox-folder"
}

resource "grafana_dashboard" "node_exporter" {
  overwrite   = true
  config_json = local.node_exporter_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_overview" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_overview_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_cpu" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_cpu_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_cpu_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_memory" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_memory_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_memory_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_network" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_network_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_network_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_storage" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_storage_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_storage_file_hash]
  }
}

resource "grafana_dashboard" "telegraf_docker_processes" {
  folder      = grafana_folder.docker.id
  overwrite   = true
  config_json = local.telegraf_docker_processes_content

  lifecycle {
    replace_triggered_by = [terraform_data.telegraf_docker_processes_file_hash]
  }
}

resource "grafana_dashboard" "proxmox_qemu_overview" {
  folder      = grafana_folder.proxmox.id
  overwrite   = true
  config_json = local.proxmox_qemu_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.proxmox_qemu_overview_file_hash]
  }
}

resource "grafana_dashboard" "proxmox_storage_overview" {
  folder      = grafana_folder.proxmox.id
  overwrite   = true
  config_json = local.proxmox_storage_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.proxmox_storage_overview_file_hash]
  }
}

resource "grafana_dashboard" "truenas" {
  overwrite   = true
  config_json = local.truenas_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_file_hash]
  }
}

resource "grafana_dashboard" "velero_overview" {
  overwrite   = true
  config_json = local.velero_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.velero_overview_file_hash]
  }
}

resource "grafana_dashboard" "qbittorrent_overview" {
  overwrite   = true
  config_json = local.qbittorrent_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.qbittorrent_overview_file_hash]
  }
}
