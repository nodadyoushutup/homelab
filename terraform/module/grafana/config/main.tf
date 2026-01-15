locals {
  default_folders = [
    {
      name = "TrueNAS"
      uid  = "truenas-fold"
    },
    {
      name = "Node Exporter"
      uid  = "node-exporter-fold"
    }
  ]
  folder_inputs = local.default_folders
  folders = [
    for folder in local.folder_inputs : {
      name = folder.name
      uid  = try(folder.uid, null)
    }
  ]

  folder_map = { for folder in local.folders : folder.name => folder }

  datasource_inputs = var.datasources

  datasources = [
    for ds in local.datasource_inputs : {
      name                     = ds.name
      type                     = try(ds.type, "prometheus")
      url                      = ds.url
      access_mode              = try(ds.access_mode, "proxy")
      is_default               = try(ds.is_default, false)
      uid                      = try(ds.uid, null)
      username                 = try(ds.username, "")
      json_data_encoded        = jsonencode(try(ds.json_data, {}))
      secure_json_data_encoded = jsonencode(try(ds.secure_json_data, {}))
      basic_auth_enabled       = try(ds.basic_auth_enabled, false)
      basic_auth_username      = try(ds.basic_auth_username, "")
    }
  ]

  datasource_map = { for ds in local.datasources : ds.name => ds }

  default_dashboards = [
    {
      name      = "Node Exporter - Overview"
      file      = "node-exporter-overview.json"
      folder    = "Node Exporter"
      uid       = "node-exp-overview"
      overwrite = true
    },
    {
      name      = "Node Exporter - CPU"
      file      = "node-exporter-cpu-load.json"
      folder    = "Node Exporter"
      uid       = "node-exp-cpu"
      overwrite = true
    },
    {
      name      = "Node Exporter - Memory"
      file      = "node-exporter-memory.json"
      folder    = "Node Exporter"
      uid       = "node-exp-mem"
      overwrite = true
    },
    {
      name      = "Node Exporter - Disk"
      file      = "node-exporter-storage.json"
      folder    = "Node Exporter"
      uid       = "node-exp-storage"
      overwrite = true
    },
    {
      name      = "Node Exporter - Network"
      file      = "node-exporter-network.json"
      folder    = "Node Exporter"
      uid       = "node-exp-net"
      overwrite = true
    },
    {
      name      = "Node Exporter - Processes"
      file      = "node-exporter-processes.json"
      folder    = "Node Exporter"
      uid       = "node-exp-proc"
      overwrite = true
    },
    {
      name      = "Node Exporter - Hardware"
      file      = "node-exporter-hardware.json"
      folder    = "Node Exporter"
      uid       = "node-exp-hw"
      overwrite = true
    },
    {
      name      = "TrueNAS - Overview"
      file      = "truenas-overview.json"
      folder    = "TrueNAS"
      uid       = "truenas-overview"
      overwrite = true
    },
    {
      name      = "TrueNAS - CPU"
      file      = "truenas-cpu-thermals.json"
      folder    = "TrueNAS"
      uid       = "truenas-cpu"
      overwrite = true
    },
    {
      name      = "TrueNAS - Disk Throughput"
      file      = "truenas-disk-throughput.json"
      folder    = "TrueNAS"
      uid       = "truenas-disk-tput"
      overwrite = true
    },
    {
      name      = "TrueNAS - Disk Latency & Queues"
      file      = "truenas-disk-latency.json"
      folder    = "TrueNAS"
      uid       = "truenas-disk-lat"
      overwrite = true
    },
    {
      name      = "TrueNAS - Disk SLA & Sizes"
      file      = "truenas-disk-sla.json"
      folder    = "TrueNAS"
      uid       = "truenas-disk-sla"
      overwrite = true
    },
    {
      name      = "TrueNAS - Extended Disk Ops"
      file      = "truenas-disk-extended.json"
      folder    = "TrueNAS"
      uid       = "truenas-disk-ext"
      overwrite = true
    },
    {
      name      = "TrueNAS - SMART & ZFS"
      file      = "truenas-smart-zfs.json"
      folder    = "TrueNAS"
      uid       = "truenas-smart-zfs"
      overwrite = true
    },
    {
      name      = "TrueNAS - Services & Network"
      file      = "truenas-services-network.json"
      folder    = "TrueNAS"
      uid       = "truenas-svc-net"
      overwrite = true
    },
    {
      name      = "TrueNAS - K3s & Diagnostics"
      file      = "truenas-k3s-diagnostics.json"
      folder    = "TrueNAS"
      uid       = "truenas-k3s"
      overwrite = true
    }
  ]
  dashboard_inputs = local.default_dashboards
  legacy_dashboard_basenames = ["graphite-truenas-overview.json"]
  filtered_dashboard_inputs = [
    for dash in local.dashboard_inputs : dash
    if !contains(local.legacy_dashboard_basenames, lower(basename(try(dash.file, ""))))
  ]

  dashboards = [
    for dash in local.filtered_dashboard_inputs : {
      key       = coalesce(try(dash.name, null), basename(dash.file))
      folder    = try(dash.folder, null)
      overwrite = try(dash.overwrite, true)
      uid       = try(dash.uid, null)
      file_path = (
        try(dash.absolute, false) ||
        startswith(dash.file, "/") ||
        length(regexall("^[A-Za-z]:", dash.file)) > 0
      ) ? dash.file : format("%s/dashboards/%s", path.module, dash.file)
    }
  ]

  dashboard_defaults = {
    refresh = "10s"
    time = {
      from = "now-10m"
      to   = "now"
    }
  }

  dashboards_with_payload = [
    for dash in local.dashboards : merge(dash, {
      content = jsonencode(merge(
        jsondecode(file(dash.file_path)),
        dash.uid == null ? {} : { uid = dash.uid },
        local.dashboard_defaults
      ))
    })
  ]

  dashboard_map = { for dash in local.dashboards_with_payload : dash.key => dash }

}

resource "grafana_folder" "this" {
  for_each = local.folder_map

  title = each.value.name
  uid   = try(each.value.uid, null)
}

resource "grafana_data_source" "this" {
  for_each = local.datasource_map

  name        = each.value.name
  type        = each.value.type
  url         = each.value.url
  access_mode = each.value.access_mode
  is_default  = each.value.is_default
  uid         = coalesce(each.value.uid, "")
  username    = each.value.username

  json_data_encoded        = each.value.json_data_encoded
  secure_json_data_encoded = each.value.secure_json_data_encoded

  basic_auth_enabled  = each.value.basic_auth_enabled
  basic_auth_username = each.value.basic_auth_username
}

resource "grafana_dashboard" "this" {
  for_each = local.dashboard_map

  config_json = each.value.content
  folder      = (each.value.folder != null && contains(keys(grafana_folder.this), each.value.folder)) ? grafana_folder.this[each.value.folder].id : null
  overwrite   = each.value.overwrite
}
