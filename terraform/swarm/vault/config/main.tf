resource "vault_mount" "kv" {
  path = var.mount_path
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "grouped" {
  for_each = local.merged_secret_payloads

  mount               = vault_mount.kv.path
  name                = each.value.name
  data_json           = jsonencode(each.value.payload)
  delete_all_versions = true
}
