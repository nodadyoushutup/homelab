output "service_name" {
  value = docker_service.torrent_manager.name
}

output "published_port" {
  value = 9030
}
