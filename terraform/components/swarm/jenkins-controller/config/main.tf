# main.tf
# Jenkins folders, multibranch pipeline jobs, and optional GitHub credential.

resource "jenkins_folder" "pipeline_folder_level_1" {
  for_each = local.folder_specs_level_1

  name        = each.value.name
  description = each.value.description
}

resource "jenkins_folder" "pipeline_folder_level_2" {
  for_each = local.folder_specs_level_2

  name        = each.value.name
  folder      = jenkins_folder.pipeline_folder_level_1[each.value.parent_path].id
  description = each.value.description
}

resource "jenkins_folder" "pipeline_folder_level_3" {
  for_each = local.folder_specs_level_3

  name        = each.value.name
  folder      = jenkins_folder.pipeline_folder_level_2[each.value.parent_path].id
  description = each.value.description
}

resource "jenkins_credential_username" "github" {
  count = local.manage_github_credentials ? 1 : 0

  name        = local.github_credentials_id
  description = local.github_credentials_description
  username    = local.github_credentials_username
  password    = local.github_credentials_password
  scope       = local.github_credentials_scope
}

resource "jenkins_job" "pipeline_job" {
  for_each = local.job_specs

  name = each.value.job_name
  folder = (
    each.value.folder_path == "" ? null :
    length(split("/", each.value.folder_path)) == 1 ? jenkins_folder.pipeline_folder_level_1[each.value.folder_path].id :
    length(split("/", each.value.folder_path)) == 2 ? jenkins_folder.pipeline_folder_level_2[each.value.folder_path].id :
    jenkins_folder.pipeline_folder_level_3[each.value.folder_path].id
  )

  template = templatefile("${path.module}/job/pipeline.xml.tftpl", {
    description                = each.value.description
    repo_url                   = local.github_repo_url
    script_path                = each.value.script_path
    source_id                  = each.value.source_id
    credentials_id             = local.effective_github_credentials_id
    branch_includes            = local.branch_discovery_includes
    branch_excludes            = local.branch_discovery_excludes
    prune_dead_branches        = local.prune_dead_branches
    orphaned_item_days_to_keep = local.orphaned_item_days_to_keep
    orphaned_item_num_to_keep  = local.orphaned_item_num_to_keep
  })
}
