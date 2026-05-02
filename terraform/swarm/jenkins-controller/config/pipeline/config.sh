#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="jenkins-controller"
STAGE_NAME="Jenkins config"
ENTRYPOINT_RELATIVE="terraform/swarm/jenkins-controller/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-controller/config"

JENKINS_CONTROLLER_TFVARS_DIR="${JENKINS_CONTROLLER_TFVARS_DIR:-${TFVARS_DIR:-/mnt/eapp/config}/jenkins-controller}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${JENKINS_CONTROLLER_TFVARS_DIR}/config.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
