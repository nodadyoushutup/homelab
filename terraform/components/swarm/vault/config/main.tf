# main.tf
# Vault KV v2 mount and grouped secrets merged from tfvars payloads and secret files.

resource "vault_mount" "kv" {
  path = local.mount_path
  type = "kv-v2"
}

resource "vault_kv_secret_v2" "grouped" {
  for_each = local.merged_secret_payloads

  mount               = vault_mount.kv.path
  name                = each.value.name
  data_json           = jsonencode(each.value.payload)
  delete_all_versions = true
}
