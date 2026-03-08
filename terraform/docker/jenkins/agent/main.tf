module "agents" {
  source = "../../../module/jenkins/agent"

  for_each = { for node in try(var.casc_config.jenkins.nodes, []) : node.permanent.name => node }

  name                  = each.value.permanent.name
  provider_config       = var.provider_config
  mounts                = var.mounts
  env                   = var.env
  controller_service_id = var.controller_service_id
  controller_image      = var.controller_image
}
