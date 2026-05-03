#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="jenkins-agent-arm64"
STAGE_NAME="Jenkins agent arm64 app"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/jenkins-agent-arm64/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-agent-arm64/app"

JENKINS_AGENT_ARM64_TFVARS_DIR="${JENKINS_AGENT_ARM64_TFVARS_DIR:-${TFVARS_DIR:-/mnt/eapp/config}/jenkins-agent-arm64}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${JENKINS_AGENT_ARM64_TFVARS_DIR}/app.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

CONTROLLER_TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-controller/app"
EXPECTED_IMAGE_ARCH="arm64"

resolve_agent_image_from_tfvars() {
  local agent_image
  agent_image="$(sed -n 's/^[[:space:]]*agent_image[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${TFVARS_PATH}" | head -n 1)"

  if [[ -z "${agent_image}" ]]; then
    echo "[ERR] Unable to resolve agent_image from ${TFVARS_PATH}." >&2
    exit 1
  fi

  printf '%s\n' "${agent_image}"
}

assert_agent_image_architecture() {
  local agent_image manifest_output
  agent_image="$(resolve_agent_image_from_tfvars)"

  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERR] docker is required to validate Jenkins agent image manifests." >&2
    exit 1
  fi

  echo "[INFO] Validating Jenkins agent image supports ${EXPECTED_IMAGE_ARCH}: ${agent_image}"
  if ! manifest_output="$(docker manifest inspect "${agent_image}" 2>/dev/null)"; then
    echo "[ERR] Unable to inspect manifest for ${agent_image}." >&2
    exit 1
  fi

  if ! printf '%s\n' "${manifest_output}" | grep -q "\"architecture\"[[:space:]]*:[[:space:]]*\"${EXPECTED_IMAGE_ARCH}\""; then
    echo "[ERR] Jenkins agent image ${agent_image} does not advertise ${EXPECTED_IMAGE_ARCH} support." >&2
    exit 1
  fi
}

pipeline_pre_terraform() {
  if [[ ! -d "${CONTROLLER_TERRAFORM_DIR}" ]]; then
    echo "[ERR] Missing controller Terraform directory at ${CONTROLLER_TERRAFORM_DIR}. Run the controller pipeline first." >&2
    exit 1
  fi

  echo "[INFO] Checking Jenkins controller outputs"
  if ! terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" init -backend-config="${BACKEND_CONFIG_PATH}" > /dev/null; then
    echo "[ERR] Unable to initialize controller backend; ensure controller pipeline has been run." >&2
    exit 1
  fi

  local controller_service_id
  controller_service_id="$(terraform -chdir="${CONTROLLER_TERRAFORM_DIR}" output -raw controller_service_id 2>/dev/null || true)"

  if [[ -z "${controller_service_id}" ]]; then
    echo "[ERR] Jenkins controller outputs unavailable. Run the controller pipeline before deploying agents." >&2
    exit 1
  fi

  assert_agent_image_architecture
}

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
