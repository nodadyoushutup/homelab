locals {
  config_hash  = substr(sha256(jsonencode(local.zot_config)), 0, 8)
  force_update = parseint(substr(local.config_hash, 0, 8), 16)

  zot_http = merge(
    {
      address = "0.0.0.0"
      port    = tostring(var.http_port)
      realm   = var.http_realm
    },
    var.enable_auth ? {
      auth = {
        htpasswd = {
          path = "/etc/zot/htpasswd"
        }
        failDelay = 2
      }
    } : {}
  )

  zot_config = {
    distSpecVersion = "1.1.0-dev"
    storage = {
      rootDirectory = "/var/lib/registry"
      commit        = true
      gc            = true
      gcDelay       = var.storage_gc_delay
      gcInterval    = var.storage_gc_interval
    }
    http = local.zot_http
    log = {
      level = var.log_level
    }
    extensions = {
      ui = {
        enable = var.enable_ui
      }
      search = {
        enable = var.enable_search
      }
      mgmt = {
        enable = var.enable_mgmt
      }
    }
  }

  zot_config_json = jsonencode(local.zot_config)
}
