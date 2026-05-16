#!/usr/bin/env bash
# Nginx Proxy Manager config stage hooks the NPM API
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="nginx_proxy_manager"
STAGE_NAME="Nginx Proxy Manager config"
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/nginx_proxy_manager/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/config"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=("-parallelism=1")

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
