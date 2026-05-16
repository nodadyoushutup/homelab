#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="prometheus"
STAGE_NAME="Prometheus database (VictoriaMetrics)"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/prometheus/database.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/prometheus/database"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

if [[ -z "${DEFAULT_TFVARS_FILE:-}" ]]; then
  _db="${TFVARS_HOME_DIR}/terraform/swarm/prometheus/database.tfvars"
  _vm_new="${TFVARS_HOME_DIR}/terraform/swarm/victoriametrics/app.tfvars"
  _vm_old="${TFVARS_HOME_DIR}/victoriametrics/app.tfvars"
  if [[ -f "${_db}" ]]; then
    DEFAULT_TFVARS_FILE="${_db}"
  elif [[ -f "${_vm_new}" ]]; then
    DEFAULT_TFVARS_FILE="${_vm_new}"
  elif [[ -f "${_vm_old}" ]]; then
    DEFAULT_TFVARS_FILE="${_vm_old}"
  else
    DEFAULT_TFVARS_FILE="${_db}"
  fi
fi

DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")


# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
