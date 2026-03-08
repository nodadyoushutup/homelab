#!/usr/bin/env bash
# Stage 2 (docs/planning/nginx-proxy-manager-plan.md) – config stage hooks the NPM API
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="nginx_proxy_manager"
STAGE_NAME="Nginx Proxy Manager config"
ENTRYPOINT_RELATIVE="terraform/swarm/nginx_proxy_manager/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/config"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/nginx-proxy-manager/config.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=("-parallelism=1")

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
