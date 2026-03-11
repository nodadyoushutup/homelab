#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SUDO_CMD=()
RESTART_SERVICES=1

CHRONY_WAIT_DROPIN_DIR="/etc/systemd/system/chrony-wait.service.d"
CHRONY_WAIT_DROPIN_FILE="${CHRONY_WAIT_DROPIN_DIR}/10-no-timeout.conf"
DOCKER_DROPIN_DIR="/etc/systemd/system/docker.service.d"
DOCKER_DROPIN_FILE="${DOCKER_DROPIN_DIR}/10-wait-for-time-sync.conf"

usage() {
  cat <<'EOF'
Usage: docker_swarm_time_sync_guard.sh [--no-restart]

Applies systemd drop-ins so Docker waits for chrony time synchronization
before startup, preventing Swarm manager startup failures on bad boot time.

Options:
  --no-restart   Apply config and enable chrony-wait, but do not restart services.
EOF
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

init_privilege_command() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO_CMD=()
    return 0
  fi

  require_cmd sudo
  SUDO_CMD=(sudo)
}

as_root() {
  "${SUDO_CMD[@]}" "$@"
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --no-restart)
        RESTART_SERVICES=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "Unknown argument: $1"
        ;;
    esac
  done
}

ensure_units_exist() {
  if ! systemctl cat docker.service >/dev/null 2>&1; then
    die "docker.service not found."
  fi

  if ! systemctl cat chrony-wait.service >/dev/null 2>&1; then
    die "chrony-wait.service not found. Install/enable chrony on this host first."
  fi
}

write_dropins() {
  log "Writing ${CHRONY_WAIT_DROPIN_FILE}"
  as_root install -d -m 0755 "${CHRONY_WAIT_DROPIN_DIR}"
  as_root tee "${CHRONY_WAIT_DROPIN_FILE}" >/dev/null <<'EOF'
[Service]
TimeoutStartSec=0
EOF

  log "Writing ${DOCKER_DROPIN_FILE}"
  as_root install -d -m 0755 "${DOCKER_DROPIN_DIR}"
  as_root tee "${DOCKER_DROPIN_FILE}" >/dev/null <<'EOF'
[Unit]
Requires=chrony-wait.service
After=chrony-wait.service time-sync.target
Wants=time-sync.target
EOF
}

apply_systemd() {
  log "Reloading systemd and enabling chrony-wait.service"
  as_root systemctl daemon-reload
  as_root systemctl enable chrony-wait.service >/dev/null

  if [[ "${RESTART_SERVICES}" == "1" ]]; then
    log "Restarting chrony, waiting for sync, then restarting Docker"
    if systemctl cat chrony.service >/dev/null 2>&1; then
      as_root systemctl restart chrony.service
    else
      warn "chrony.service unit not found; skipping chrony restart."
    fi
    as_root systemctl start chrony-wait.service
    as_root systemctl restart docker.service
  else
    log "Skipping service restart (--no-restart)."
  fi
}

show_status() {
  echo "=== chrony-wait ==="
  systemctl is-enabled chrony-wait.service
  systemctl status chrony-wait.service --no-pager -l | sed -n '1,30p'

  echo "=== docker dependencies ==="
  systemctl show docker.service -p After -p Wants -p Requires

  if command -v docker >/dev/null 2>&1; then
    echo "=== docker swarm ==="
    docker info --format 'SwarmState={{.Swarm.LocalNodeState}} Manager={{.Swarm.ControlAvailable}} NodeID={{.Swarm.NodeID}}'
  fi
}

main() {
  parse_args "$@"
  require_cmd systemctl
  init_privilege_command
  ensure_units_exist
  write_dropins
  apply_systemd
  show_status
  log "Done."
}

main "$@"
