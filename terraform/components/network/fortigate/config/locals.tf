# locals.tf
# Single source of truth for the FortiGate provider/declarative config values (resources read local.* only).

locals {
  effective_config = jsondecode(jsonencode(var.config))

  virtual_ip_specs = {
    for vip in try(local.effective_config.virtual_ips, []) :
    vip.name => vip
  }

  virtual_ip_import_specs = {
    for vip in try(local.effective_config.virtual_ips, []) :
    vip.name => vip
    if try(vip.import_existing, false)
  }

  firewall_policy_specs = {
    for policy in try(local.effective_config.firewall_policies, []) :
    tostring(policy.policyid) => policy
  }

  firewall_policy_import_specs = {
    for policy in try(local.effective_config.firewall_policies, []) :
    tostring(policy.policyid) => policy
    if try(policy.import_existing, false)
  }

  dhcp_server_reservation_specs = {
    for dhcp in try(local.effective_config.dhcp_server_reservations, []) :
    tostring(dhcp.fosid) => dhcp
  }
}

locals {
  provider_config = var.provider_config

  fortigate_host        = trimspace(local.provider_config.fortigate.host)
  fortigate_port        = try(local.provider_config.fortigate.port, 443)
  fortigate_hostname    = local.fortigate_port == 443 ? local.fortigate_host : "${local.fortigate_host}:${local.fortigate_port}"
  fortigate_insecure    = try(local.provider_config.fortigate.insecure, true)
  fortigate_vdom        = try(local.provider_config.fortigate.vdom, "root")
  fortigate_api_token   = try(trimspace(local.provider_config.fortigate.api_token), "")
  fortigate_username    = try(trimspace(local.provider_config.fortigate.username), "")
  fortigate_password    = try(trimspace(local.provider_config.fortigate.password), "")
  fortigate_has_token   = local.fortigate_api_token != ""
  fortigate_has_userpwd = local.fortigate_username != "" && local.fortigate_password != ""
}
