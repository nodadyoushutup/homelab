#!/usr/bin/env bash

if [[ "${PIPELINE_ROOT_ENV_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

_pipeline_root_dir="${ROOT_DIR:-}"
if [[ -z "${_pipeline_root_dir}" ]]; then
  _pipeline_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _pipeline_root_dir="$(cd "${_pipeline_script_dir}/../.." && pwd)"
fi

export ROOT_DIR="${_pipeline_root_dir}"

_pipeline_legacy_secrets_env="${_pipeline_root_dir}/.secrets/.env"
_pipeline_legacy_env="${_pipeline_root_dir}/.env"

if [[ -f "${_pipeline_legacy_secrets_env}" ]]; then
  echo "[homelab] Prefer .config/docker/*.env over .secrets/.env; migrate and remove .secrets/.env (see .config/docker/README.md)." >&2
elif [[ -f "${_pipeline_legacy_env}" ]]; then
  echo "[homelab] Prefer .config/docker/*.env over repo-root .env; migrate and remove .env (see .config/docker/README.md)." >&2
fi

_pipeline_existing_config_dir_set=0
_pipeline_existing_tfvars_home_dir_set=0
_pipeline_existing_jenkins_agent_tfvars_dir_set=0
_pipeline_existing_jenkins_controller_tfvars_dir_set=0
_pipeline_existing_config_dir_value=""
_pipeline_existing_tfvars_home_dir_value=""
_pipeline_existing_jenkins_agent_tfvars_dir_value=""
_pipeline_existing_jenkins_controller_tfvars_dir_value=""

if [[ -n "${CONFIG_DIR+x}" ]]; then
  _pipeline_existing_config_dir_set=1
  _pipeline_existing_config_dir_value="${CONFIG_DIR}"
fi
if [[ -n "${TFVARS_HOME_DIR+x}" ]]; then
  _pipeline_existing_tfvars_home_dir_set=1
  _pipeline_existing_tfvars_home_dir_value="${TFVARS_HOME_DIR}"
fi
if [[ -n "${JENKINS_AGENT_TFVARS_DIR+x}" ]]; then
  _pipeline_existing_jenkins_agent_tfvars_dir_set=1
  _pipeline_existing_jenkins_agent_tfvars_dir_value="${JENKINS_AGENT_TFVARS_DIR}"
fi
if [[ -n "${JENKINS_CONTROLLER_TFVARS_DIR+x}" ]]; then
  _pipeline_existing_jenkins_controller_tfvars_dir_set=1
  _pipeline_existing_jenkins_controller_tfvars_dir_value="${JENKINS_CONTROLLER_TFVARS_DIR}"
fi

_pipeline_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=load_docker_env.sh
source "${_pipeline_script_dir}/load_docker_env.sh" || return 1 2>/dev/null || exit 1

if [[ "${_pipeline_existing_config_dir_set}" == "1" ]]; then
  export CONFIG_DIR="${_pipeline_existing_config_dir_value}"
fi
if [[ "${_pipeline_existing_tfvars_home_dir_set}" == "1" ]]; then
  export TFVARS_HOME_DIR="${_pipeline_existing_tfvars_home_dir_value}"
fi
if [[ "${_pipeline_existing_jenkins_agent_tfvars_dir_set}" == "1" ]]; then
  export JENKINS_AGENT_TFVARS_DIR="${_pipeline_existing_jenkins_agent_tfvars_dir_value}"
fi
if [[ "${_pipeline_existing_jenkins_controller_tfvars_dir_set}" == "1" ]]; then
  export JENKINS_CONTROLLER_TFVARS_DIR="${_pipeline_existing_jenkins_controller_tfvars_dir_value}"
fi

# Default site layout: Terraform/Kubernetes tfvars + terraform/minio.backend.hcl live under <repo>/.config/terraform/.
# Override with CONFIG_DIR in site.env when needed.
if [[ -z "${CONFIG_DIR:-}" ]]; then
  export CONFIG_DIR="${_pipeline_root_dir}/.config"
fi

if [[ -z "${TFVARS_HOME_DIR:-}" && -n "${CONFIG_DIR:-}" ]]; then
  export TFVARS_HOME_DIR="${CONFIG_DIR}"
fi

if [[ -z "${JENKINS_CONTROLLER_TFVARS_DIR:-}" && -n "${CONFIG_DIR:-}" ]]; then
  export JENKINS_CONTROLLER_TFVARS_DIR="${CONFIG_DIR}/terraform/components/swarm/jenkins-controller"
fi

export PIPELINE_ROOT_ENV_LOADED=1
