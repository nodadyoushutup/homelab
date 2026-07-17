# locals.tf
# Single source of truth for Vault KV config (secrets) values (resources read local.* only).

locals {
  mount_path   = var.mount_path
  secret_files = var.secret_files
  secrets      = var.secrets

  flattened_secrets = {
    for item in flatten([
      for group_name, grouped_entries in local.secrets : [
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
      for group_name, grouped_entries in local.secret_files : [
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
