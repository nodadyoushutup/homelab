locals {
  node_exporter_file_path = "${path.module}/dashboards/node-exporter.json"
  node_exporter_file_hash = filemd5(local.node_exporter_file_path)
  node_exporter_content   = file(local.node_exporter_file_path)

  truenas_file_path = "${path.module}/dashboards/truenas.json"
  truenas_file_hash = filemd5(local.truenas_file_path)
  truenas_content   = file(local.truenas_file_path)

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

  velero_overview_file_path = "${path.module}/dashboards/velero-overview.json"
  velero_overview_file_hash = filemd5(local.velero_overview_file_path)
  velero_overview_content   = file(local.velero_overview_file_path)

  qbittorrent_overview_file_path = "${path.module}/dashboards/qbittorrent-overview.json"
  qbittorrent_overview_file_hash = filemd5(local.qbittorrent_overview_file_path)
  qbittorrent_overview_content   = file(local.qbittorrent_overview_file_path)
}
