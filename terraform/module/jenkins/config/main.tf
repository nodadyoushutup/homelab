locals {
  repo_url = "https://github.com/nodadyoushutup/homelab"

  # Jenkins pipeline wrappers are currently disabled repo-wide.
  jenkins_jobs         = {}
  multi_stage_services = {}
  single_stage_jobs    = {}

  multi_stage_jobs = length(local.multi_stage_services) == 0 ? {} : merge([
    for service, cfg in local.multi_stage_services : {
      for job_name, job in cfg.jobs :
      "${service}-${job_name}" => {
        name        = job_name
        folder      = service
        description = job.description
        script_path = job.script_path
      }
    }
  ]...)
}

resource "jenkins_folder" "jenkins_service" {
  name = "jenkins"
}

resource "jenkins_folder" "multi_stage_service" {
  for_each = local.multi_stage_services

  name = each.key
}

resource "jenkins_job" "multi_stage" {
  for_each = local.multi_stage_jobs

  name   = each.value.name
  folder = jenkins_folder.multi_stage_service[each.value.folder].id

  template = templatefile("${path.module}/job/bash_pipeline.xml.tmpl", {
    description = each.value.description
    script_path = each.value.script_path
    repo_url    = local.repo_url
  })
}

resource "jenkins_job" "jenkins" {
  for_each = local.jenkins_jobs

  name   = each.key
  folder = jenkins_folder.jenkins_service.id

  template = templatefile("${path.module}/job/bash_pipeline.xml.tmpl", {
    description = each.value.description
    script_path = each.value.script_path
    repo_url    = local.repo_url
  })
}

resource "jenkins_job" "single_stage" {
  for_each = local.single_stage_jobs

  name = each.key

  template = templatefile("${path.module}/job/bash_pipeline.xml.tmpl", {
    description = each.value.description
    script_path = each.value.script_path
    repo_url    = local.repo_url
  })
}
