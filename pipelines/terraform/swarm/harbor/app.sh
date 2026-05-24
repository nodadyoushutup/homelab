#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="harbor"
STAGE_NAME="Harbor app"
# No NFS mounts; skip nfs.tfvars so the stack need not declare `nfs` variable.
SWARM_SKIP_NFS_PROVIDER_TFVARS=1
export SWARM_SKIP_NFS_PROVIDER_TFVARS
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/harbor/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/harbor/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

HARBOR_PREPARE_SCRIPT="${ROOT_DIR}/scripts/harbor/prepare_from_tfvars.py"

pipeline_pre_terraform() {
  [[ -f "${HARBOR_PREPARE_SCRIPT}" ]] || {
    echo "[ERR] Missing ${HARBOR_PREPARE_SCRIPT}" >&2
    exit 1
  }

  local py=(python3)
  if command -v uv >/dev/null 2>&1; then
    py=(uv run --with "python-hcl2>=4,<5" --with pyyaml python3)
  fi

  echo "[STEP] harbor-prepare from ${TFVARS_PATH}"
  if ! "${py[@]}" "${HARBOR_PREPARE_SCRIPT}" --tfvars "${TFVARS_PATH}"; then
    echo "[ERR] harbor-prepare failed (see messages above)." >&2
    exit 1
  fi
}

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_docker_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
