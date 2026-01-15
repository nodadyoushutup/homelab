#!/usr/bin/env bash
# Stage 2 (docs/planning/nginx-proxy-manager-plan.md) – app deployment entrypoint
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/pipeline/script"

SERVICE_NAME="nginx_proxy_manager"
STAGE_NAME="Nginx Proxy Manager app"
ENTRYPOINT_RELATIVE="terraform/swarm/nginx_proxy_manager/app/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/app"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${HOME}/.tfvars}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/nginx-proxy-manager/app.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
