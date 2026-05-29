#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

if [[ $# -gt 0 ]]; then
  echo "[ERR] vault config pipeline uses fixed input paths and does not accept override arguments." >&2
  echo "      expected tfvars:  <TFVARS_HOME>/terraform/swarm/vault/config.tfvars" >&2
  echo "      plus merged HCL:  secrets/secret_files in <TFVARS_HOME>/terraform/**/{app,config,database}.tfvars" >&2
  echo "      and kubernetes/**/*.tfvars (legacy secrets.tfvars still merged if present;" >&2
  echo "      see scripts/terraform/vault_merge_config_secrets.py)" >&2
  echo "      expected backend: <TFVARS_HOME>/minio.backend.hcl (default: <repo>/.config/minio.backend.hcl)" >&2
  exit 2
fi

VAULT_UNSEAL_SCRIPT="${ROOT_DIR}/scripts/vault/unseal.sh"
VAULT_TFVARS_HOME="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
VAULT_TFVARS_DIR="${VAULT_TFVARS_HOME}/terraform/swarm/vault"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
VAULT_INIT_FILE="${VAULT_TFVARS_DIR}/init.json"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"

SERVICE_NAME="vault"
STAGE_NAME="Vault config"
# No NFS mounts; skip nfs.tfvars so the stack need not declare `nfs` variable.
SWARM_SKIP_NFS_PROVIDER_TFVARS=1
export SWARM_SKIP_NFS_PROVIDER_TFVARS
# No Swarm task dns_config; skip dns.tfvars so the stack need not declare dns_nameservers.
SWARM_SKIP_DNS_PROVIDER_TFVARS=1
export SWARM_SKIP_DNS_PROVIDER_TFVARS
ENTRYPOINT_RELATIVE="terraform/swarm/vault/pipeline/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/vault/config"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

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

  while (( SECONDS < deadline )); do
    for candidate in "${candidates[@]}"; do
      code="$(vault_health_code "${candidate}")"
      case "${code}" in
        200|429|472|473|501|503)
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
    echo "[ERR] Missing ${VAULT_INIT_FILE}. Run terraform/swarm/vault/pipeline/app.sh first to bootstrap Vault." >&2
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
    --vault-config-tfvars "${TFVARS_HOME_DIR}/terraform/swarm/vault/config.tfvars" \
    --out "${VAULT_MERGED_SECRETS_TFVARS}"; then
    echo "[ERR] Vault secret merge failed (see messages above)." >&2
    exit 1
  fi

  PLAN_ARGS_EXTRA+=(-var-file "${VAULT_MERGED_SECRETS_TFVARS}")
  APPLY_ARGS_EXTRA+=(-var-file "${VAULT_MERGED_SECRETS_TFVARS}")
}

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
