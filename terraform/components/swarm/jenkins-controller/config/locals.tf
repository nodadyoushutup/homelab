locals {
  repo_root            = abspath("${path.module}/../../../..")
  job_definition_root  = trimsuffix(var.job_definition_root, "/")
  job_definition_files = sort(fileset(local.repo_root, "${local.job_definition_root}/${var.job_definition_glob}"))

  job_specs = {
    for repo_relative_file in local.job_definition_files :
    trimsuffix(trimprefix(repo_relative_file, "${local.job_definition_root}/"), ".jenkins") => {
      repo_relative_file = repo_relative_file
      script_path        = repo_relative_file
      job_name           = trimsuffix(basename(repo_relative_file), ".jenkins")
      folder_path        = dirname(trimsuffix(trimprefix(repo_relative_file, "${local.job_definition_root}/"), ".jenkins")) == "." ? "" : dirname(trimsuffix(trimprefix(repo_relative_file, "${local.job_definition_root}/"), ".jenkins"))
      description        = "Managed by Terraform. Multibranch pipeline for ${replace(repo_relative_file, ".jenkins", ".sh")} from this repository."
      source_id          = md5("${var.github_repo_url}:${repo_relative_file}")
    }
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
      description = "Managed by Terraform from ${local.job_definition_root}/${folder_path}"
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
    var.manage_github_credentials &&
    var.github_credentials_id != "" &&
    var.github_credentials_username != "" &&
    var.github_credentials_password != ""
  )

  effective_github_credentials_id = local.manage_github_credentials ? jenkins_credential_username.github[0].name : var.github_credentials_id
}
