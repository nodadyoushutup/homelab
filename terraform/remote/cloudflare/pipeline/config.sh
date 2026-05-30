#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="cloudflare"
STAGE_NAME="Cloudflare config"
ENTRYPOINT_RELATIVE="terraform/remote/cloudflare/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/remote/cloudflare/config"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

source "${PIPELINE_SCRIPT_ROOT}/remote_pipeline.sh"
