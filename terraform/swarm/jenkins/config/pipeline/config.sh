#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/pipeline/script"

SERVICE_NAME="jenkins"
STAGE_NAME="Jenkins config"
ENTRYPOINT_RELATIVE="terraform/swarm/jenkins/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins/config"

JENKINS_TFVARS_DIR="${JENKINS_TFVARS_DIR:-${HOME}/.tfvars/jenkins}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${JENKINS_TFVARS_DIR}/config.tfvars}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
