# outputs.tf
# Exported identifiers for the Jenkins agent (ARM64) Docker containers.

output "agent_container_ids" {
  description = "Docker container IDs for Jenkins agents keyed by Jenkins node name."
  value = {
    for node_name, container in docker_container.jenkins_agent : node_name => container.id
  }
}

output "agent_container_names" {
  description = "Docker container names for Jenkins agents keyed by Jenkins node name."
  value = {
    for node_name, container in docker_container.jenkins_agent : node_name => container.name
  }
}
