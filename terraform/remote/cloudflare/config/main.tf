locals {
  records_by_key = {
    for record in var.records : record.key => record
  }
}

resource "cloudflare_dns_record" "records" {
  for_each = local.records_by_key

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = each.value.ttl

  proxied  = contains(["A", "AAAA", "CNAME"], each.value.type) ? each.value.proxied : null
  priority = each.value.type == "MX" ? try(each.value.priority, null) : null
}

import {
  to = cloudflare_dns_record.records["argocd_a"]
  id = "${var.zone_id}/54d70a0b4dc08f71d13acc485e5a8747"
}

import {
  to = cloudflare_dns_record.records["dozzle_a"]
  id = "${var.zone_id}/e81e8b97ddde382d87d5426947a7b9d4"
}

import {
  to = cloudflare_dns_record.records["grafana_a"]
  id = "${var.zone_id}/1a794a8434d1191239de70ded25b4060"
}

import {
  to = cloudflare_dns_record.records["graphite_a"]
  id = "${var.zone_id}/218ed60309f4712a10acde35aafc28e4"
}

import {
  to = cloudflare_dns_record.records["mcp_argocd_a"]
  id = "${var.zone_id}/085ce2e4e0e6749ef31beb2cb397ce42"
}

import {
  to = cloudflare_dns_record.records["mcp_atlassian_a"]
  id = "${var.zone_id}/b0693f6b4c96d272c494f6b896c6dd88"
}

import {
  to = cloudflare_dns_record.records["mcp_cloudflare_a"]
  id = "${var.zone_id}/236565c81a91b6bb063d3bd7d555bec9"
}

import {
  to = cloudflare_dns_record.records["mcp_fortigate_a"]
  id = "${var.zone_id}/aaa8a12df1b70891e80a6635f0c67e82"
}

import {
  to = cloudflare_dns_record.records["mcp_github_a"]
  id = "${var.zone_id}/3f5b574a3a9b932f92119a2041bc49c4"
}

import {
  to = cloudflare_dns_record.records["minio_a"]
  id = "${var.zone_id}/3dfa65d87a4114aef1522d6cd5911be5"
}

import {
  to = cloudflare_dns_record.records["nginx_proxy_manager_a"]
  id = "${var.zone_id}/eac3a079f5bb8c96aa5058309a2d074d"
}

import {
  to = cloudflare_dns_record.records["wildcard_a"]
  id = "${var.zone_id}/0bffcd8843a81795b30d43ad12f521a3"
}

import {
  to = cloudflare_dns_record.records["apex_a"]
  id = "${var.zone_id}/75764804d2d2850e4570847ac987f5f8"
}

import {
  to = cloudflare_dns_record.records["picsur_a"]
  id = "${var.zone_id}/8ff9d2f175907625d9d0d2f053973f2b"
}

import {
  to = cloudflare_dns_record.records["prometheus_a"]
  id = "${var.zone_id}/ac80c0d064a5cb611609ed1235ed1d1e"
}

import {
  to = cloudflare_dns_record.records["tautulli_a"]
  id = "${var.zone_id}/6a84541bb92f64a3092e86482f1626f5"
}

import {
  to = cloudflare_dns_record.records["thelounge_a"]
  id = "${var.zone_id}/bf766365010ae07890161f0a3912f319"
}

import {
  to = cloudflare_dns_record.records["webserver_image_a"]
  id = "${var.zone_id}/11dbb2cd48295facba7281367c50ef59"
}

import {
  to = cloudflare_dns_record.records["www_a"]
  id = "${var.zone_id}/3690a005aadb04ca07b6f02e193e3af2"
}

import {
  to = cloudflare_dns_record.records["mx_alt2"]
  id = "${var.zone_id}/d6807385c4373e0d953f5679f3d2fba0"
}

import {
  to = cloudflare_dns_record.records["mx_alt3"]
  id = "${var.zone_id}/d0622ee1d0e343d4903262c47a3ad23a"
}

import {
  to = cloudflare_dns_record.records["mx_alt1"]
  id = "${var.zone_id}/9c139bc7ba59cd78eda08d0c3e075181"
}

import {
  to = cloudflare_dns_record.records["mx_alt4"]
  id = "${var.zone_id}/e0963fbd9415f987bcbb90f46274aee9"
}

import {
  to = cloudflare_dns_record.records["mx_primary"]
  id = "${var.zone_id}/3d11f6b1a5f9bd8ac186d7da6fce0b53"
}

import {
  to = cloudflare_dns_record.records["txt_spf"]
  id = "${var.zone_id}/a5f061f155e6a92013efc76919531004"
}

import {
  to = cloudflare_dns_record.records["txt_google_verification"]
  id = "${var.zone_id}/ada099894705125329985b00094f3a36"
}
