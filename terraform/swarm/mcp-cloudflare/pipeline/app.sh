#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="mcp-cloudflare"
STAGE_NAME="MCP Cloudflare app"
# No NFS mounts; skip nfs.tfvars so the stack need not declare `nfs` variable.
SWARM_SKIP_NFS_PROVIDER_TFVARS=1
export SWARM_SKIP_NFS_PROVIDER_TFVARS
ENTRYPOINT_RELATIVE="terraform/swarm/mcp-cloudflare/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/mcp-cloudflare/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")


# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
