locals {
  service_name = "mcp-terraform"

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  parsed_env = {
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) :
    trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  }
  default_env = {
    TZ = var.timezone
  }
  effective_env      = merge(local.default_env, local.parsed_env, var.env)
  effective_toolsets = lookup(local.effective_env, "MCP_TERRAFORM_TOOLSETS", var.terraform_toolsets)
}

module "mcp_terraform" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "harbor.nodadyoushutup.com"
  registry_auth         = var.registry_auth
  internal_port         = 8080
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  user                  = "65532:65532"
  cap_drop              = ["ALL"]
  args = [
    "streamable-http",
    "--transport-host",
    "0.0.0.0",
    "--transport-port",
    "8080",
    "--mcp-endpoint",
    "/mcp",
    "--toolsets",
    local.effective_toolsets,
  ]
}
