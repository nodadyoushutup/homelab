locals {
  # Strip digest; keep tag in a separate pass below.
  at_stripped = split("@", var.image_reference)[0]

  # Tag is the segment after the last ':' (supports registry hosts with ports).
  colon_parts = split(":", local.at_stripped)
  image_repository = (
    length(local.colon_parts) <= 1 ? local.at_stripped : join(":", slice(local.colon_parts, 0, length(local.colon_parts) - 1))
  )

  repo_slash_parts = split("/", local.image_repository)

  # First path component is the registry when ref is hosted (not bare dockerhub short name).
  registry_host = (
    length(local.repo_slash_parts) >= 2 && (
      strcontains(local.repo_slash_parts[0], ".") ||
      strcontains(local.repo_slash_parts[0], ":") ||
      lower(local.repo_slash_parts[0]) == "localhost"
    ) ? local.repo_slash_parts[0] : "docker.io"
  )

  normalized_registry_host = lower(trimspace(local.registry_host))

  auth_matches = [
    for a in var.registry_auths : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.normalized_registry_host
  ]

  # docker_service.auth allows a single block; match image host, else single-cred fallback.
  selected_auth = (
    length(local.auth_matches) > 0 ? local.auth_matches[0] : (
      length(var.registry_auths) == 1 ? var.registry_auths[0] : null
    )
  )

  server_address = (
    local.selected_auth == null ? "" : trimspace(replace(replace(try(local.selected_auth.address, "ghcr.io"), "https://", ""), "http://", ""))
  )
}
