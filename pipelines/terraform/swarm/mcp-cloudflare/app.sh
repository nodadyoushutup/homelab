#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="mcp-cloudflare"
STAGE_NAME="MCP Cloudflare app"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/mcp-cloudflare/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/mcp-cloudflare/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/mcp-cloudflare/app.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")


# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
