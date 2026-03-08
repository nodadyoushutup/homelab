#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

if [[ $# -gt 0 ]]; then
  echo "[ERR] vault app pipeline uses fixed input paths and does not accept override arguments." >&2
  echo "      expected tfvars:  /mnt/eapp/.tfvars/vault/app.tfvars" >&2
  echo "      expected backend: /mnt/eapp/.tfvars/minio.backend.hcl" >&2
  exit 2
fi

VAULT_BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/vault/bootstrap.sh"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"
VAULT_PUBLISHED_PORT="8200"

detect_swarm_manager_host() {
  local host
  host="${VAULT_SWARM_MANAGER_HOST:-}"
  if [[ -n "${host}" ]]; then
    echo "${host}"
    return 0
  fi

  host="${DOCKER_SWARM_CP:-ssh://swarm-cp-0.internal}"
  host="${host#ssh://}"
  host="${host%%/*}"
  echo "${host}"
}

vault_preflight_port_check() {
  local swarm_manager_host
  swarm_manager_host="$(detect_swarm_manager_host)"

  if [[ -z "${swarm_manager_host}" ]]; then
    echo "[ERR] Unable to determine swarm manager host for Vault port preflight." >&2
    exit 1
  fi

  if ! command -v ssh >/dev/null 2>&1; then
    echo "[ERR] ssh is required for Vault port preflight checks." >&2
    exit 1
  fi

  if ! ssh "${swarm_manager_host}" "true" >/dev/null 2>&1; then
    echo "[ERR] Unable to reach swarm manager host ${swarm_manager_host} over ssh for Vault preflight checks." >&2
    exit 1
  fi

  if ssh "${swarm_manager_host}" "docker service inspect vault >/dev/null 2>&1"; then
    echo "[INFO] Existing Vault service detected on ${swarm_manager_host}; skipping fresh-port check."
    export VAULT_SWARM_MANAGER_HOST="${swarm_manager_host}"
    return 0
  fi

  if ssh "${swarm_manager_host}" "ss -H -ltn 2>/dev/null | awk '{print \$4}' | grep -Eq '(^|:|\\])${VAULT_PUBLISHED_PORT}$'"; then
    echo "[ERR] Port ${VAULT_PUBLISHED_PORT} is already in use on ${swarm_manager_host}." >&2
    echo "      Free the port or remove the conflicting listener before rerunning Vault app pipeline." >&2
    exit 1
  fi

  echo "[INFO] Port preflight passed on ${swarm_manager_host}:${VAULT_PUBLISHED_PORT}."
  export VAULT_SWARM_MANAGER_HOST="${swarm_manager_host}"
}

vault_post_deploy_health_check() {
  local env_file vault_addr code
  local retries=24
  local sleep_seconds=5

  env_file="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}/vault/.env"
  vault_addr="${VAULT_ADDR:-}"

  if [[ -z "${vault_addr}" && -f "${env_file}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
    vault_addr="${VAULT_ADDR:-}"
  fi

  if [[ -z "${vault_addr}" ]]; then
    echo "[WARN] ${env_file} missing or VAULT_ADDR unset; falling back to ${DEFAULT_VAULT_ADDR}" >&2
    vault_addr="${DEFAULT_VAULT_ADDR}"
  fi

  echo "[INFO] Validating Vault health endpoint at ${vault_addr}/v1/sys/health"
  for ((i=1; i<=retries; i++)); do
    code="$(curl -sS -o /dev/null -w "%{http_code}" "${vault_addr}/v1/sys/health" || true)"

    case "${code}" in
      200|429|472|473|501|503)
        echo "[INFO] Vault health check passed with HTTP ${code}."
        return 0
        ;;
    esac

    sleep "${sleep_seconds}"
  done

  echo "[ERR] Vault health check failed at ${vault_addr}/v1/sys/health after $((retries * sleep_seconds))s." >&2
  exit 1
}

SERVICE_NAME="vault"
STAGE_NAME="Vault app"
ENTRYPOINT_RELATIVE="terraform/docker/vault/app/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/docker/vault/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/.tfvars}}"
DEFAULT_TFVARS_FILE="${TFVARS_HOME_DIR}/vault/app.tfvars"
DEFAULT_BACKEND_FILE="${TFVARS_HOME_DIR}/minio.backend.hcl"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=()

vault_preflight_port_check

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"

if [[ ! -x "${VAULT_BOOTSTRAP_SCRIPT}" ]]; then
  echo "[ERR] Missing executable bootstrap script: ${VAULT_BOOTSTRAP_SCRIPT}" >&2
  exit 1
fi

"${VAULT_BOOTSTRAP_SCRIPT}"
vault_post_deploy_health_check
