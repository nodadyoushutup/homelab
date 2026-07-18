# locals.tf
# Single source of truth for Jenkins controller config (folders/jobs/credentials) values (resources read local.* only).

locals {
  branch_discovery_excludes       = var.branch_discovery_excludes
  branch_discovery_includes       = var.branch_discovery_includes
  github_credentials_description  = var.github_credentials_description
  github_credentials_id           = var.github_credentials_id
  github_credentials_password     = var.github_credentials_password
  github_credentials_scope        = var.github_credentials_scope
  github_credentials_username     = var.github_credentials_username
  github_repo_url                 = var.github_repo_url
  job_definition_glob             = var.job_definition_glob
  job_definition_root_input       = var.job_definition_root
  manage_github_credentials_input = var.manage_github_credentials
  orphaned_item_days_to_keep      = var.orphaned_item_days_to_keep
  orphaned_item_num_to_keep       = var.orphaned_item_num_to_keep
  provider_config                 = var.provider_config
  prune_dead_branches             = var.prune_dead_branches

  repo_root           = abspath("${path.module}/../../../../..")
  job_definition_root = trimsuffix(local.job_definition_root_input, "/")
  job_folder_roots    = var.job_folder_roots

  job_definition_fileset = (
    local.job_definition_root == "" ?
    local.job_definition_glob :
    "${local.job_definition_root}/${local.job_definition_glob}"
  )

  # Structural path segments dropped from the derived Jenkins folder path so the
  # UI reads cleanly, e.g. terraform/components/swarm/grafana/pipeline/app.jenkins
  # -> folder terraform/swarm/grafana with job "app".
  folder_strip_segments = ["components", "pipeline"]

  # Only surface pipelines under an allowed top-level tree (terraform, packer).
  job_definition_files = [
    for repo_relative_file in sort(fileset(local.repo_root, local.job_definition_fileset)) :
    repo_relative_file
    if contains(local.job_folder_roots, split("/", repo_relative_file)[0])
  ]

  job_spec_list = [
    for repo_relative_file in local.job_definition_files : {
      repo_relative_file = repo_relative_file
      script_path        = repo_relative_file
      job_name           = trimsuffix(basename(repo_relative_file), ".jenkins")
      folder_path = join("/", [
        for segment in split("/", dirname(repo_relative_file)) : segment
        if !contains(local.folder_strip_segments, segment)
      ])
      description = "Managed by Terraform. Multibranch pipeline for ${replace(repo_relative_file, ".jenkins", ".sh")} from this repository."
      source_id   = md5("${local.github_repo_url}:${repo_relative_file}")
    }
  ]

  job_specs = {
    for spec in local.job_spec_list :
    (spec.folder_path == "" ? spec.job_name : "${spec.folder_path}/${spec.job_name}") => spec
  }

  folder_paths = sort(tolist(toset(flatten([
    for _, job in local.job_specs : [
      for depth in range(length(compact(split("/", job.folder_path)))) :
      join("/", slice(compact(split("/", job.folder_path)), 0, depth + 1))
    ]
  ]))))

  folder_specs = {
    for folder_path in local.folder_paths :
    folder_path => {
      name        = basename(folder_path)
      parent_path = length(split("/", folder_path)) > 1 ? join("/", slice(split("/", folder_path), 0, length(split("/", folder_path)) - 1)) : ""
      depth       = length(split("/", folder_path))
      description = "Managed by Terraform from ${folder_path}"
    }
  }

  folder_specs_level_1 = {
    for folder_path, spec in local.folder_specs :
    folder_path => spec
    if spec.depth == 1
  }

  folder_specs_level_2 = {
    for folder_path, spec in local.folder_specs :
    folder_path => spec
    if spec.depth == 2
  }

  folder_specs_level_3 = {
    for folder_path, spec in local.folder_specs :
    folder_path => spec
    if spec.depth == 3
  }

  manage_github_credentials = (
    local.manage_github_credentials_input &&
    local.github_credentials_id != "" &&
    local.github_credentials_username != "" &&
    local.github_credentials_password != ""
  )

  effective_github_credentials_id = local.manage_github_credentials ? jenkins_credential_username.github[0].name : local.github_credentials_id
}
