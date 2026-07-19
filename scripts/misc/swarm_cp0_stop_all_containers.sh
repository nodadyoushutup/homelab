#!/usr/bin/env bash
# Emergency: after swarm-cp-0 is reachable, stop all workloads so the host stays SSH-able.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SSH_KEY="${SSH_KEY:-${ROOT_DIR}/.config/.ssh/ca/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-${ROOT_DIR}/.config/.ssh/known_hosts}"
SSH_USER="${SSH_USER:-nodadyoushutup}"
HOST="${HOST:-swarm-cp-0.local}"
TARGET_IP="${TARGET_IP:-192.168.1.120}"
PING_INTERVAL="${PING_INTERVAL:-0.5}"
SSH_RETRY_INTERVAL="${SSH_RETRY_INTERVAL:-0.5}"
WAIT_FOR_DOWN="${WAIT_FOR_DOWN:-1}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

wait_for_ping() {
  log "ping: waiting for ${TARGET_IP} ..."
  until ping -c 1 -W 1 "${TARGET_IP}" >/dev/null 2>&1; do
    sleep "${PING_INTERVAL}"
  done
  log "ping: ${TARGET_IP} is up"
}

wait_for_ping_down() {
  log "ping: waiting for ${TARGET_IP} to go down (reboot) ..."
  local i=0
  while ping -c 1 -W 1 "${TARGET_IP}" >/dev/null 2>&1; do
    i=$((i + 1))
    if [[ "${i}" -ge 180 ]]; then
      log "ping: still up after 90s; continuing anyway"
      return 0
    fi
    sleep "${PING_INTERVAL}"
  done
  log "ping: host is down"
}

wait_for_ssh() {
  log "ssh: waiting for ${HOST} ..."
  local -a ssh_base=(
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=2
    -i "${SSH_KEY}"
  )
  [[ -f "${KNOWN_HOSTS}" ]] && ssh_base+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  until "${ssh_base[@]}" "${SSH_USER}@${HOST}" 'exit 0' >/dev/null 2>&1; do
    sleep "${SSH_RETRY_INTERVAL}"
  done
  log "ssh: connected"
}

stop_all_remote() {
  log "stopping all containers and scaling swarm services to 0 ..."
  local -a ssh_cmd=(
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15
    -i "${SSH_KEY}"
  )
  [[ -f "${KNOWN_HOSTS}" ]] && ssh_cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  "${ssh_cmd[@]}" "${SSH_USER}@${HOST}" bash -s <<'REMOTE'
set -euo pipefail
echo "host=$(hostname) uptime=$(uptime | head -1)"

if docker info >/dev/null 2>&1; then
  if docker info 2>/dev/null | grep -q 'Swarm: active'; then
    mapfile -t services < <(docker service ls --format '{{.Name}}' 2>/dev/null || true)
    if ((${#services[@]} > 0)); then
      echo "scaling ${#services[@]} swarm services to 0 ..."
      args=()
      for svc in "${services[@]}"; do
        args+=("${svc}=0")
      done
      docker service scale "${args[@]}" 2>/dev/null || true
    fi
  fi

  mapfile -t ids < <(docker ps -aq 2>/dev/null || true)
  if ((${#ids[@]} > 0)); then
    echo "disabling restart on ${#ids[@]} containers ..."
    docker update --restart=no "${ids[@]}" 2>/dev/null || true
  fi

  mapfile -t running < <(docker ps -q 2>/dev/null || true)
  if ((${#running[@]} > 0)); then
    echo "stopping ${#running[@]} running containers ..."
    docker stop -t 8 "${running[@]}" 2>/dev/null || true
  fi
fi

echo "--- remaining ---"
docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | head -20 || true
count=$(docker ps -q 2>/dev/null | wc -l)
echo "running_containers=${count}"
REMOTE
}

[[ "${WAIT_FOR_DOWN}" == "1" ]] && wait_for_ping_down || true
wait_for_ping
wait_for_ssh
stop_all_remote
log "done — swarm-cp-0 should be idle; bring stacks back one at a time"
