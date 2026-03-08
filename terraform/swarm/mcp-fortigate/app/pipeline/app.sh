#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/pipeline"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="mcp-fortigate"
STAGE_NAME="MCP FortiGate app"
ENTRYPOINT_RELATIVE="terraform/swarm/mcp-fortigate/app/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/mcp-fortigate/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/mcp-fortigate/app.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

build_fortigate_image() {
  local image_name="homelab/mcp-fortigate:2026.03.08.6"
  local image_context_dir="${ROOT_DIR}/docker/mcp-fortigate"
  local docker_host="${DOCKER_SWARM_CP:-ssh://swarm-cp-0.local}"

  if ! command -v docker >/dev/null 2>&1; then
    echo "[ERR] docker CLI is required to build ${image_name}" >&2
    exit 1
  fi

  if [[ ! -d "${image_context_dir}" ]]; then
    echo "[ERR] Docker image context not found: ${image_context_dir}" >&2
    exit 1
  fi

  if [[ "${MCP_FORTIGATE_REBUILD_IMAGE:-0}" != "1" ]] && DOCKER_HOST="${docker_host}" docker image inspect "${image_name}" >/dev/null 2>&1; then
    echo "[INFO] Reusing existing image ${image_name} on ${docker_host}"
    return 0
  fi

  echo "[INFO] Building image ${image_name} on ${docker_host}"
  DOCKER_HOST="${docker_host}" docker build --pull -t "${image_name}" "${image_context_dir}"
}

pipeline_pre_terraform() {
  build_fortigate_image
}

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
