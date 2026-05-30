#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  echo "[ERR] seal.sh does not accept positional arguments." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_ENV_LOADER="${ROOT_DIR}/scripts/terraform/load_root_env.sh"
if [[ -f "${ROOT_ENV_LOADER}" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT_ENV_LOADER}"
fi

VAULT_TFVARS_HOME="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
VAULT_TFVARS_DIR="${VAULT_TFVARS_DIR:-${VAULT_TFVARS_HOME}/terraform/components/swarm/vault}"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"
WAIT_SECONDS="120"

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

fail() {
  echo "[ERR] $*" >&2
  exit 1
}

resolve_runtime_env() {
  if [[ -f "${VAULT_ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${VAULT_ENV_FILE}"
    set +a
  fi

  if [[ -z "${VAULT_ADDR:-}" ]]; then
    log_warn "${VAULT_ENV_FILE} missing or VAULT_ADDR unset; falling back to ${DEFAULT_VAULT_ADDR}"
    VAULT_ADDR="${DEFAULT_VAULT_ADDR}"
  fi
}

wait_for_vault_api() {
  local deadline=$((SECONDS + WAIT_SECONDS))

  while (( SECONDS < deadline )); do
    local code
    code="$(curl -sS -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)"

    case "${code}" in
      200|429|472|473|501|503)
        return 0
        ;;
    esac

    sleep 2
  done

  return 1
}

vault_is_sealed() {
  curl -fsS "${VAULT_ADDR}/v1/sys/seal-status" | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("sealed", True)).lower())'
}

validate_token() {
  curl -fsS \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/auth/token/lookup-self" > /dev/null
}

main() {
  local sealed

  resolve_runtime_env
  log_info "Using VAULT_ADDR=${VAULT_ADDR}"

  if ! wait_for_vault_api; then
    fail "Vault API did not become reachable within ${WAIT_SECONDS}s at ${VAULT_ADDR}"
  fi

  if [[ -z "${VAULT_TOKEN:-}" ]]; then
    fail "VAULT_TOKEN is not set. Ensure ${VAULT_ENV_FILE} exists or export VAULT_TOKEN before sealing."
  fi

  sealed="$(vault_is_sealed)"
  if [[ "${sealed}" == "true" ]]; then
    log_info "Vault is already sealed."
    return 0
  fi

  if ! validate_token; then
    fail "Unable to validate VAULT_TOKEN against ${VAULT_ADDR}."
  fi

  curl -fsS -X PUT -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/sys/seal" > /dev/null

  sealed="$(vault_is_sealed)"
  if [[ "${sealed}" != "true" ]]; then
    fail "Seal request completed but Vault did not report sealed state."
  fi

  log_info "Vault sealed successfully."
}

main
