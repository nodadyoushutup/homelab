output "project_ids" {
  description = "Project IDs keyed by project name."
  value = {
    for name, project in harbor_project.projects :
    name => project.project_id
  }
}

output "robot_account_names" {
  description = "Robot account full names keyed by resource key."
  value = {
    for name, account in harbor_robot_account.accounts :
    name => account.full_name
  }
}

output "robot_account_secrets" {
  description = "Robot account secrets keyed by resource key (set only on create or when provided by provider)."
  value = {
    for name, account in harbor_robot_account.accounts :
    name => account.secret
  }
  sensitive = true
}
