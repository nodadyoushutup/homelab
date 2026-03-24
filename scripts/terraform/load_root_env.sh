#!/usr/bin/env bash

if [[ "${PIPELINE_ROOT_ENV_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

_pipeline_root_dir="${ROOT_DIR:-}"
if [[ -z "${_pipeline_root_dir}" ]]; then
  _pipeline_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _pipeline_root_dir="$(cd "${_pipeline_script_dir}/../.." && pwd)"
fi

_pipeline_env_file="${_pipeline_root_dir}/.env"
if [[ -f "${_pipeline_env_file}" ]]; then
  _pipeline_existing_tfvars_dir_set=0
  _pipeline_existing_tfvars_home_dir_set=0
  _pipeline_existing_jenkins_tfvars_dir_set=0
  _pipeline_existing_jenkins_controller_tfvars_dir_set=0
  _pipeline_existing_tfvars_dir_value=""
  _pipeline_existing_tfvars_home_dir_value=""
  _pipeline_existing_jenkins_tfvars_dir_value=""
  _pipeline_existing_jenkins_controller_tfvars_dir_value=""

  if [[ -n "${TFVARS_DIR+x}" ]]; then
    _pipeline_existing_tfvars_dir_set=1
    _pipeline_existing_tfvars_dir_value="${TFVARS_DIR}"
  fi
  if [[ -n "${TFVARS_HOME_DIR+x}" ]]; then
    _pipeline_existing_tfvars_home_dir_set=1
    _pipeline_existing_tfvars_home_dir_value="${TFVARS_HOME_DIR}"
  fi
  if [[ -n "${JENKINS_TFVARS_DIR+x}" ]]; then
    _pipeline_existing_jenkins_tfvars_dir_set=1
    _pipeline_existing_jenkins_tfvars_dir_value="${JENKINS_TFVARS_DIR}"
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

  if [[ "${_pipeline_existing_tfvars_dir_set}" == "1" ]]; then
    export TFVARS_DIR="${_pipeline_existing_tfvars_dir_value}"
  fi
  if [[ "${_pipeline_existing_tfvars_home_dir_set}" == "1" ]]; then
    export TFVARS_HOME_DIR="${_pipeline_existing_tfvars_home_dir_value}"
  fi
  if [[ "${_pipeline_existing_jenkins_tfvars_dir_set}" == "1" ]]; then
    export JENKINS_TFVARS_DIR="${_pipeline_existing_jenkins_tfvars_dir_value}"
  fi
  if [[ "${_pipeline_existing_jenkins_controller_tfvars_dir_set}" == "1" ]]; then
    export JENKINS_CONTROLLER_TFVARS_DIR="${_pipeline_existing_jenkins_controller_tfvars_dir_value}"
  fi
fi

if [[ -z "${TFVARS_HOME_DIR:-}" && -n "${TFVARS_DIR:-}" ]]; then
  export TFVARS_HOME_DIR="${TFVARS_DIR}"
fi

if [[ -z "${JENKINS_TFVARS_DIR:-}" && -n "${TFVARS_DIR:-}" ]]; then
  export JENKINS_TFVARS_DIR="${TFVARS_DIR}/jenkins"
fi

if [[ -z "${JENKINS_CONTROLLER_TFVARS_DIR:-}" && -n "${TFVARS_DIR:-}" ]]; then
  export JENKINS_CONTROLLER_TFVARS_DIR="${TFVARS_DIR}/jenkins-controller"
fi

export PIPELINE_ROOT_ENV_LOADED=1
