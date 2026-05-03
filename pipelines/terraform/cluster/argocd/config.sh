#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="argocd"
STAGE_NAME="Argo CD config"
ENTRYPOINT_RELATIVE="pipelines/terraform/cluster/argocd/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/cluster/argocd/config"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/config}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/argocd/config.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
