#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="prometheus"
STAGE_NAME="Prometheus database (VictoriaMetrics)"
ENTRYPOINT_RELATIVE="terraform/swarm/prometheus/database/pipeline/database.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/prometheus/database"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"

if [[ -z "${DEFAULT_TFVARS_FILE:-}" ]]; then
  if [[ -f "${TFVARS_HOME_DIR}/prometheus/database.tfvars" ]]; then
    DEFAULT_TFVARS_FILE="${TFVARS_HOME_DIR}/prometheus/database.tfvars"
  else
    DEFAULT_TFVARS_FILE="${TFVARS_HOME_DIR}/victoriametrics/app.tfvars"
  fi
fi

DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
