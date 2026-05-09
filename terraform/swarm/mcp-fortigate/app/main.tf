locals {
  service_name = "mcp-fortigate"

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  parsed_env = {
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) :
    trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  }
  default_env = {
    TZ                   = var.timezone
    FORTIGATE_HOST       = "192.168.1.1"
    FORTIGATE_PORT       = "443"
    FORTIGATE_VDOM       = "root"
    FORTIGATE_VERIFY_SSL = "false"
    FORTIGATE_TIMEOUT    = "30"
    MCP_SERVER_PORT      = "8814"
    MCP_HTTP_PATH        = "/mcp"
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

module "mcp_fortigate" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "ghcr.io"
  registry_auth         = var.registry_auth
  internal_port         = 8814
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "1000:1000"
  cap_drop              = ["ALL"]
}
