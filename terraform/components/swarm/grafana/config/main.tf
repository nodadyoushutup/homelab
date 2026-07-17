# main.tf
# Grafana datasources and dashboards applied against a running Grafana instance.

resource "terraform_data" "node_exporter_file_hash" {
  triggers_replace = local.node_exporter_file_hash
}

resource "terraform_data" "cadvisor_file_hash" {
  triggers_replace = local.cadvisor_file_hash
}

resource "terraform_data" "truenas_file_hash" {
  triggers_replace = local.truenas_file_hash
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
  for_each = { for ds in local.datasources : ds.uid => ds }

  name              = each.value.name
  uid               = each.value.uid
  type              = each.value.type
  url               = each.value.url
  is_default        = each.value.is_default
  json_data_encoded = each.value.json_data != null ? jsonencode(each.value.json_data) : null
}

resource "grafana_dashboard" "cadvisor" {
  overwrite   = true
  config_json = local.cadvisor_content

  lifecycle {
    replace_triggered_by = [terraform_data.cadvisor_file_hash]
  }
}

resource "grafana_dashboard" "node_exporter" {
  overwrite   = true
  config_json = local.node_exporter_content

  lifecycle {
    replace_triggered_by = [terraform_data.node_exporter_file_hash]
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
