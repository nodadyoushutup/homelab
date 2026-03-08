locals {
  records_by_key = {
    for record in var.records : record.key => record
  }
}

resource "cloudflare_dns_record" "records" {
  for_each = local.records_by_key

  zone_id = var.zone_id
  name    = each.value.name
  type    = "A"
  content = each.value.content
  ttl     = each.value.ttl

  proxied = each.value.proxied
}
