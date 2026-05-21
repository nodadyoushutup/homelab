#!/usr/bin/env bash
set -euo pipefail

# Wrapper to run service-specific purge scripts locally or via SSH on a swarm
# manager. Usage: ./scripts/docker/purge/purge.sh <service|all> [manager_host]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_LIB="${SCRIPT_DIR}/base.sh"
KNOWN_SERVICES=(
  dozzle
  gha-runner-amd64
  gha-runner-arm64
  grafana
  graphite
  harbor
  jenkins-agent-amd64
  jenkins-agent-arm64
  jenkins-controller
  nginx_proxy_manager
  node_exporter
  prometheus
  telegraf_docker_metrics
  vault
  cloud-image-repository
)
declare -A SERVICE_MAP=(
  [dozzle]="dozzle"
  [gha-runner]="gha-runner"
  [gha_runner]="gha-runner"
  [gha-runner-amd64]="gha-runner-amd64"
  [gha_runner_amd64]="gha-runner-amd64"
  [gha-runner-arm64]="gha-runner-arm64"
  [gha_runner_arm64]="gha-runner-arm64"
  [github-actions-runner]="gha-runner"
  [github_actions_runner]="gha-runner"
  [actions-runner]="gha-runner"
  [actions_runner]="gha-runner"
  [grafana]="grafana"
  [graphite]="graphite"
  [harbor]="harbor"
  [jenkins]="jenkins"
  [jenkins-agent]="jenkins-agent"
  [jenkins_agent]="jenkins-agent"
  [jenkins-agent-amd64]="jenkins-agent-amd64"
  [jenkins_agent_amd64]="jenkins-agent-amd64"
  [jenkins-agent-arm64]="jenkins-agent-arm64"
  [jenkins_agent_arm64]="jenkins-agent-arm64"
  [jenkins-controller]="jenkins-controller"
  [jenkins_controller]="jenkins-controller"
  [jenkins-config]="jenkins-controller"
  [jenkins_config]="jenkins-controller"
  [minio]="minio"
  [nginx-proxy-manager]="nginx_proxy_manager"
  [nginx_proxy_manager]="nginx_proxy_manager"
  [nginx-proxy]="nginx_proxy_manager"
  [npm]="nginx_proxy_manager"
  [node-exporter]="node_exporter"
  [node_exporter]="node_exporter"
  [prometheus]="prometheus"
  [telegraf-docker-metrics]="telegraf_docker_metrics"
  [telegraf_docker_metrics]="telegraf_docker_metrics"
  [telegraf]="telegraf_docker_metrics"
  [docker-metrics]="telegraf_docker_metrics"
  [docker_metrics]="telegraf_docker_metrics"
  [vault]="vault"
  [cloud-image-repository]="cloud-image-repository"
  [cloud_image_repository]="cloud-image-repository"
  [webserver-image]="cloud-image-repository"
  [webserver_image]="cloud-image-repository"
  [image-webserver]="cloud-image-repository"
  [image_webserver]="cloud-image-repository"
  [image-server]="cloud-image-repository"
  [images-webserver]="cloud-image-repository"
)

usage() {
  cat <<EOF
Usage: $(basename "$0") <service|all> [manager_host]

service       One of: ${KNOWN_SERVICES[*]} (or "all" to purge every repo-managed
              Swarm app). Legacy aliases such as "jenkins", "gha-runner",
              "nginx-proxy-manager", and "minio" are still accepted.
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
      run_purge "${svc}" "${TARGET_HOST}"
    done
else
  run_purge "${SERVICE_INPUT}" "${TARGET_HOST}"
fi
