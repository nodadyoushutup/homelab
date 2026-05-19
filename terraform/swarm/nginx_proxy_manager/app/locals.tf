locals {
  stack_name      = "nginx-proxy-manager"
  image_reference = "jc21/nginx-proxy-manager:2.12.6@sha256:6ab097814f54b1362d5fd3c5884a01ddd5878aaae9992ffd218439180f0f92f3"
}




locals {
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
