#!/usr/bin/env bash
# Bespoke Vault app Swarm deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Single slice tfvars carries provider + DNS + stack settings (no shared swarm/dns var-files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/vault/app"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${VAULT_APP_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${VAULT_APP_BACKEND:-${DEFAULT_BACKEND}}"

VAULT_BOOTSTRAP_SCRIPT="${ROOT_DIR}/scripts/vault/bootstrap.sh"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"
VAULT_PUBLISHED_PORT="8200"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/vault/pipeline/app.sh [options] [slice_tfvars] [backend_config]

Deploy Vault app on Docker Swarm (terraform init, plan, apply), then bootstrap.

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: VAULT_APP_TFVARS, VAULT_APP_BACKEND, CONFIG_DIR (default: <repo>/.config)
USAGE
}

require_file() {
  local label="$1"
  local path="$2"
  if [[ -z "${path}" || ! -f "${path}" ]]; then
    echo "[ERR] Missing ${label}: ${path}" >&2
    exit 1
  fi
}

require_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    echo "[ERR] terraform not found on PATH" >&2
    exit 1
  fi
}

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

  env_file="${CONFIG_DIR}/terraform/components/swarm/vault/.env"
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
  for ((i = 1; i <= retries; i++)); do
    code="$(curl -sS -o /dev/null -w "%{http_code}" "${vault_addr}/v1/sys/health" || true)"

    case "${code}" in
      200 | 429 | 472 | 473 | 501 | 503)
        echo "[INFO] Vault health check passed with HTTP ${code}."
        return 0
        ;;
    esac

    sleep "${sleep_seconds}"
  done

  echo "[ERR] Vault health check failed at ${vault_addr}/v1/sys/health after $((retries * sleep_seconds))s." >&2
  exit 1
}

ARGS=("$@")
while [[ ${#ARGS[@]} -gt 0 ]]; do
  case "${ARGS[0]}" in
    --tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --tfvars requires a path" >&2
        exit 2
      }
      SLICE_TFVARS="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --backend)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --backend requires a path" >&2
        exit 2
      }
      BACKEND_CONFIG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      if [[ "${ARGS[0]}" == --* ]]; then
        echo "[ERR] Unknown option: ${ARGS[0]}" >&2
        usage >&2
        exit 2
      fi
      if [[ -z "${POSITIONAL_SLICE_TFVARS:-}" ]]; then
        POSITIONAL_SLICE_TFVARS="${ARGS[0]}"
      elif [[ -z "${POSITIONAL_BACKEND:-}" ]]; then
        POSITIONAL_BACKEND="${ARGS[0]}"
      else
        echo "[ERR] Unexpected argument: ${ARGS[0]}" >&2
        usage >&2
        exit 2
      fi
      ARGS=("${ARGS[@]:1}")
      ;;
  esac
done

if [[ -n "${POSITIONAL_SLICE_TFVARS:-}" ]]; then
  SLICE_TFVARS="${POSITIONAL_SLICE_TFVARS}"
fi
if [[ -n "${POSITIONAL_BACKEND:-}" ]]; then
  BACKEND_CONFIG="${POSITIONAL_BACKEND}"
fi

if [[ -n "${TFVARS_FILE:-}" ]]; then
  SLICE_TFVARS="${TFVARS_FILE}"
fi
if [[ -n "${BACKEND_FILE:-}" ]]; then
  BACKEND_CONFIG="${BACKEND_FILE}"
fi

require_terraform
require_file "slice tfvars" "${SLICE_TFVARS}"
require_file "backend config" "${BACKEND_CONFIG}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

vault_preflight_port_check

cd "${TERRAFORM_DIR}"

run_terraform_init() {
  local init_log
  init_log="$(mktemp -t vault-app-terraform-init-XXXXXX)"

  if terraform init -backend-config="${BACKEND_CONFIG}" "$@" \
    > >(tee "${init_log}") \
    2> >(tee -a "${init_log}" >&2); then
    rm -f "${init_log}"
    return 0
  fi

  if grep -q "Backend configuration changed" "${init_log}"; then
    if [[ -f ".terraform/terraform.tfstate" ]]; then
      echo "[WARN] Backend change detected; attempting state migration"
      if terraform init -force-copy -migrate-state -backend-config="${BACKEND_CONFIG}" "$@"; then
        rm -f "${init_log}"
        return 0
      fi
    fi
    echo "[WARN] Backend change detected; re-running terraform init -reconfigure"
    if terraform init -reconfigure -backend-config="${BACKEND_CONFIG}" "$@"; then
      rm -f "${init_log}"
      return 0
    fi
  fi

  rm -f "${init_log}"
  return 1
}

echo "[STEP] terraform init (Vault app)"
if ! run_terraform_init; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${SLICE_TFVARS}"
)

echo "[STEP] terraform plan (Vault app)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Vault app)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

if [[ ! -x "${VAULT_BOOTSTRAP_SCRIPT}" ]]; then
  echo "[ERR] Missing executable bootstrap script: ${VAULT_BOOTSTRAP_SCRIPT}" >&2
  exit 1
fi

"${VAULT_BOOTSTRAP_SCRIPT}"
vault_post_deploy_health_check

echo "[DONE] Vault app apply complete."
