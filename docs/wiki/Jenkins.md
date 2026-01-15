# Jenkins Overview

The Jenkins stack provides CI/CD orchestration for the platform. Image build
contexts live under `docker/jenkins/` and deployments are driven by Terraform +
Swarm pipelines.

## Images

- Controller: `docker/jenkins/controller/` (plugins pinned in `plugins.txt`), built/pushed by `.github/workflows/jenkins_controller_build_push.yml`.
- Agent: `docker/jenkins/agent/`, built/pushed by `.github/workflows/jenkins_agent_build_push.yml`.

## Deployment

- Terraform modules: `terraform/module/jenkins/{controller,agent,config}` with stack entrypoints under `terraform/swarm/jenkins/{controller,agent,config}`.
- Pipelines: `terraform/swarm/jenkins/controller/pipeline/controller.{sh,jenkins}`, `terraform/swarm/jenkins/agent/pipeline/agent.{sh,jenkins}`, and `terraform/swarm/jenkins/config/pipeline/config.{sh,jenkins}` run through the shared Swarm pipeline helper.
- Tfvars: `~/.tfvars/jenkins/{controller.tfvars,agent.tfvars,config.tfvars}` plus shared backend `~/.tfvars/minio.backend.hcl` (see [[Secrets]]).
- Purge: `scripts/purge/jenkins.sh` tears down Jenkins Swarm artifacts when needed.

## Operations

- Build/push images locally only if debugging; CI workflows are the source of truth for published tags.
- Run the controller pipeline first, then agent, then config when rolling out changes. Use Jenkins jobs provisioned by `terraform/module/jenkins/config` for CI-triggered runs.
