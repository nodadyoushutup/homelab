locals {
  service_name  = "rag-engine"
  internal_port = 8080

  env_file_contents = trimspace(var.env_file_path) != "" ? try(file(var.env_file_path), "") : ""
  env_file_pairs = [
    for raw_line in split("\n", replace(local.env_file_contents, "\r\n", "\n")) : {
      key   = trimspace(split("=", trimspace(raw_line))[0])
      value = trimspace(join("=", slice(split("=", trimspace(raw_line)), 1, length(split("=", trimspace(raw_line))))))
    }
    if trimspace(raw_line) != "" && !startswith(trimspace(raw_line), "#") && length(split("=", trimspace(raw_line))) > 1
  ]
  env_passthrough_keys = toset([
    "GOOGLE_API_KEY",
    "GOOGLE_GENAI_USE_VERTEXAI",
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "OPENAI_ORG_ID",
    "OPENAI_ORGANIZATION",
    "OPENAI_PROJECT",
    "VOYAGE_API_KEY",
    "RAG_VOYAGE_BASE_URL",
    "GOOGLE_CLOUD_PROJECT",
    "GOOGLE_CLOUD_LOCATION",
    "RAG_ALLOWED_PATH_PREFIXES",
    "RAG_BACKFILL_MAX_FILE_BYTES",
    "RAG_CHROMA_ADD_BATCH_SIZE",
    "RAG_CHROMA_COLLECTION",
    "RAG_CHROMA_HOST",
    "RAG_CHROMA_HTTP_BASE_DELAY_SEC",
    "RAG_CHROMA_HTTP_MAX_DELAY_SEC",
    "RAG_CHROMA_HTTP_MAX_RETRIES",
    "RAG_CHROMA_LIST_BATCH",
    "RAG_CHROMA_PORT",
    "RAG_CHUNK_CHARS",
    "RAG_CHUNK_OVERLAP",
    "RAG_EMBEDDING_MODEL",
    "RAG_EMBEDDING_PROVIDER",
    "RAG_EMBED_BASE_DELAY_SEC",
    "RAG_EMBED_MAX_DELAY_SEC",
    "RAG_EMBED_MAX_RETRIES",
    "RAG_EMBED_MIN_INTERVAL_SEC",
    "RAG_ENGINE_API_KEY",
    "RAG_EXCLUDE_FILE_SUFFIXES",
    "RAG_EXCLUDE_PATH_SEGMENTS",
    "RAG_GIT_LOG_TIMEOUT_SEC",
    "RAG_INDEX_SCHEMA_VERSION",
    "RAG_LOG_LEVEL",
    "RAG_MEMORY_DECLARATIVE_COLLECTION",
    "RAG_MEMORY_DECLARATIVE_TIE_BIAS",
    "RAG_MEMORY_DEDUP_DISTANCE_MAX",
    "RAG_MEMORY_EPISODIC_COLLECTION",
    "RAG_MEMORY_EPISODIC_TTL_DAYS",
    "RAG_MEMORY_RECALL_BODY_MAX_CHARS",
    "RAG_MEMORY_RECALL_MAX_K",
    "RAG_MEMORY_RECALL_REFRESH_DAYS",
    "RAG_MEMORY_STALE_LIST_DEFAULT",
    "RAG_MD_MAX_SECTION_HEADING_LEVEL",
    "RAG_OFFICE_DOCX_PARAS_PER_CHUNK",
    "RAG_OFFICE_ODT_PARAS_PER_CHUNK",
    "RAG_OFFICE_PPTX_SLIDES_PER_CHUNK",
    "RAG_OPENAI_EMBEDDING_DIMENSIONS",
    "RAG_OPENAI_EMBED_BATCH_SIZE",
    "RAG_OPENAI_TIMEOUT_SEC",
    "RAG_ANTHROPIC_EMBEDDING_DIMENSIONS",
    "RAG_ANTHROPIC_EMBED_BATCH_SIZE",
    "RAG_ANTHROPIC_TIMEOUT_SEC",
    "RAG_PDF_FUSION_SIMILARITY",
    "RAG_PDF_MAX_PAGES",
    "RAG_PDF_OCR_DPI",
    "RAG_STRUCTURED_CHUNK_OVERLAP",
    "RAG_STRUCTURED_MAX_CHUNK_CHARS",
    "RAG_TABULAR_ROWS_PER_CHUNK",
    "RAG_TESSERACT_LANG",
    "RAG_TESSERACT_PSM",
    "RAG_WORKSPACE_MOUNT",
    "RAG_XLSX_MAX_ROWS_PER_SHEET",
    "RAG_XLSX_MAX_SHEETS",
  ])
  parsed_env = {
    for pair in local.env_file_pairs : pair.key => pair.value
    if contains(local.env_passthrough_keys, pair.key)
  }
  default_env = {
    TZ                              = var.timezone
    RAG_CHROMA_HOST                 = var.chroma_host
    RAG_CHROMA_PORT                 = tostring(var.chroma_port)
    RAG_CHROMA_COLLECTION           = var.chroma_collection
    RAG_EMBEDDING_PROVIDER          = lower(var.embedding_provider)
    RAG_EMBEDDING_MODEL             = var.embedding_model
    RAG_OPENAI_EMBEDDING_DIMENSIONS = var.openai_embedding_dimensions
    RAG_WORKSPACE_MOUNT             = var.workspace_mount
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)

  swarm_nfs_ready = (
    trimspace(var.swarm_nfs_code_device) != "" &&
    trimspace(var.swarm_nfs_config_device) != "" &&
    trimspace(var.swarm_nfs_volume_type) != "" &&
    trimspace(var.swarm_nfs_volume_o_rw) != "" &&
    trimspace(var.swarm_nfs_volume_o_ro) != ""
  )
  swarm_nfs_code_target = trimspace(element(split(":", trimspace(var.swarm_nfs_code_device)), length(split(":", trimspace(var.swarm_nfs_code_device))) - 1))
  swarm_nfs_code_mounts = local.swarm_nfs_ready ? [{
    type      = "volume"
    source    = "${local.service_name}-mnt-eapp-code"
    target    = local.swarm_nfs_code_target
    read_only = true
    volume_options = {
      driver_name = "local"
      driver_options = {
        type   = trimspace(var.swarm_nfs_volume_type)
        o      = trimspace(var.swarm_nfs_volume_o_ro)
        device = trimspace(var.swarm_nfs_code_device)
      }
      no_copy = false
    }
  }] : []
}


locals {
  pull_ref                      = var.image_reference
  pull_at_stripped              = split("@", local.pull_ref)[0]
  pull_colon_parts              = split(":", local.pull_at_stripped)
  pull_image_repository         = length(local.pull_colon_parts) <= 1 ? local.pull_at_stripped : join(":", slice(local.pull_colon_parts, 0, length(local.pull_colon_parts) - 1))
  pull_repo_slash_parts         = split("/", local.pull_image_repository)
  pull_registry_host            = length(local.pull_repo_slash_parts) >= 2 && (strcontains(local.pull_repo_slash_parts[0], ".") || strcontains(local.pull_repo_slash_parts[0], ":") || lower(local.pull_repo_slash_parts[0]) == "localhost") ? local.pull_repo_slash_parts[0] : "docker.io"
  pull_normalized_registry_host = lower(trimspace(local.pull_registry_host))
  pull_auth_matches = [
    for a in local.docker_registry_auths : a
    if lower(trimspace(replace(replace(try(a.address, "ghcr.io"), "https://", ""), "http://", ""))) == local.pull_normalized_registry_host
  ]
  pull_selected_auth = length(local.pull_auth_matches) > 0 ? local.pull_auth_matches[0] : (
    length(local.docker_registry_auths) == 1 ? local.docker_registry_auths[0] : null
  )
  pull_server_address = local.pull_selected_auth == null ? "" : trimspace(replace(replace(try(local.pull_selected_auth.address, "ghcr.io"), "https://", ""), "http://", ""))
  docker_service_pull_auth_map = local.pull_selected_auth == null ? {} : {
    pull = {
      server_address = local.pull_server_address
      username       = local.pull_selected_auth.username
      password       = local.pull_selected_auth.password
    }
  }
}

locals {
  docker_registry_auths = coalesce(try(var.swarm_docker_provider_config.registry_auths, null), [])
}
