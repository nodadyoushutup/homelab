#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="jenkins-controller"
STAGE_NAME="Jenkins controller app"
ENTRYPOINT_RELATIVE="terraform/swarm/jenkins-controller/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/jenkins-controller/app"

JENKINS_CONTROLLER_TFVARS_DIR="${JENKINS_CONTROLLER_TFVARS_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}/terraform/swarm/jenkins-controller}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")


# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
