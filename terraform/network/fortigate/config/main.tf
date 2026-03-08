locals {
  effective_config = jsondecode(jsonencode(var.config))

  virtual_ip_specs = {
    for vip in try(local.effective_config.virtual_ips, []) :
    vip.name => vip
  }

  firewall_policy_specs = {
    for policy in try(local.effective_config.firewall_policies, []) :
    tostring(policy.policyid) => policy
  }
}

resource "fortios_firewall_vip" "this" {
  for_each = local.virtual_ip_specs

  name        = each.value.name
  type        = try(each.value.type, "static-nat")
  extintf     = each.value.extintf
  extip       = each.value.extip
  portforward = try(each.value.portforward, "enable")
  protocol    = try(each.value.protocol, "tcp")
  extport     = tostring(each.value.extport)
  mappedport  = tostring(each.value.mappedport)
  status      = try(each.value.status, "enable")
  comment     = try(each.value.comment, null)

  dynamic "mappedip" {
    for_each = each.value.mappedip

    content {
      range = mappedip.value.range
    }
  }

  lifecycle {
    ignore_changes = [dynamic_sort_subtable, get_all_tables]
  }
}

resource "fortios_firewall_policy" "this" {
  for_each = local.firewall_policy_specs

  depends_on = [fortios_firewall_vip.this]

  policyid   = tonumber(each.value.policyid)
  name       = try(each.value.name, null)
  action     = try(each.value.action, "accept")
  status     = try(each.value.status, "enable")
  schedule   = try(each.value.schedule, "always")
  nat        = try(each.value.nat, "disable")
  logtraffic = try(each.value.logtraffic, "all")
  match_vip  = try(each.value.match_vip, "enable")
  comments   = try(each.value.comments, null)

  dynamic "srcintf" {
    for_each = try(each.value.srcintf, [])

    content {
      name = srcintf.value.name
    }
  }

  dynamic "dstintf" {
    for_each = try(each.value.dstintf, [])

    content {
      name = dstintf.value.name
    }
  }

  dynamic "srcaddr" {
    for_each = try(each.value.srcaddr, [])

    content {
      name = srcaddr.value.name
    }
  }

  dynamic "dstaddr" {
    for_each = try(each.value.dstaddr, [])

    content {
      name = dstaddr.value.name
    }
  }

  dynamic "service" {
    for_each = try(each.value.service, [])

    content {
      name = service.value.name
    }
  }

  lifecycle {
    ignore_changes = [dynamic_sort_subtable, get_all_tables, comments]
  }
}

import {
  for_each = local.virtual_ip_specs
  to       = fortios_firewall_vip.this[each.key]
  id       = each.value.name
}

import {
  for_each = local.firewall_policy_specs
  to       = fortios_firewall_policy.this[each.key]
  id       = tostring(each.value.policyid)
}
