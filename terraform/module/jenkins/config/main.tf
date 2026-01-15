locals {
  repo_url = "https://github.com/nodadyoushutup/homelab"

  jenkins_jobs = {
    controller = {
      description = "Jenkins controller deployment"
      script_path = "terraform/swarm/jenkins/controller/pipeline/controller.jenkins"
    }
    agent = {
      description = "Jenkins agent deployment"
      script_path = "terraform/swarm/jenkins/agent/pipeline/agent.jenkins"
    }
    config = {
      description = "Jenkins configuration apply"
      script_path = "terraform/swarm/jenkins/config/pipeline/config.jenkins"
    }
  }

  multi_stage_services = {
    grafana = {
      jobs = {
        app = {
          description = "Grafana application deployment"
          script_path = "terraform/swarm/grafana/app/pipeline/app.jenkins"
        }
        config = {
          description = "Grafana configuration apply"
          script_path = "terraform/swarm/grafana/config/pipeline/config.jenkins"
        }
      }
    }
    nginx_proxy_manager = {
      jobs = {
        app = {
          description = "Nginx Proxy Manager application deployment"
          script_path = "terraform/swarm/nginx_proxy_manager/app/pipeline/app.jenkins"
        }
        config = {
          description = "Nginx Proxy Manager configuration apply"
          script_path = "terraform/swarm/nginx_proxy_manager/config/pipeline/config.jenkins"
        }
      }
    }
  }

  single_stage_jobs = {
    dozzle = {
      description = "Dozzle Swarm deployment"
      script_path = "terraform/swarm/dozzle/app/pipeline/app.jenkins"
    }
    node_exporter = {
      description = "Node Exporter Swarm deployment"
      script_path = "terraform/swarm/node_exporter/app/pipeline/app.jenkins"
    }
    graphite = {
      description = "Graphite Swarm deployment"
      script_path = "terraform/swarm/graphite/app/pipeline/app.jenkins"
    }
    prometheus = {
      description = "Prometheus Swarm deployment"
      script_path = "terraform/swarm/prometheus/app/pipeline/app.jenkins"
    }
  }

  multi_stage_jobs = merge([
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
