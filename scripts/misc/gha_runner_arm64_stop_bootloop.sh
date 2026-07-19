#!/usr/bin/env bash
# After an ARM64 pool host reboot: wait for ping + SSH, then stop/remove GHA runner
# containers that crash-loop on stale .runner state (frees CPU/RAM before sshd dies).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SSH_KEY="${SSH_KEY:-${ROOT_DIR}/.config/.ssh/ca/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-${ROOT_DIR}/.config/.ssh/known_hosts}"
SSH_USER="${SSH_USER:-nodadyoushutup}"
PING_INTERVAL="${PING_INTERVAL:-0.5}"
SSH_RETRY_INTERVAL="${SSH_RETRY_INTERVAL:-0.5}"
PING_TIMEOUT_SEC="${PING_TIMEOUT_SEC:-1}"
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-3}"

HOSTS=(swarm-wk-0.local)
ALSO_CP0=0

usage() {
  cat <<'EOF'
Usage: gha_runner_arm64_stop_bootloop.sh [options]

Waits for host(s) to answer ping, then SSH, then immediately stops/removes
homelab-gha-runner-arm64* containers (boot-loop relief after reboot).

Options:
  --host <name-or-ip>   Pool host (repeatable; default: swarm-wk-0.local)
  --also-cp0           Also run against 192.168.1.120 (legacy control-plane pool)
  --ping-interval <s>  Seconds between pings (default: 0.5)
  --dry-run            Print actions without docker rm

Examples:
  ./scripts/misc/gha_runner_arm64_stop_bootloop.sh
  ./scripts/misc/gha_runner_arm64_stop_bootloop.sh --also-cp0
  ./scripts/misc/gha_runner_arm64_stop_bootloop.sh --host 192.168.1.26
EOF
}

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

resolve_target() {
  local host="$1"
  if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${host}"
    return 0
  fi
  local ip
  ip="$(getent ahostsv4 "${host}" 2>/dev/null | awk '{print $1; exit}')" || true
  if [[ -n "${ip}" ]]; then
    echo "${ip}"
  else
    echo "${host}"
  fi
}

wait_for_ping() {
  local target="$1"
  log "ping: waiting for ${target} ..."
  until ping -c 1 -W "${PING_TIMEOUT_SEC}" "${target}" >/dev/null 2>&1; do
    sleep "${PING_INTERVAL}"
  done
  log "ping: ${target} is up"
}

wait_for_ssh() {
  local host="$1"
  log "ssh: waiting for ${host} ..."
  local -a ssh_base=(
    ssh
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}"
    -i "${SSH_KEY}"
  )
  if [[ -f "${KNOWN_HOSTS}" ]]; then
    ssh_base+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  fi
  until "${ssh_base[@]}" "${SSH_USER}@${host}" 'exit 0' >/dev/null 2>&1; do
    sleep "${SSH_RETRY_INTERVAL}"
  done
  log "ssh: ${host} is accepting connections"
}

stop_bootloop_containers() {
  local host="$1"
  local remote
  remote="$(cat <<'REMOTE'
set -euo pipefail
ids="$(docker ps -aq --filter name=homelab-gha-runner-arm64 2>/dev/null || true)"
if [ -z "${ids}" ]; then
  echo "no homelab-gha-runner-arm64 containers"
  exit 0
fi
echo "stopping: $(docker ps -a --filter name=homelab-gha-runner-arm64 --format '{{.Names}} ({{.Status}})' | tr '\n' ' ')"
docker rm -f ${ids} >/dev/null
echo "removed homelab-gha-runner-arm64 containers"
REMOTE
)"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would ssh to ${host} and remove homelab-gha-runner-arm64*"
    return 0
  fi

  local -a ssh_cmd=(
    ssh
    -o BatchMode=yes
    -o StrictHostKeyChecking=no
    -o ConnectTimeout="${SSH_CONNECT_TIMEOUT}"
    -i "${SSH_KEY}"
  )
  if [[ -f "${KNOWN_HOSTS}" ]]; then
    ssh_cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  fi
  "${ssh_cmd[@]}" "${SSH_USER}@${host}" bash -s <<<"${remote}"
}

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      shift
      HOSTS+=("$1")
      shift
      ;;
    --also-cp0)
      ALSO_CP0=1
      shift
      ;;
    --ping-interval)
      shift
      PING_INTERVAL="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${ALSO_CP0}" == "1" ]]; then
  HOSTS+=(192.168.1.120)
fi

if [[ ! -f "${SSH_KEY}" ]]; then
  echo "SSH key not found: ${SSH_KEY}" >&2
  exit 1
fi

for host in "${HOSTS[@]}"; do
  target="$(resolve_target "${host}")"
  wait_for_ping "${target}"
  wait_for_ssh "${host}"
  stop_bootloop_containers "${host}"
done

log "done"
