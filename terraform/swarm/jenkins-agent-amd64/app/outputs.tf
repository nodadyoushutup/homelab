output "agent_service_ids" {
  description = "Docker Swarm service IDs for Jenkins agents keyed by Jenkins node name."
  value = {
    for node_name, service in docker_service.jenkins_agent : node_name => service.id
  }
}

output "agent_service_names" {
  description = "Docker Swarm service names for Jenkins agents keyed by Jenkins node name."
  value = {
    for node_name, service in docker_service.jenkins_agent : node_name => service.name
  }
}
