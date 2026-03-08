resource "vault_mount" "kv" {
  path = var.mount_path
  type = "kv-v2"
}

locals {
  flattened_secrets = {
    for item in flatten([
      for group_name, grouped_entries in var.secrets : [
        for secret_name, payload in grouped_entries : {
          key         = "${group_name}/${secret_name}"
          name        = "${group_name}/${secret_name}"
          group       = group_name
          secret_name = secret_name
          payload     = payload
        }
      ]
    ]) : item.key => item
  }

  flattened_secret_files = {
    for item in flatten([
      for group_name, grouped_entries in var.secret_files : [
        for secret_name, files in grouped_entries : {
          key   = "${group_name}/${secret_name}"
          name  = "${group_name}/${secret_name}"
          files = files
        }
      ]
    ]) : item.key => item
  }

  merged_secret_payloads = {
    for key in setunion(toset(keys(local.flattened_secrets)), toset(keys(local.flattened_secret_files))) : key => {
      name = key
      payload = merge(
        try(local.flattened_secrets[key].payload, {}),
        try({
          for field_name, field_path in local.flattened_secret_files[key].files :
          field_name => file(field_path)
        }, {})
      )
    }
  }
}

resource "vault_kv_secret_v2" "grouped" {
  for_each = local.merged_secret_payloads

  mount               = vault_mount.kv.path
  name                = each.value.name
  data_json           = jsonencode(each.value.payload)
  delete_all_versions = true
}
