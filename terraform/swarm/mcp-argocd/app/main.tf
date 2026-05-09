locals {
  service_name = "mcp-argocd"

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  parsed_env = {
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) :
    trimspace(split("=", trimspace(raw_line))[0]) => join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line)))))
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  }
  default_env = {
    TZ = var.timezone
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

module "mcp_argocd" {
  source = "../../modules/mcp-service"

  service_name          = local.service_name
  image_reference       = var.image_reference
  registry_address      = "ghcr.io"
  registry_auth         = var.registry_auth
  internal_port         = 3000
  published_port        = var.published_port
  endpoint_host         = var.endpoint_host
  replicas              = var.replicas
  placement_constraints = var.placement_constraints
  platform_architecture = var.platform_architecture
  dns_nameservers       = var.dns_nameservers
  env                   = local.effective_env
  command               = ["sh", "-c"]
  args = [
    <<-EOT
      if [ "$${ARGOCD_INSECURE_SKIP_VERIFY:-false}" = "true" ]; then
        export NODE_TLS_REJECT_UNAUTHORIZED=0
      fi
      exec node dist/index.js http --port 3000
    EOT
  ]
  healthcheck = {
    test = [
      "CMD",
      "node",
      "-e",
      "fetch('http://127.0.0.1:3000/mcp',{headers:{'mcp-session-id':'healthcheck'}}).then(r=>process.exit(r.status<500?0:1)).catch(()=>process.exit(1))",
    ]
    interval     = "15s"
    timeout      = "5s"
    retries      = 10
    start_period = "30s"
  }
}
