resource "terraform_data" "node_exporter_overview_file_hash" {
  triggers_replace = local.node_exporter_overview_file_hash
}

resource "terraform_data" "node_exporter_cpu_load_file_hash" {
  triggers_replace = local.node_exporter_cpu_load_file_hash
}

resource "terraform_data" "node_exporter_memory_file_hash" {
  triggers_replace = local.node_exporter_memory_file_hash
}

resource "terraform_data" "node_exporter_storage_file_hash" {
  triggers_replace = local.node_exporter_storage_file_hash
}

resource "terraform_data" "node_exporter_network_file_hash" {
  triggers_replace = local.node_exporter_network_file_hash
}

resource "terraform_data" "node_exporter_processes_file_hash" {
  triggers_replace = local.node_exporter_processes_file_hash
}

resource "terraform_data" "node_exporter_hardware_file_hash" {
  triggers_replace = local.node_exporter_hardware_file_hash
}

resource "terraform_data" "truenas_overview_file_hash" {
  triggers_replace = local.truenas_overview_file_hash
}

resource "terraform_data" "truenas_cpu_thermals_file_hash" {
  triggers_replace = local.truenas_cpu_thermals_file_hash
}

resource "terraform_data" "truenas_disk_throughput_file_hash" {
  triggers_replace = local.truenas_disk_throughput_file_hash
}

resource "terraform_data" "truenas_disk_latency_file_hash" {
  triggers_replace = local.truenas_disk_latency_file_hash
}

resource "terraform_data" "truenas_disk_sla_file_hash" {
  triggers_replace = local.truenas_disk_sla_file_hash
}

resource "terraform_data" "truenas_disk_extended_file_hash" {
  triggers_replace = local.truenas_disk_extended_file_hash
}

resource "terraform_data" "truenas_smart_zfs_file_hash" {
  triggers_replace = local.truenas_smart_zfs_file_hash
}

resource "terraform_data" "truenas_services_network_file_hash" {
  triggers_replace = local.truenas_services_network_file_hash
}

resource "terraform_data" "truenas_k3s_diagnostics_file_hash" {
  triggers_replace = local.truenas_k3s_diagnostics_file_hash
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

resource "terraform_data" "loki_swarm_logs_overview_file_hash" {
  triggers_replace = local.loki_swarm_logs_overview_file_hash
}

resource "grafana_data_source" "prometheus" {
  name              = "Prometheus"
  uid               = "prometheus"
  type              = "prometheus"
  url               = "http://192.168.1.120:9090"
  is_default        = true
  json_data_encoded = jsonencode({ httpMethod = "POST" })
}

resource "grafana_data_source" "graphite" {
  name              = "Graphite"
  uid               = "graphite"
  type              = "graphite"
  url               = "http://192.168.1.120:8081"
  is_default        = false
  json_data_encoded = jsonencode({ httpMethod = "POST" })
}

resource "grafana_data_source" "loki" {
  name              = "Loki"
  uid               = "loki"
  type              = "loki"
  url               = "http://192.168.1.120:3100"
  is_default        = false
  json_data_encoded = jsonencode({ maxLines = 2000 })
}

resource "grafana_folder" "node_exporter" {
  title = "Node Exporter"
  uid   = "node-exporter-folder"
}

resource "grafana_folder" "truenas" {
  title = "TrueNAS"
  uid   = "truenas-folder"
}

resource "grafana_folder" "docker" {
  title = "Docker"
  uid   = "docker-folder"
}

resource "grafana_folder" "proxmox" {
  title = "Proxmox"
  uid   = "proxmox-folder"
}

resource "grafana_folder" "logs" {
  title = "Logs"
  uid   = "logs-folder"
}

resource "grafana_dashboard" "node_exporter_overview" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_overview_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_cpu_load" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_cpu_load_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_cpu_load_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_memory" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_memory_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_memory_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_storage" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_storage_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_storage_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_network" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_network_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_network_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_processes" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_processes_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_processes_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter_hardware" {
  folder      = grafana_folder.node_exporter.id
  overwrite   = true
  config_json = local.node_exporter_hardware_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_hardware_file_hash]
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

resource "grafana_dashboard" "truenas_overview" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_overview_file_hash]
  }
}

resource "grafana_dashboard" "truenas_cpu_thermals" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_cpu_thermals_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_cpu_thermals_file_hash]
  }
}

resource "grafana_dashboard" "truenas_disk_throughput" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_disk_throughput_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_disk_throughput_file_hash]
  }
}

resource "grafana_dashboard" "truenas_disk_latency" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_disk_latency_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_disk_latency_file_hash]
  }
}

resource "grafana_dashboard" "truenas_disk_sla" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_disk_sla_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_disk_sla_file_hash]
  }
}

resource "grafana_dashboard" "truenas_disk_extended" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_disk_extended_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_disk_extended_file_hash]
  }
}

resource "grafana_dashboard" "truenas_smart_zfs" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_smart_zfs_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_smart_zfs_file_hash]
  }
}

resource "grafana_dashboard" "truenas_services_network" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_services_network_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_services_network_file_hash]
  }
}

resource "grafana_dashboard" "truenas_k3s_diagnostics" {
  folder      = grafana_folder.truenas.id
  overwrite   = true
  config_json = local.truenas_k3s_diagnostics_content

  lifecycle {
    replace_triggered_by = [terraform_data.truenas_k3s_diagnostics_file_hash]
  }
}

resource "grafana_dashboard" "loki_swarm_logs_overview" {
  folder      = grafana_folder.logs.id
  overwrite   = true
  config_json = local.loki_swarm_logs_overview_content

  lifecycle {
    replace_triggered_by = [terraform_data.loki_swarm_logs_overview_file_hash]
  }
}
