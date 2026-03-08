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
}

resource "vault_kv_secret_v2" "grouped" {
  for_each = local.flattened_secrets

  mount               = vault_mount.kv.path
  name                = each.value.name
  data_json           = jsonencode(each.value.payload)
  delete_all_versions = true
}
