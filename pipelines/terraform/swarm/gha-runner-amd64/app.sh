#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="gha-runner-amd64"
STAGE_NAME="GitHub Actions AMD64 runner app"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/gha-runner-amd64/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/gha-runner-amd64/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PIPELINE_ARGS=("$@")

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${PIPELINE_SCRIPT_ROOT}/resolve_config_by_id.sh"
SWARM_DOCKER_PROVIDER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/providers/runner_agent_amd64")}"
export SWARM_DOCKER_PROVIDER_TFVARS

if [[ ! -f "${SWARM_DOCKER_PROVIDER_TFVARS}" ]]; then
  echo "[ERR] Missing AMD64 runner/agent Docker provider tfvars: ${SWARM_DOCKER_PROVIDER_TFVARS}" >&2
  echo "[ERR] Create it from homelab terraform/providers/runner_agent_amd64.tfvars.example." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
