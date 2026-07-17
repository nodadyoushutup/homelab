locals {
  cleanup_interval_seconds = 604800
  retention_seconds        = 604800
  image                    = "docker:29.2.1-cli@sha256:cab69e2d0a1a2ea9a1ce1060252f439e83483ae41ec09317aecb33b08a0656a5"
  arm64_image              = "docker:29.2.1-cli@sha256:b419ff204d51c59cf7e3e01c4277dad148fc5f300f172c2f65700a1cac93e7c1"

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
}
