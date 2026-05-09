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
    TZ                    = var.timezone
    RAG_CHROMA_HOST       = var.chroma_host
    RAG_CHROMA_PORT       = tostring(var.chroma_port)
    RAG_CHROMA_COLLECTION = var.chroma_collection
    RAG_EMBEDDING_MODEL   = var.embedding_model
    RAG_WORKSPACE_MOUNT   = var.workspace_mount
  }
  effective_env = merge(local.default_env, local.parsed_env, var.env)
}

data "docker_network" "chromadb" {
  name = var.chromadb_network_name
}

resource "docker_network" "rag_engine" {
  name   = var.rag_engine_network_name
  driver = "overlay"
}

resource "docker_service" "rag_engine" {
  name = local.service_name

  dynamic "auth" {
    for_each = var.registry_auth == null ? [] : [var.registry_auth]

    content {
      server_address = try(auth.value.address, "ghcr.io")
      username       = auth.value.username
      password       = auth.value.password
    }
  }

  task_spec {
    placement {
      constraints = var.placement_constraints

      platforms {
        os           = "linux"
        architecture = var.platform_architecture
      }
    }

    networks_advanced {
      name    = docker_network.rag_engine.id
      aliases = [local.service_name]
    }

    networks_advanced {
      name    = data.docker_network.chromadb.id
      aliases = []
    }

    container_spec {
      image = var.image_reference
      env   = local.effective_env

      dns_config {
        nameservers = var.dns_nameservers
      }

      mounts {
        type      = "bind"
        source    = var.workspace_host_path
        target    = var.workspace_mount
        read_only = true
      }

      healthcheck {
        test         = ["CMD", "rag-engine-healthcheck"]
        interval     = "15s"
        timeout      = "5s"
        retries      = 10
        start_period = "30s"
      }
    }

    restart_policy {
      condition    = "on-failure"
      delay        = "10s"
      max_attempts = 3
      window       = "2m"
    }
  }

  mode {
    replicated {
      replicas = var.replicas
    }
  }

  update_config {
    order = "stop-first"
  }

  endpoint_spec {
    ports {
      target_port    = local.internal_port
      published_port = var.published_port
      protocol       = "tcp"
      publish_mode   = "ingress"
    }
  }
}
