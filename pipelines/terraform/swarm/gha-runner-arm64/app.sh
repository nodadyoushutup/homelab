#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="gha-runner-arm64"
STAGE_NAME="GitHub Actions ARM64 runner app"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/gha-runner-arm64/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/gha-runner-arm64/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

# Pool-host Docker provider: docker_arm64_pool.tfvars sets `swarm_docker_provider_config` last
# (after shared docker_arm64 / dns / nfs / stack tfvars) so Terraform targets the pool host.
PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

SWARM_DOCKER_ARM64_POOL_TFVARS="${SWARM_DOCKER_ARM64_POOL_TFVARS:-${TFVARS_HOME_DIR}/terraform/providers/docker_arm64_pool.tfvars}"
export SWARM_DOCKER_ARM64_POOL_TFVARS

if [[ -f "${SWARM_DOCKER_ARM64_POOL_TFVARS}" ]]; then
  PLAN_ARGS_EXTRA+=(-var-file "${SWARM_DOCKER_ARM64_POOL_TFVARS}")
  APPLY_ARGS_EXTRA+=(-var-file "${SWARM_DOCKER_ARM64_POOL_TFVARS}")
fi

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
