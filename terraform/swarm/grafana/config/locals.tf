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

  proxmox_qemu_overview_file_path = "${path.module}/dashboards/proxmox-qemu-overview.json"
  proxmox_qemu_overview_file_hash = filemd5(local.proxmox_qemu_overview_file_path)
  proxmox_qemu_overview_content   = file(local.proxmox_qemu_overview_file_path)

  proxmox_storage_overview_file_path = "${path.module}/dashboards/proxmox-storage-overview.json"
  proxmox_storage_overview_file_hash = filemd5(local.proxmox_storage_overview_file_path)
  proxmox_storage_overview_content   = file(local.proxmox_storage_overview_file_path)

  loki_swarm_logs_overview_file_path = "${path.module}/dashboards/loki-swarm-logs-overview.json"
  loki_swarm_logs_overview_file_hash = filemd5(local.loki_swarm_logs_overview_file_path)
  loki_swarm_logs_overview_content   = file(local.loki_swarm_logs_overview_file_path)
}
