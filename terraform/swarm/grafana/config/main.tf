locals {
  node_exporter_overview_file_path = "${path.module}/dashboards/node-exporter-overview.json"
  node_exporter_overview_file_hash = filemd5(local.node_exporter_overview_file_path)
  node_exporter_overview_content   = file(local.node_exporter_overview_file_path)

  node_exporter_cpu_load_file_path = "${path.module}/dashboards/node-exporter-cpu-load.json"
  node_exporter_cpu_load_file_hash = filemd5(local.node_exporter_cpu_load_file_path)
  node_exporter_cpu_load_content   = file(local.node_exporter_cpu_load_file_path)

  node_exporter_memory_file_path = "${path.module}/dashboards/node-exporter-memory.json"
  node_exporter_memory_file_hash = filemd5(local.node_exporter_memory_file_path)
  node_exporter_memory_content   = file(local.node_exporter_memory_file_path)

  node_exporter_storage_file_path = "${path.module}/dashboards/node-exporter-storage.json"
  node_exporter_storage_file_hash = filemd5(local.node_exporter_storage_file_path)
  node_exporter_storage_content   = file(local.node_exporter_storage_file_path)

  node_exporter_network_file_path = "${path.module}/dashboards/node-exporter-network.json"
  node_exporter_network_file_hash = filemd5(local.node_exporter_network_file_path)
  node_exporter_network_content   = file(local.node_exporter_network_file_path)

  node_exporter_processes_file_path = "${path.module}/dashboards/node-exporter-processes.json"
  node_exporter_processes_file_hash = filemd5(local.node_exporter_processes_file_path)
  node_exporter_processes_content   = file(local.node_exporter_processes_file_path)

  node_exporter_hardware_file_path = "${path.module}/dashboards/node-exporter-hardware.json"
  node_exporter_hardware_file_hash = filemd5(local.node_exporter_hardware_file_path)
  node_exporter_hardware_content   = file(local.node_exporter_hardware_file_path)

  truenas_overview_file_path = "${path.module}/dashboards/truenas-overview.json"
  truenas_overview_file_hash = filemd5(local.truenas_overview_file_path)
  truenas_overview_content   = file(local.truenas_overview_file_path)

  truenas_cpu_thermals_file_path = "${path.module}/dashboards/truenas-cpu-thermals.json"
  truenas_cpu_thermals_file_hash = filemd5(local.truenas_cpu_thermals_file_path)
  truenas_cpu_thermals_content   = file(local.truenas_cpu_thermals_file_path)

  truenas_disk_throughput_file_path = "${path.module}/dashboards/truenas-disk-throughput.json"
  truenas_disk_throughput_file_hash = filemd5(local.truenas_disk_throughput_file_path)
  truenas_disk_throughput_content   = file(local.truenas_disk_throughput_file_path)

  truenas_disk_latency_file_path = "${path.module}/dashboards/truenas-disk-latency.json"
  truenas_disk_latency_file_hash = filemd5(local.truenas_disk_latency_file_path)
  truenas_disk_latency_content   = file(local.truenas_disk_latency_file_path)

  truenas_disk_sla_file_path = "${path.module}/dashboards/truenas-disk-sla.json"
  truenas_disk_sla_file_hash = filemd5(local.truenas_disk_sla_file_path)
  truenas_disk_sla_content   = file(local.truenas_disk_sla_file_path)

  truenas_disk_extended_file_path = "${path.module}/dashboards/truenas-disk-extended.json"
  truenas_disk_extended_file_hash = filemd5(local.truenas_disk_extended_file_path)
  truenas_disk_extended_content   = file(local.truenas_disk_extended_file_path)

  truenas_smart_zfs_file_path = "${path.module}/dashboards/truenas-smart-zfs.json"
  truenas_smart_zfs_file_hash = filemd5(local.truenas_smart_zfs_file_path)
  truenas_smart_zfs_content   = file(local.truenas_smart_zfs_file_path)

  truenas_services_network_file_path = "${path.module}/dashboards/truenas-services-network.json"
  truenas_services_network_file_hash = filemd5(local.truenas_services_network_file_path)
  truenas_services_network_content   = file(local.truenas_services_network_file_path)

  truenas_k3s_diagnostics_file_path = "${path.module}/dashboards/truenas-k3s-diagnostics.json"
  truenas_k3s_diagnostics_file_hash = filemd5(local.truenas_k3s_diagnostics_file_path)
  truenas_k3s_diagnostics_content   = file(local.truenas_k3s_diagnostics_file_path)

  telegraf_docker_overview_file_path = "${path.module}/dashboards/telegraf-docker-metrics-overview.json"
  telegraf_docker_overview_file_hash = filemd5(local.telegraf_docker_overview_file_path)
  telegraf_docker_overview_content   = file(local.telegraf_docker_overview_file_path)

  telegraf_docker_cpu_file_path = "${path.module}/dashboards/telegraf-docker-metrics-cpu.json"
  telegraf_docker_cpu_file_hash = filemd5(local.telegraf_docker_cpu_file_path)
  telegraf_docker_cpu_content   = file(local.telegraf_docker_cpu_file_path)

  telegraf_docker_memory_file_path = "${path.module}/dashboards/telegraf-docker-metrics-memory.json"
  telegraf_docker_memory_file_hash = filemd5(local.telegraf_docker_memory_file_path)
  telegraf_docker_memory_content   = file(local.telegraf_docker_memory_file_path)

  telegraf_docker_network_file_path = "${path.module}/dashboards/telegraf-docker-metrics-network.json"
  telegraf_docker_network_file_hash = filemd5(local.telegraf_docker_network_file_path)
  telegraf_docker_network_content   = file(local.telegraf_docker_network_file_path)

  telegraf_docker_storage_file_path = "${path.module}/dashboards/telegraf-docker-metrics-storage.json"
  telegraf_docker_storage_file_hash = filemd5(local.telegraf_docker_storage_file_path)
  telegraf_docker_storage_content   = file(local.telegraf_docker_storage_file_path)

  telegraf_docker_processes_file_path = "${path.module}/dashboards/telegraf-docker-metrics-processes.json"
  telegraf_docker_processes_file_hash = filemd5(local.telegraf_docker_processes_file_path)
  telegraf_docker_processes_content   = file(local.telegraf_docker_processes_file_path)
}

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

resource "grafana_data_source" "prometheus" {
  name              = "Prometheus"
  uid               = "prometheus"
  type              = "prometheus"
  url               = "http://192.168.1.26:9090"
  is_default        = true
  json_data_encoded = jsonencode({ httpMethod = "POST" })
}

resource "grafana_data_source" "graphite" {
  name              = "Graphite"
  uid               = "graphite"
  type              = "graphite"
  url               = "http://192.168.1.26:8081"
  is_default        = false
  json_data_encoded = jsonencode({ httpMethod = "POST" })
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
