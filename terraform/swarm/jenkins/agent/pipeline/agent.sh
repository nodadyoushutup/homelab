#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/pipeline"

SERVICE_NAME="jenkins"
STAGE_NAME="Jenkins agents"
ENTRYPOINT_RELATIVE="terraform/swarm/jenkins/agent/pipeline/agent.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins/agent"

JENKINS_TFVARS_DIR="${JENKINS_TFVARS_DIR:-${HOME}/.tfvars/jenkins}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${JENKINS_TFVARS_DIR}/agent.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

CONTROLLER_TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins/controller"

pipeline_pre_terraform() {
  if [[ ! -d "${CONTROLLER_TERRAFORM_DIR}" ]]; then
    echo "[ERR] Missing controller Terraform directory at ${CONTROLLER_TERRAFORM_DIR}. Run the controller pipeline first." >&2
    exit 1
  fi

  echo "[INFO] Collecting Jenkins controller outputs"
  if ! terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" init -backend-config="${BACKEND_CONFIG_PATH}" > /dev/null; then
    echo "[ERR] Unable to initialize controller backend; ensure controller pipeline has been run." >&2
    exit 1
  fi

  local controller_service_id controller_image
  controller_service_id="$(terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" output -raw controller_service_id 2>/dev/null || true)"
  controller_image="$(terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" output -raw controller_image 2>/dev/null || true)"

  if [[ -z "${controller_service_id}" || -z "${controller_image}" ]]; then
    echo "[ERR] Jenkins controller outputs unavailable. Run the controller pipeline before deploying agents." >&2
    exit 1
  fi

  export TF_VAR_controller_service_id="${controller_service_id}"
  export TF_VAR_controller_image="${controller_image}"
}

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
