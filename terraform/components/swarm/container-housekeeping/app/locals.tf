# locals.tf
# Single source of truth for container-housekeeping Swarm service values (resources read local.* only).

locals {
  docker_selected = var.docker_providers[var.docker_machine]
  swarm_docker_provider_config = {
    docker         = { host = local.docker_selected.host, ssh_opts = local.docker_selected.ssh_opts }
    registry_auths = var.registry_auths
  }

  cleanup_interval_seconds = 604800
  retention_seconds        = 604800

  cleanup_script = <<-SCRIPT
    while :; do
      sleep ${local.cleanup_interval_seconds}
      cutoff_epoch="$(( $(date -u +%s) - ${local.retention_seconds} ))"

      docker container ls --all --filter status=exited --format '{{.ID}}' |
        while read -r container_id; do
          finished_at="$(docker container inspect --format '{{.State.FinishedAt}}' "$container_id" 2>/dev/null || true)"
          normalized_finished_at="$(printf '%s' "$finished_at" | cut -d. -f1 | tr T ' ')"
          finished_epoch="$(date -u -d "$normalized_finished_at" +%s 2>/dev/null || true)"

          if [ -n "$finished_epoch" ] && [ "$finished_epoch" -lt "$cutoff_epoch" ]; then
            docker container rm "$container_id"
          fi
        done
    done
  SCRIPT

  # Fleet-common optional nested fields (post-audit: secrets/defaults double-pass).
  registry_auths           = coalesce(try(local.swarm_docker_provider_config.registry_auths, null), [])
  default_registry_address = "ghcr.io"
}
