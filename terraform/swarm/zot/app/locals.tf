locals {
  auth_enabled = fileexists(var.htpasswd_path)

  zot_config_raw = templatefile("${path.module}/files/zot-config.json.tpl", {
    auth_enabled = local.auth_enabled
  })
  zot_config = jsondecode(local.zot_config_raw)

  config_hash  = substr(sha256(local.zot_config_raw), 0, 8)
  force_update = parseint(substr(local.config_hash, 0, 8), 16)
}
