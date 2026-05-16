#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
  echo "[ERR] unseal.sh does not accept positional arguments." >&2
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
VAULT_TFVARS_DIR="${VAULT_TFVARS_DIR:-${VAULT_TFVARS_HOME}/terraform/swarm/vault}"
VAULT_INIT_FILE="${VAULT_TFVARS_DIR}/init.json"
VAULT_ENV_FILE="${VAULT_TFVARS_DIR}/.env"
DEFAULT_VAULT_ADDR="${DEFAULT_VAULT_ADDR:-http://swarm-cp-0.local:8200}"
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

vault_is_sealed() {
  local vault_addr="$1"

  curl -fsS "${vault_addr}/v1/sys/seal-status" | python3 -c 'import json,sys; print(str(json.load(sys.stdin).get("sealed", True)).lower())'
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
      log_info "Using local docker runtime for unseal actions."
      return 0
    fi
  fi

  manager_host="$(detect_swarm_manager_host)"
  if [[ -n "${manager_host}" ]]; then
    command -v ssh >/dev/null 2>&1 || fail "ssh is required for remote docker unseal actions."
    VAULT_DOCKER_MODE="remote"
    VAULT_DOCKER_REMOTE_HOST="${manager_host}"
    log_info "Using remote docker runtime via ssh host ${VAULT_DOCKER_REMOTE_HOST}."
    return 0
  fi

  fail "Unable to resolve a docker runtime for Vault unseal actions."
}

docker_cmd() {
  if [[ "${VAULT_DOCKER_MODE}" == "remote" ]]; then
    ssh "${VAULT_DOCKER_REMOTE_HOST}" docker "$@"
    return $?
  fi

  docker "$@"
}

read_unseal_keys() {
  python3 - "${VAULT_INIT_FILE}" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    payload = json.load(fh)

keys = payload.get("unseal_keys_b64") or payload.get("keys_base64") or []
threshold = payload.get("unseal_threshold") or payload.get("secret_threshold")

if not isinstance(keys, list) or len(keys) == 0:
    raise SystemExit("init.json missing unseal keys")
if not isinstance(threshold, int) or threshold <= 0:
    raise SystemExit("init.json missing threshold")
if len(keys) < threshold:
    raise SystemExit("init.json does not include enough keys for threshold")

for key in keys[:threshold]:
    print(key)
PY
}

main() {
  local vault_addr sealed container_id
  local -a vault_addr_candidates

  [[ -f "${VAULT_INIT_FILE}" ]] || fail "Missing ${VAULT_INIT_FILE}; run scripts/vault/bootstrap.sh first."

  mapfile -t vault_addr_candidates < <(collect_vault_addr_candidates)
  ((${#vault_addr_candidates[@]} > 0)) || fail "Unable to determine a Vault address candidate."

  if ! vault_addr="$(wait_for_reachable_vault_api "${vault_addr_candidates[@]}")"; then
    fail "Vault API did not become reachable within ${WAIT_SECONDS}s. Tried: ${vault_addr_candidates[*]}"
  fi
  log_info "Using VAULT_ADDR=${vault_addr}"

  sealed="$(vault_is_sealed "${vault_addr}")"
  if [[ "${sealed}" == "false" ]]; then
    log_info "Vault is already unsealed, continuing."
    return 0
  fi

  resolve_docker_runtime
  container_id="$(find_vault_container_id)" || fail "Unable to locate a running Vault container for unseal operation."

  mapfile -t keys < <(read_unseal_keys)
  ((${#keys[@]} > 0)) || fail "No unseal keys available."

  for key in "${keys[@]}"; do
    docker_cmd exec "${container_id}" vault operator unseal "${key}" > /dev/null

    sealed="$(vault_is_sealed "${vault_addr}")"
    if [[ "${sealed}" == "false" ]]; then
      log_info "Vault unseal complete."
      return 0
    fi
  done

  fail "Vault remains sealed after submitting threshold unseal keys."
}

main
