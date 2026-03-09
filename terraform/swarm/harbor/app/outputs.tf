output "service_names" {
  description = "Harbor swarm service names managed by this stage."
  value = {
    log           = docker_service.log.name
    registry      = docker_service.registry.name
    registryctl   = docker_service.registryctl.name
    postgresql    = docker_service.postgresql.name
    core          = docker_service.core.name
    portal        = docker_service.portal.name
    jobservice    = docker_service.jobservice.name
    redis         = docker_service.redis.name
    proxy         = docker_service.proxy.name
    trivy_adapter = docker_service.trivy_adapter.name
  }
}

output "proxy_http_endpoint" {
  description = "Published Harbor proxy HTTP port."
  value       = var.proxy_published_port
}
