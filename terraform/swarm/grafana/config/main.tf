resource "terraform_data" "node_exporter_file_hash" {
  triggers_replace = local.node_exporter_file_hash
}

resource "terraform_data" "docker_file_hash" {
  triggers_replace = local.docker_file_hash
}

resource "terraform_data" "truenas_file_hash" {
  triggers_replace = local.truenas_file_hash
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

resource "terraform_data" "proxmox_file_hash" {
  triggers_replace = local.proxmox_file_hash
}

resource "grafana_data_source" "this" {
  for_each = { for ds in var.datasources : ds.uid => ds }

  name              = each.value.name
  uid               = each.value.uid
  type              = each.value.type
  url               = each.value.url
  is_default        = each.value.is_default
  json_data_encoded = each.value.json_data != null ? jsonencode(each.value.json_data) : null
}

resource "grafana_folder" "proxmox" {
  title = "Proxmox"
  uid   = "proxmox-folder"
}

resource "grafana_dashboard" "docker" {
  overwrite   = true
  config_json = local.docker_content

  lifecycle {
    replace_triggered_by = [terraform_data.docker_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter" {
  overwrite   = true
  config_json = local.node_exporter_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_file_hash]
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

resource "grafana_dashboard" "proxmox" {
  overwrite   = true
  config_json = local.proxmox_content

  lifecycle {
    replace_triggered_by = [terraform_data.proxmox_file_hash]
  }
}
