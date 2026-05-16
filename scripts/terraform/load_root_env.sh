#!/usr/bin/env bash

if [[ "${PIPELINE_ROOT_ENV_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

_pipeline_root_dir="${ROOT_DIR:-}"
if [[ -z "${_pipeline_root_dir}" ]]; then
  _pipeline_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _pipeline_root_dir="$(cd "${_pipeline_script_dir}/../.." && pwd)"
fi

_pipeline_config_env="${_pipeline_root_dir}/.config/.env"
_pipeline_legacy_secrets_env="${_pipeline_root_dir}/.secrets/.env"
_pipeline_legacy_env="${_pipeline_root_dir}/.env"
_pipeline_env_file=""
if [[ -f "${_pipeline_config_env}" ]]; then
  _pipeline_env_file="${_pipeline_config_env}"
elif [[ -f "${_pipeline_legacy_secrets_env}" ]]; then
  echo "[homelab] Prefer .config/.env over .secrets/.env; copy variables into .config/.env and remove .secrets/.env (see .config/.env.example)." >&2
  _pipeline_env_file="${_pipeline_legacy_secrets_env}"
elif [[ -f "${_pipeline_legacy_env}" ]]; then
  echo "[homelab] Prefer .config/.env over repo-root .env; copy variables into .config/.env and remove .env (see .config/.env.example)." >&2
  _pipeline_env_file="${_pipeline_legacy_env}"
fi
if [[ -n "${_pipeline_env_file}" && -f "${_pipeline_env_file}" ]]; then
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

  _pipeline_restore_allexport=0
  _pipeline_restore_nounset=0

  if [[ "$-" == *a* ]]; then
    _pipeline_restore_allexport=1
  fi
  if [[ "$-" == *u* ]]; then
    _pipeline_restore_nounset=1
    set +u
  fi

  set -a
  # shellcheck disable=SC1090
  source "${_pipeline_env_file}"

  if [[ "${_pipeline_restore_allexport}" != "1" ]]; then
    set +a
  fi
  if [[ "${_pipeline_restore_nounset}" == "1" ]]; then
    set -u
  fi

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
fi

# Default site layout: Terraform/Kubernetes tfvars + minio.backend.hcl live under <repo>/.config/
# (migrated from legacy /mnt/eapp/config). Override with CONFIG_DIR in .config/.env when needed.
if [[ -z "${CONFIG_DIR:-}" ]]; then
  export CONFIG_DIR="${_pipeline_root_dir}/.config"
fi

if [[ -z "${TFVARS_HOME_DIR:-}" && -n "${CONFIG_DIR:-}" ]]; then
  export TFVARS_HOME_DIR="${CONFIG_DIR}"
fi

if [[ -z "${JENKINS_CONTROLLER_TFVARS_DIR:-}" && -n "${CONFIG_DIR:-}" ]]; then
  export JENKINS_CONTROLLER_TFVARS_DIR="${CONFIG_DIR}/terraform/swarm/jenkins-controller"
fi

export PIPELINE_ROOT_ENV_LOADED=1
