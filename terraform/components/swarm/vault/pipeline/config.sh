#!/usr/bin/env bash
# Bespoke Vault config deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Slice tfvars plus the Vault provider credentials (config-id
# terraform/providers/vault) and the merged secrets, all as extra -var-files.
# The .env/VAULT_ADDR handling below is operational only (health check + unseal);
# the hashicorp/vault provider now authenticates from var.vault (VAULT_TFVARS).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/swarm/vault/config"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR}}"

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${ROOT_DIR}/scripts/terraform/resolve_config_by_id.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/scripts/terraform/terraform_backend_init.sh"
# shellcheck source=../../../scripts/terraform/vault_tfvars_env.sh
source "${ROOT_DIR}/scripts/terraform/vault_tfvars_env.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${CONFIG_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${CONFIG_DIR}" "terraform/minio.backend")"

SLICE_TFVARS="${VAULT_CONFIG_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG="${VAULT_CONFIG_BACKEND:-${DEFAULT_BACKEND}}"

VAULT_UNSEAL_SCRIPT="${ROOT_DIR}/scripts/vault/unseal.sh"
VAULT_TFVARS_DIR="${TFVARS_HOME_DIR}/terraform/components/swarm/vault"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
VAULT_INIT_FILE="${VAULT_TFVARS_DIR}/init.json"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"

usage() {
  cat <<USAGE
Usage: terraform/components/swarm/vault/pipeline/config.sh [options] [slice_tfvars] [backend_config]

Apply Vault config (secrets) after unseal; merges secret payloads into an extra tfvars file.

Options:
  --tfvars <path>           Slice tfvars (default: ${DEFAULT_SLICE_TFVARS})
  --backend <path>          S3 backend config (default: ${DEFAULT_BACKEND})
  -h, --help                Show this help

Environment overrides: VAULT_CONFIG_TFVARS, VAULT_CONFIG_BACKEND, CONFIG_DIR (default: <repo>/.config)
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

vault_health_code() {
  local vault_addr="$1"
  curl -m 3 --connect-timeout 2 -sS -o /dev/null -w "%{http_code}" "${vault_addr}/v1/sys/health" || true
}

resolve_reachable_vault_addr() {
  local manager_host code candidate existing
  local deadline=$((SECONDS + 120))
  local -a candidates=()

  add_candidate() {
    local value="$1"
    [[ -n "${value}" ]] || return 0
    for existing in "${candidates[@]}"; do
      [[ "${existing}" == "${value}" ]] && return 0
    done
    candidates+=("${value}")
  }

  add_candidate "${VAULT_ADDR:-}"
  add_candidate "${DEFAULT_VAULT_ADDR}"

  manager_host="$(detect_swarm_manager_host)"
  if [[ -n "${manager_host}" ]]; then
    add_candidate "http://${manager_host}:8200"
  fi
  add_candidate "http://127.0.0.1:8200"
  add_candidate "http://localhost:8200"

  while ((SECONDS < deadline)); do
    for candidate in "${candidates[@]}"; do
      code="$(vault_health_code "${candidate}")"
      case "${code}" in
        200 | 429 | 472 | 473 | 501 | 503)
          echo "${candidate}"
          return 0
          ;;
      esac
    done
    sleep 2
  done

  echo "[ERR] Vault is not reachable via any candidate address (${candidates[*]})." >&2
  return 1
}

assert_vault_reachable() {
  local code

  code="$(curl -sS -o /dev/null -w "%{http_code}" "${VAULT_ADDR}/v1/sys/health" || true)"
  case "${code}" in
    200 | 429 | 472 | 473 | 501 | 503)
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
require_file "vault credentials tfvars" "${VAULT_TFVARS}"

echo "Terraform dir:     ${TERRAFORM_DIR}"
echo "Slice tfvars:      ${SLICE_TFVARS}"
echo "Vault creds:       ${VAULT_TFVARS}"
echo "Backend config:    ${BACKEND_CONFIG}"

[[ -f "${VAULT_INIT_FILE}" ]] || {
  echo "[ERR] Missing ${VAULT_INIT_FILE}. Run terraform/components/swarm/vault/pipeline/app.sh first to bootstrap Vault." >&2
  exit 1
}

[[ -x "${VAULT_UNSEAL_SCRIPT}" ]] || {
  echo "[ERR] Missing executable unseal script: ${VAULT_UNSEAL_SCRIPT}" >&2
  exit 1
}

resolve_vault_env
VAULT_ADDR="$(resolve_reachable_vault_addr)"
export VAULT_ADDR
assert_vault_reachable

if ! "${VAULT_UNSEAL_SCRIPT}"; then
  echo "[ERR] Auto-unseal failed in config pipeline. Run scripts/vault/unseal.sh manually and retry." >&2
  exit 1
fi

assert_unsealed

VAULT_MERGED_SECRETS_TFVARS="$(mktemp -t vault-merged-secrets-XXXXXX.auto.tfvars.json)"
trap 'rm -f "${VAULT_MERGED_SECRETS_TFVARS:-}"' EXIT

_merge_py=(python3)
if command -v uv >/dev/null 2>&1; then
  _merge_py=(uv run --with "python-hcl2>=4,<5" python3)
fi
if ! "${_merge_py[@]}" "${ROOT_DIR}/scripts/terraform/vault_merge_config_secrets.py" \
  --tfvars-home "${TFVARS_HOME_DIR}" \
  --vault-config-tfvars "${SLICE_TFVARS}" \
  --out "${VAULT_MERGED_SECRETS_TFVARS}"; then
  echo "[ERR] Vault secret merge failed (see messages above)." >&2
  exit 1
fi

cd "${TERRAFORM_DIR}"


echo "[STEP] terraform init (Vault config)"
if ! homelab_terraform_init "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

PLAN_ARGS=(
  -input=false
  -var-file "${SLICE_TFVARS}"
  -var-file "${VAULT_TFVARS}"
  -var-file "${VAULT_MERGED_SECRETS_TFVARS}"
)

echo "[STEP] terraform plan (Vault config)"
if ! terraform plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan failed" >&2
  exit 1
fi

echo "[STEP] terraform apply (Vault config)"
if ! terraform apply -input=false -auto-approve "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform apply failed" >&2
  exit 1
fi

echo "[DONE] Vault config apply complete."
