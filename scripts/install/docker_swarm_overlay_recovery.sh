#!/usr/bin/env bash
# Recover Docker Swarm overlay networking after WAN/LAN outages (stale vxlan, sandbox join).
# Runs on every Swarm node; manager-only checks reschedule edge services (NPM).
set -euo pipefail

STATE_DIR="/var/lib/homelab"
DOCKER_RESTART_STAMP="${STATE_DIR}/docker-overlay-recovery-last-restart"
DOCKER_RESTART_MIN_INTERVAL="${DOCKER_RESTART_MIN_INTERVAL:-600}"
EDGE_HOST="${EDGE_HOST:-192.168.1.120}"
GATEWAY="${GATEWAY:-192.168.1.1}"

log() { echo "[docker-swarm-overlay-recovery] $*"; logger -t docker-swarm-overlay-recovery "$*"; }

is_manager() {
  docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null | grep -q true
}

overlay_network_ids() {
  docker network ls --filter driver=overlay --format '{{.ID}}' 2>/dev/null || true
}

vxlan_iface_matches_overlay() {
  local iface="$1"
  local id
  while read -r id; do
    [[ -z "${id}" ]] && continue
    if [[ "${iface}" == *"${id}"* ]]; then
      return 0
    fi
  done < <(overlay_network_ids)
  return 1
}

list_stale_vxlan_ifaces() {
  local iface state
  while read -r iface _ _ _ state _; do
    iface="${iface%%:}"
    if vxlan_iface_matches_overlay "${iface}"; then
      if [[ "${state}" == "DOWN" ]]; then
        echo "${iface}"
      fi
    else
      echo "${iface}"
    fi
  done < <(ip -o link show type vxlan 2>/dev/null || true)
}

remove_stale_vxlans() {
  local iface removed=0
  while read -r iface; do
    [[ -z "${iface}" ]] && continue
    log "Removing stale vxlan interface ${iface}"
    ip link delete "${iface}" 2>/dev/null || true
    removed=1
  done < <(list_stale_vxlan_ifaces)
  echo "${removed}"
}

prune_stale_docker_netns() {
  local ns
  for ns in /var/run/docker/netns/*; do
    [[ -e "${ns}" ]] || continue
    umount "${ns}" 2>/dev/null || true
  done
  rm -f /var/run/docker/netns/* 2>/dev/null || true
}

recent_docker_restart_allowed() {
  mkdir -p "${STATE_DIR}"
  if [[ ! -f "${DOCKER_RESTART_STAMP}" ]]; then
    return 0
  fi
  local last now
  last="$(cat "${DOCKER_RESTART_STAMP}")"
  now="$(date +%s)"
  (( now - last >= DOCKER_RESTART_MIN_INTERVAL ))
}

mark_docker_restart() {
  mkdir -p "${STATE_DIR}"
  date +%s >"${DOCKER_RESTART_STAMP}"
}

restart_docker_if_allowed() {
  local reason="$1"
  if ! recent_docker_restart_allowed; then
    log "Skipping docker restart (${reason}): rate-limited"
    return 1
  fi
  log "Restarting docker.service (${reason})"
  systemctl restart docker.service
  mark_docker_restart
  sleep 5
  return 0
}

swarm_stuck_error() {
  [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)" == "error" ]]
}

ntp_synchronized() {
  [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" == "yes" ]]
}

manager_has_actionable_vxlan_failures() {
  is_manager || return 1
  local svc running latest_state
  for svc in $(docker service ls -q 2>/dev/null); do
    running="$(docker service ps "${svc}" --filter desired-state=running -q 2>/dev/null | wc -l)"
    (( running > 0 )) && continue
    latest_state="$(docker service ps "${svc}" --no-trunc 2>/dev/null | sed -n '2p')"
    if [[ "${latest_state}" == *"vxlan interface: file exists"* ]] \
      || [[ "${latest_state}" == *"network sandbox join failed"* ]]; then
      return 0
    fi
  done
  return 1
}

manager_service_needs_force_update() {
  local name="$1"
  is_manager || return 1
  docker service ps "${name}" --filter desired-state=running -q 2>/dev/null | grep -q .
}

heal_edge_on_manager() {
  is_manager || return 0

  if ! manager_service_needs_force_update "nginx-proxy-manager"; then
    log "nginx-proxy-manager has no running task; forcing service update"
    docker service update --force --detach=true nginx-proxy-manager 2>/dev/null || true
  fi

  if ! ss -tln 2>/dev/null | grep -qE ':443[[:space:]]'; then
    log "TCP 443 not listening on manager; forcing nginx-proxy-manager update"
    docker service update --force --detach=true nginx-proxy-manager 2>/dev/null || true
  fi
}

gateway_reachable() {
  ping -c 1 -W 2 -I eth0 "${GATEWAY}" >/dev/null 2>&1
}

main() {
  if ! command -v docker >/dev/null 2>&1; then
    exit 0
  fi

  if ! systemctl is-active docker.service >/dev/null 2>&1; then
    exit 0
  fi

  mkdir -p "${STATE_DIR}"

  local removed=0
  removed="$(remove_stale_vxlans)"

  if (( removed )); then
    prune_stale_docker_netns
    restart_docker_if_allowed "stale vxlan removed" || true
  fi

  if swarm_stuck_error && ntp_synchronized; then
    restart_docker_if_allowed "swarm state error after NTP sync" || true
  elif manager_has_actionable_vxlan_failures && gateway_reachable; then
    restart_docker_if_allowed "actionable vxlan sandbox join failures on manager" || true
  fi

  if gateway_reachable; then
    heal_edge_on_manager
  else
    log "Gateway ${GATEWAY} unreachable on eth0; deferring edge heal"
  fi

  if is_manager; then
    local swarm_state
    swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
    log "Done (Swarm=${swarm_state:-unknown})"
  fi
}

main "$@"
