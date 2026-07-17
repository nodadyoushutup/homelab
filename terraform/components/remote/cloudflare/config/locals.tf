# locals.tf
# Single source of truth for the Cloudflare provider/DNS record values (resources read local.* only).

locals {
  provider_config = var.provider_config
  zone_id         = var.zone_id

  records_by_key = {
    for record in var.records : record.key => record
  }
}
