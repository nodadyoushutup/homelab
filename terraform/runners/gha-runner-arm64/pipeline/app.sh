#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="gha-runner-arm64"
STAGE_NAME="GitHub Actions ARM64 runner app"
ENTRYPOINT_RELATIVE="terraform/runners/gha-runner-arm64/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/runners/gha-runner-arm64/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PIPELINE_ARGS=("$@")

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${PIPELINE_SCRIPT_ROOT}/resolve_config_by_id.sh"
SWARM_DOCKER_PROVIDER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/components/arm64")}"
export SWARM_DOCKER_PROVIDER_TFVARS

if [[ ! -f "${SWARM_DOCKER_PROVIDER_TFVARS}" ]]; then
  echo "[ERR] Missing ARM64 pool Docker provider tfvars: ${SWARM_DOCKER_PROVIDER_TFVARS}" >&2
  echo "[ERR] Create it from .config/terraform/components/arm64.tfvars.example." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
