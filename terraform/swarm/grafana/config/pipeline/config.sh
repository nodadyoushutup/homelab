#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/pipeline/script"

SERVICE_NAME="grafana"
STAGE_NAME="Grafana config"
ENTRYPOINT_RELATIVE="terraform/swarm/grafana/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/grafana/config"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${HOME}/.tfvars}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/grafana/config.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
