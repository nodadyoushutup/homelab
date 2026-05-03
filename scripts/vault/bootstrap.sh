#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  echo "[ERR] bootstrap.sh does not accept positional arguments." >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_ENV_LOADER="${ROOT_DIR}/scripts/terraform/load_root_env.sh"
if [[ -f "${ROOT_ENV_LOADER}" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT_ENV_LOADER}"
fi

VAULT_TFVARS_HOME="${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}"
VAULT_TFVARS_DIR="${VAULT_TFVARS_DIR:-${VAULT_TFVARS_HOME}/vault}"
VAULT_INIT_FILE="${VAULT_TFVARS_DIR}/init.json"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"
UNSEAL_KEY_SHARES="3"
UNSEAL_KEY_THRESHOLD="2"
WAIT_SECONDS="120"
VAULT_DOCKER_MODE=""
VAULT_DOCKER_REMOTE_HOST=""

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

resolve_vault_addr() {
  local resolved="${VAULT_ADDR:-}"

  if [[ -z "${resolved}" && -f "${VAULT_ENV_FILE}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${VAULT_ENV_FILE}"
    set +a
    resolved="${VAULT_ADDR:-}"
  fi

  if [[ -z "${resolved}" ]]; then
    log_warn "${VAULT_ENV_FILE} missing or VAULT_ADDR unset; falling back to ${DEFAULT_VAULT_ADDR}"
    resolved="${DEFAULT_VAULT_ADDR}"
  fi

  echo "${resolved}"
}

collect_vault_addr_candidates() {
  local env_file_addr manager_host
  local -a candidates=()

  add_candidate() {
    local candidate="$1"
    local existing
    [[ -n "${candidate}" ]] || return 0

    for existing in "${candidates[@]}"; do
      [[ "${existing}" == "${candidate}" ]] && return 0
    done

    candidates+=("${candidate}")
  }

  add_candidate "$(resolve_vault_addr)"

  if [[ -f "${VAULT_ENV_FILE}" ]]; then
    env_file_addr="$(awk -F= '/^VAULT_ADDR=/{print $2; exit}' "${VAULT_ENV_FILE}" || true)"
    add_candidate "${env_file_addr}"
  fi

  add_candidate "${DEFAULT_VAULT_ADDR}"

  manager_host="$(detect_swarm_manager_host || true)"
  if [[ -n "${manager_host}" ]]; then
    add_candidate "http://${manager_host}:8200"
  fi

  add_candidate "http://127.0.0.1:8200"
  add_candidate "http://localhost:8200"

  printf '%s\n' "${candidates[@]}"
}

detect_swarm_manager_host() {
  local host docker_swarm_cp
  local -a candidates

  host="${VAULT_SWARM_MANAGER_HOST:-}"
  if [[ -n "${host}" ]]; then
    echo "${host}"
    return 0
  fi

  docker_swarm_cp="${DOCKER_SWARM_CP:-}"
  if [[ -n "${docker_swarm_cp}" ]]; then
    host="${docker_swarm_cp#ssh://}"
    host="${host%%/*}"
    if [[ -n "${host}" ]]; then
      candidates+=("${host}")
    fi
  fi

  candidates+=("swarm-cp-0.local" "swarm-cp-0.internal")

  if command -v ssh >/dev/null 2>&1; then
    for host in "${candidates[@]}"; do
      if ssh -o BatchMode=yes -o ConnectTimeout=3 "${host}" true >/dev/null 2>&1; then
        echo "${host}"
        return 0
      fi
    done
  fi

  echo "${candidates[0]}"
}

vault_health_code() {
  local vault_addr="$1"
  curl -m 3 --connect-timeout 2 -sS -o /dev/null -w "%{http_code}" "${vault_addr}/v1/sys/health" || true
}

wait_for_reachable_vault_api() {
  local -a candidates=("$@")
  local deadline=$((SECONDS + WAIT_SECONDS))

  while (( SECONDS < deadline )); do
    local candidate code
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

  return 1
}

vault_is_initialized() {
  local vault_addr="$1"

  curl -fsS "${vault_addr}/v1/sys/init" | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("initialized", False)).lower())'
}

find_vault_container_id() {
  local cid

  cid="$(docker_cmd ps --filter label=com.docker.swarm.service.name=vault --format '{{.ID}}' | head -n 1)"
  if [[ -n "${cid}" ]]; then
    echo "${cid}"
    return 0
  fi

  cid="$(docker_cmd ps --filter name=vault --format '{{.ID}}' | head -n 1)"
  if [[ -n "${cid}" ]]; then
    echo "${cid}"
    return 0
  fi

  return 1
}

resolve_docker_runtime() {
  local manager_host local_cid

  if command -v docker >/dev/null 2>&1; then
    local_cid="$(docker ps --filter label=com.docker.swarm.service.name=vault --format '{{.ID}}' | head -n 1 || true)"
    if [[ -n "${local_cid}" ]] || docker service inspect vault >/dev/null 2>&1; then
      VAULT_DOCKER_MODE="local"
      log_info "Using local docker runtime for bootstrap actions."
      return 0
    fi
  fi

  manager_host="$(detect_swarm_manager_host)"
  if [[ -n "${manager_host}" ]]; then
    command -v ssh >/dev/null 2>&1 || fail "ssh is required for remote docker bootstrap actions."
    VAULT_DOCKER_MODE="remote"
    VAULT_DOCKER_REMOTE_HOST="${manager_host}"
    log_info "Using remote docker runtime via ssh host ${VAULT_DOCKER_REMOTE_HOST}."
    return 0
  fi

  fail "Unable to resolve a docker runtime for Vault bootstrap actions."
}

docker_cmd() {
  if [[ "${VAULT_DOCKER_MODE}" == "remote" ]]; then
    ssh "${VAULT_DOCKER_REMOTE_HOST}" docker "$@"
    return $?
  fi

  docker "$@"
}

chmod_temporary_policy() {
  chmod 775 "${VAULT_TFVARS_DIR}"

  if [[ -f "${VAULT_INIT_FILE}" ]]; then
    chmod 775 "${VAULT_INIT_FILE}"
  fi

  if [[ -f "${VAULT_ENV_FILE}" ]]; then
    chmod 775 "${VAULT_ENV_FILE}"
  fi
}

write_env_file() {
  local vault_addr="$1"
  local root_token

  root_token="$(python3 - "${VAULT_INIT_FILE}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

root_token = payload.get("root_token")
if not root_token:
    raise SystemExit("init.json missing root_token")

print(root_token)
PY
)"

  cat > "${VAULT_ENV_FILE}" <<EOF_ENV
# Auto-generated by scripts/vault/bootstrap.sh
VAULT_ADDR=${vault_addr}
VAULT_TOKEN=${root_token}
EOF_ENV
}

validate_init_json() {
  python3 - "${VAULT_INIT_FILE}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

if not payload.get("root_token"):
    raise SystemExit("init.json missing root_token")

keys = payload.get("unseal_keys_b64") or payload.get("keys_base64") or []
if not isinstance(keys, list) or len(keys) == 0:
    raise SystemExit("init.json missing unseal keys")

threshold = payload.get("unseal_threshold") or payload.get("secret_threshold")
if not isinstance(threshold, int) or threshold <= 0:
    raise SystemExit("init.json missing threshold metadata")

if len(keys) < threshold:
    raise SystemExit("init.json has fewer keys than threshold")
PY
}

main() {
  local vault_addr initialized container_id
  local -a vault_addr_candidates

  mkdir -p "${VAULT_TFVARS_DIR}"

  mapfile -t vault_addr_candidates < <(collect_vault_addr_candidates)
  ((${#vault_addr_candidates[@]} > 0)) || fail "Unable to determine a Vault address candidate."

  if ! vault_addr="$(wait_for_reachable_vault_api "${vault_addr_candidates[@]}")"; then
    fail "Vault API did not become reachable within ${WAIT_SECONDS}s. Tried: ${vault_addr_candidates[*]}"
  fi
  log_info "Using VAULT_ADDR=${vault_addr}"

  initialized="$(vault_is_initialized "${vault_addr}")"

  if [[ "${initialized}" == "true" ]]; then
    if [[ ! -f "${VAULT_INIT_FILE}" ]]; then
      fail "Vault is already initialized but ${VAULT_INIT_FILE} is missing. Restore this file before continuing."
    fi

    log_info "Vault is already initialized; bootstrap will not reinitialize."
    validate_init_json
    write_env_file "${vault_addr}"
    chmod_temporary_policy
    log_info "Refreshed ${VAULT_ENV_FILE} from existing init metadata."
    return 0
  fi

  resolve_docker_runtime
  container_id="$(find_vault_container_id)" || fail "Unable to locate a running Vault container for initialization."

  log_info "Initializing Vault via docker exec (key-shares=${UNSEAL_KEY_SHARES}, key-threshold=${UNSEAL_KEY_THRESHOLD})."
  docker_cmd exec "${container_id}" vault operator init -key-shares="${UNSEAL_KEY_SHARES}" -key-threshold="${UNSEAL_KEY_THRESHOLD}" -format=json > "${VAULT_INIT_FILE}"

  validate_init_json
  write_env_file "${vault_addr}"
  chmod_temporary_policy

  log_info "Vault bootstrap complete. Artifacts written to ${VAULT_TFVARS_DIR}."
}

main
