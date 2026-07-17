# locals.tf
# Single source of truth for Grafana config (datasources + dashboards) values (resources read local.* only).

locals {
  provider_config = var.provider_config
  datasources     = var.datasources

  node_exporter_file_path = "${path.module}/dashboards/node-exporter.json"
  node_exporter_file_hash = filemd5(local.node_exporter_file_path)
  node_exporter_content   = file(local.node_exporter_file_path)

  cadvisor_file_path = "${path.module}/dashboards/cadvisor.json"
  cadvisor_file_hash = filemd5(local.cadvisor_file_path)
  cadvisor_content   = file(local.cadvisor_file_path)

  truenas_file_path = "${path.module}/dashboards/truenas.json"
  truenas_file_hash = filemd5(local.truenas_file_path)
  truenas_content   = file(local.truenas_file_path)

  velero_overview_file_path = "${path.module}/dashboards/velero-overview.json"
  velero_overview_file_hash = filemd5(local.velero_overview_file_path)
  velero_overview_content   = file(local.velero_overview_file_path)

  qbittorrent_overview_file_path = "${path.module}/dashboards/qbittorrent-overview.json"
  qbittorrent_overview_file_hash = filemd5(local.qbittorrent_overview_file_path)
  qbittorrent_overview_content   = file(local.qbittorrent_overview_file_path)

  proxmox_file_path = "${path.module}/dashboards/proxmox.json"
  proxmox_file_hash = filemd5(local.proxmox_file_path)
  proxmox_content   = file(local.proxmox_file_path)
}
