# main.tf
# Cloudflare A DNS records managed from a declarative records list.

resource "cloudflare_dns_record" "records" {
  for_each = local.records_by_key

  zone_id = local.zone_id
  name    = each.value.name
  type    = "A"
  content = each.value.content
  ttl     = each.value.ttl

  proxied = each.value.proxied
}
