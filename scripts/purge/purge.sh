#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run service-specific purge scripts locally or via SSH on a swarm
# manager. Usage: ./scripts/purge/purge.sh <service|all> [manager_host]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_LIB="${SCRIPT_DIR}/base.sh"
KNOWN_SERVICES=(dozzle grafana graphite jenkins minio nginx-proxy-manager node-exporter prometheus)
declare -A SERVICE_MAP=(
  [dozzle]="dozzle"
  [grafana]="grafana"
  [graphite]="graphite"
  [jenkins]="jenkins"
  [jenkins-controller]="jenkins"
  [jenkins_controller]="jenkins"
  [jenkins-agent]="jenkins"
  [jenkins_agent]="jenkins"
  [jenkins-config]="jenkins"
  [jenkins_config]="jenkins"
  [minio]="minio"
  [nginx-proxy-manager]="nginx-proxy-manager"
  [nginx_proxy_manager]="nginx-proxy-manager"
  [nginx-proxy]="nginx-proxy-manager"
  [npm]="nginx-proxy-manager"
  [node-exporter]="node-exporter"
  [node_exporter]="node-exporter"
  [prometheus]="prometheus"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <service|all> [manager_host]

service       One of: ${KNOWN_SERVICES[*]} (or "all" to purge everything)
manager_host  Optional SSH target; if set, purge runs there via SSH. Without it,
              the purge script executes locally (use when already on swarm-cp-0).
EOF
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

resolve_service() {
  local requested="${1,,}"
  local script_name=""

  # Try direct map, underscore, and hyphen variants.
  script_name="${SERVICE_MAP[$requested]:-}"
  if [[ -z "${script_name}" ]]; then
    local alt="${requested//-/_}"
    script_name="${SERVICE_MAP[$alt]:-}"
  fi
  if [[ -z "${script_name}" ]]; then
    local alt="${requested//_/-}"
    script_name="${SERVICE_MAP[$alt]:-}"
  fi

  if [[ -z "${script_name}" ]]; then
    echo "Unknown service: ${requested}" >&2
    echo "Known services: ${KNOWN_SERVICES[*]}" >&2
    exit 1
  fi

  SERVICE_SCRIPT="${SCRIPT_DIR}/${script_name}.sh"
  SERVICE_NAME="${script_name}"
}

run_purge() {
  local service_input="$1"
  local target_host="$2"

  resolve_service "${service_input}"

  local payload=""
  local payload_b64=""

  if [[ -f "${BASE_LIB}" && -f "${SERVICE_SCRIPT}" ]]; then
    payload="$(cat "${BASE_LIB}" "${SERVICE_SCRIPT}")"
    payload_b64="$(printf '%s' "${payload}" | base64 | tr -d '\n')"
  fi

  if [[ ! -f "${SERVICE_SCRIPT}" ]]; then
    echo "Purge script not found for ${SERVICE_NAME}: ${SERVICE_SCRIPT}" >&2
    return 1
  fi

  if [[ -n "${target_host}" ]]; then
    need_cmd ssh

    echo "==> Running ${SERVICE_NAME} purge on ${target_host} via SSH..."
    local ssh_known_hosts="${SWARM_PURGE_KNOWN_HOSTS_FILE:-${HOME}/.ssh/known_hosts}"
    local ssh_strict="${SWARM_PURGE_STRICT_HOSTS:-no}"

    # Forward relevant SWARM_PURGE_* env vars when present.
    local -a forward_env=()
    for var in SWARM_PURGE_AUTO_TRUST_SSH_HOSTS SWARM_PURGE_KNOWN_HOSTS_FILE SWARM_PURGE_SSH_KEYSCAN_TIMEOUT SWARM_PURGE_SKIP_REMOTE SWARM_PURGE_SSH_USER SWARM_PURGE_STRICT_HOSTS; do
      if [[ -n "${!var:-}" ]]; then
        forward_env+=("${var}=${!var}")
      fi
    done
    if [[ -n "${payload_b64}" ]]; then
      forward_env+=("PURGE_PAYLOAD_B64=${payload_b64}")
    fi

    local -a cmd=(
      ssh
      -o "StrictHostKeyChecking=${ssh_strict}"
      -o "UserKnownHostsFile=${ssh_known_hosts}"
      "${target_host}"
    )
    if ((${#forward_env[@]})); then
      cmd+=(env "${forward_env[@]}")
    fi
    cmd+=(bash -s)

    if [[ -n "${payload}" ]]; then
      printf '%s' "${payload}" | "${cmd[@]}"
    else
      "${cmd[@]}" < "${SERVICE_SCRIPT}"
    fi
  else
    echo "==> Running ${SERVICE_NAME} purge locally..."
    if [[ -n "${payload_b64}" ]]; then
      PURGE_PAYLOAD_B64="${payload_b64}" "${SERVICE_SCRIPT}"
    else
      "${SERVICE_SCRIPT}"
    fi
  fi
}

if (( $# < 1 || $# > 2 )); then
  usage
  exit 1
fi

SERVICE_INPUT="$1"
TARGET_HOST="${2:-}"

if [[ "${SERVICE_INPUT,,}" == "all" ]]; then
  for svc in "${KNOWN_SERVICES[@]}"; do
    # Minio runs outside the swarm cluster; skip it on blanket purges to avoid errors.
    if [[ "${svc}" == "minio" ]]; then
      echo "==> Skipping minio (managed outside swarm)"
      continue
    fi
    run_purge "${svc}" "${TARGET_HOST}"
  done
else
  run_purge "${SERVICE_INPUT}" "${TARGET_HOST}"
fi
