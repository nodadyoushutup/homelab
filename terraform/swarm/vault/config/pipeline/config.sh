#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

if [[ $# -gt 0 ]]; then
  echo "[ERR] vault config pipeline uses fixed input paths and does not accept override arguments." >&2
  echo "      expected tfvars:  /mnt/eapp/.tfvars/vault/config.tfvars" >&2
  echo "      expected backend: /mnt/eapp/.tfvars/minio.backend.hcl" >&2
  exit 2
fi

VAULT_UNSEAL_SCRIPT="${ROOT_DIR}/scripts/vault/unseal.sh"
VAULT_TFVARS_HOME="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
VAULT_TFVARS_DIR="${VAULT_TFVARS_HOME}/vault"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
VAULT_INIT_FILE="${VAULT_TFVARS_DIR}/init.json"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"

SERVICE_NAME="vault"
STAGE_NAME="Vault config"
ENTRYPOINT_RELATIVE="terraform/swarm/vault/config/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/vault/config"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${TFVARS_HOME_DIR}/vault/config.tfvars"
DEFAULT_BACKEND_FILE="${TFVARS_HOME_DIR}/minio.backend.hcl"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=()

resolve_vault_env() {
  if [[ -f "${VAULT_ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${VAULT_ENV_FILE}"
    set +a
  fi

  if [[ -z "${VAULT_ADDR:-}" ]]; then
    echo "[WARN] ${VAULT_ENV_FILE} missing or VAULT_ADDR unset; falling back to ${DEFAULT_VAULT_ADDR}" >&2
    export VAULT_ADDR="${DEFAULT_VAULT_ADDR}"
  fi

  if [[ -z "${VAULT_TOKEN:-}" ]]; then
    echo "[ERR] VAULT_TOKEN is not set. Ensure ${VAULT_ENV_FILE} exists with bootstrap values." >&2
    exit 1
  fi
}

assert_vault_reachable() {
  local code

  code="$(curl -sS -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)"
  case "${code}" in
    200|429|472|473|501|503)
      return 0
      ;;
  esac

  echo "[ERR] Vault is not reachable at ${VAULT_ADDR} (health status ${code:-n/a})." >&2
  exit 1
}

assert_unsealed() {
  local sealed

  sealed="$(curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("sealed", True)).lower())')"
  if [[ "${sealed}" == "false" ]]; then
    return 0
  fi

  echo "[ERR] Vault remains sealed after auto-unseal attempt. Run scripts/vault/unseal.sh manually and retry." >&2
  exit 1
}

pipeline_pre_terraform() {
  [[ -f "${VAULT_INIT_FILE}" ]] || {
    echo "[ERR] Missing ${VAULT_INIT_FILE}. Run terraform/swarm/vault/app/pipeline/app.sh first to bootstrap Vault." >&2
    exit 1
  }

  [[ -x "${VAULT_UNSEAL_SCRIPT}" ]] || {
    echo "[ERR] Missing executable unseal script: ${VAULT_UNSEAL_SCRIPT}" >&2
    exit 1
  }

  resolve_vault_env
  assert_vault_reachable

  if ! "${VAULT_UNSEAL_SCRIPT}"; then
    echo "[ERR] Auto-unseal failed in config pipeline. Run scripts/vault/unseal.sh manually and retry." >&2
    exit 1
  fi

  assert_unsealed
}

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
