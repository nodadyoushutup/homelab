#!/usr/bin/env bash
# Apply swarm_pi_clock_bootstrap.sh to every Swarm Raspberry Pi node.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SSH_KEY="${SSH_KEY:-${ROOT_DIR}/.config/.ssh/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-${ROOT_DIR}/.config/.ssh/known_hosts}"
SSH_USER="${SSH_USER:-nodadyoushutup}"
INSTALL_SCRIPT="${ROOT_DIR}/scripts/install/swarm_pi_clock_bootstrap.sh"
GUARD_SCRIPT="${ROOT_DIR}/scripts/install/docker_swarm_time_sync_guard.sh"
GATEWAY_NTP="${GATEWAY_NTP:-192.168.1.1}"

SWARM_IPS=(120 121 122 123 124 125)

usage() {
  cat <<EOF
Usage: apply_swarm_pi_clock_bootstrap_all.sh [--dry-run]

Runs scripts/install/swarm_pi_clock_bootstrap.sh on swarm-cp-0 and swarm-wk-0..4
(${SWARM_IPS[*]} on 192.168.1.0/24).

Environment:
  SSH_KEY, KNOWN_HOSTS, SSH_USER, GATEWAY_NTP
EOF
}

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

[[ -f "${INSTALL_SCRIPT}" ]] || fail "Missing ${INSTALL_SCRIPT}"
[[ -f "${GUARD_SCRIPT}" ]] || fail "Missing ${GUARD_SCRIPT}"
[[ -f "${SSH_KEY}" ]] || fail "Missing SSH key: ${SSH_KEY}"

ssh_base() {
  local -a cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15)
  cmd+=(-i "${SSH_KEY}")
  [[ -f "${KNOWN_HOSTS}" ]] && cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  printf '%s\n' "${cmd[@]}"
}

readarray -t SSH_BASE < <(ssh_base)

apply_host() {
  local ip="$1"
  local host="${SSH_USER}@192.168.1.${ip}"
  log "=== 192.168.1.${ip} ==="
  ping -c 1 -W 2 "192.168.1.${ip}" >/dev/null 2>&1 || fail "ping failed for 192.168.1.${ip}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log "dry-run: would patch ${host}"
    return 0
  fi

  scp -o BatchMode=yes -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
    ${KNOWN_HOSTS:+-o "UserKnownHostsFile=${KNOWN_HOSTS}"} \
    "${INSTALL_SCRIPT}" "${GUARD_SCRIPT}" "${host}:/tmp/"

  "${SSH_BASE[@]}" "${host}" \
    "mkdir -p /tmp/install && mv /tmp/swarm_pi_clock_bootstrap.sh /tmp/docker_swarm_time_sync_guard.sh /tmp/install/ && chmod +x /tmp/install/*.sh && sudo GATEWAY_NTP=${GATEWAY_NTP} /tmp/install/swarm_pi_clock_bootstrap.sh"
}

for ip in "${SWARM_IPS[@]}"; do
  apply_host "${ip}"
done

log "All nodes patched."
