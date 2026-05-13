output "docker_service_auth_map" {
  description = "Singleton map for docker_service dynamic auth (kreuzwerker/docker allows at most one auth block)."
  value = (
    local.selected_auth == null ? {} : {
      pull = {
        server_address = local.server_address
        username       = local.selected_auth.username
        password       = local.selected_auth.password
      }
    }
  )
}
