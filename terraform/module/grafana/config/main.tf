locals {
  folder_inputs = concat(
    try(var.grafana_config_inputs.folders, []),
    var.folders
  )
  folders = [
    for folder in local.folder_inputs : {
      name = folder.name
      uid  = try(folder.uid, null)
    }
  ]

  folder_map = { for folder in local.folders : folder.name => folder }

  datasource_inputs = concat(
    try(var.grafana_config_inputs.datasources, []),
    var.datasources
  )

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

  dashboard_inputs = concat(
    try(var.grafana_config_inputs.dashboards, []),
    var.dashboards
  )
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
