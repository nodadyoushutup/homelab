#!/usr/bin/env bash
# Cold-boot time sync for Swarm Raspberry Pi nodes (dead RTC, NTS chicken-and-egg).
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SUDO_CMD=()
RESTART_CHRONY=1
GATEWAY_NTP="${GATEWAY_NTP:-192.168.1.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CHRONY_BOOTSTRAP_SOURCES="/etc/chrony/sources.d/00-homelab-bootstrap.sources"
CHRONY_MAKESTEP_CONF="/etc/chrony/conf.d/zz-homelab-makestep.conf"
FAKE_HWCLOCK_TIMER_DROPIN="/etc/systemd/system/fake-hwclock-save.timer.d/10-homelab-frequent.conf"
FAKE_HWCLOCK_SYNC_SERVICE="/etc/systemd/system/fake-hwclock-save-on-sync.service"

usage() {
  cat <<EOF
Usage: swarm_pi_clock_bootstrap.sh [--no-restart-chrony]

Installs cold-boot time sync on a Swarm Pi (including unclean power loss):
  - fake-hwclock + 5-minute periodic save + save after chrony sync
  - plain UDP NTP bootstrap sources (no NTS/TLS — works with dead RTC)
  - makestep 1 -1 (always step large offsets)
  - docker_swarm_time_sync_guard.sh drop-ins (Docker waits for chrony)
  - docker_swarm_boot_recovery.service (boot: vxlan/Swarm/NPM edge recovery)
  - docker-swarm-overlay-recovery.timer (every 2 min + after network-online)
  - swarm-pi-eth0-watchdog.timer (bounce eth0 / reboot on silent LAN loss)

Environment:
  GATEWAY_NTP   LAN NTP server (default: 192.168.1.1)

Options:
  --no-restart-chrony   Write config only; do not restart chrony.
EOF
}

init_privilege_command() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO_CMD=()
    return 0
  fi
  command -v sudo >/dev/null 2>&1 || die "Run as root or install sudo."
  SUDO_CMD=(sudo)
}

as_root() {
  "${SUDO_CMD[@]}" "$@"
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --no-restart-chrony)
        RESTART_CHRONY=0
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

ensure_packages() {
  if ! dpkg -s chrony >/dev/null 2>&1; then
    die "chrony is not installed."
  fi

  if ! dpkg -s fake-hwclock >/dev/null 2>&1; then
    log "Installing fake-hwclock"
    as_root apt-get update -qq
    as_root apt-get install -y fake-hwclock
  fi

  # Ubuntu ships systemd units; the legacy SysV fake-hwclock.service is masked.
  for unit in fake-hwclock-load.service fake-hwclock-save.service fake-hwclock-save.timer; do
    if systemctl cat "${unit}" >/dev/null 2>&1; then
      as_root systemctl enable "${unit}" >/dev/null 2>&1 || true
    fi
  done
}

write_chrony_bootstrap_sources() {
  log "Writing ${CHRONY_BOOTSTRAP_SOURCES}"
  as_root tee "${CHRONY_BOOTSTRAP_SOURCES}" >/dev/null <<EOF
# Homelab Swarm Pi cold-boot NTP (plain UDP — no NTS/TLS).
# Managed by scripts/install/swarm_pi_clock_bootstrap.sh — do not edit by hand.
#
# NTS pools in ubuntu-ntp-pools.sources fail TLS validation when the RTC is
# stale; these sources sync without certificates so chrony-wait finishes fast.

server ${GATEWAY_NTP} iburst minpoll 3 maxpoll 6 prefer
pool time.cloudflare.com iburst maxsources 2
pool pool.ntp.org iburst maxsources 2
EOF
}

write_chrony_makestep() {
  log "Writing ${CHRONY_MAKESTEP_CONF}"
  as_root tee "${CHRONY_MAKESTEP_CONF}" >/dev/null <<'EOF'
# Always step when more than 1s off (dead RTC / long power loss).
makestep 1 -1
EOF
}

write_fake_hwclock_plug_pull_hooks() {
  log "Writing ${FAKE_HWCLOCK_TIMER_DROPIN} (every 5 min — survives pull-the-plug)"
  as_root install -d -m 0755 "$(dirname "${FAKE_HWCLOCK_TIMER_DROPIN}")"
  as_root tee "${FAKE_HWCLOCK_TIMER_DROPIN}" >/dev/null <<'EOF'
# Homelab: save often; shutdown hooks never run on pull-the-plug.
[Timer]
OnCalendar=
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true
EOF

  log "Writing ${FAKE_HWCLOCK_SYNC_SERVICE} (save once after chrony sync each boot)"
  as_root tee "${FAKE_HWCLOCK_SYNC_SERVICE}" >/dev/null <<'EOF'
[Unit]
Description=Save fake-hwclock after chrony sync (plug-pull safe)
After=chrony-wait.service time-sync.target
Wants=chrony-wait.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/fake-hwclock save force
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  as_root systemctl daemon-reload
  as_root systemctl enable fake-hwclock-save-on-sync.service >/dev/null
  as_root systemctl restart fake-hwclock-save.timer || as_root systemctl start fake-hwclock-save.timer
}

apply_docker_time_sync_guard() {
  local guard="${SCRIPT_DIR}/docker_swarm_time_sync_guard.sh"
  if [[ ! -f "${guard}" ]]; then
    guard="/tmp/install/docker_swarm_time_sync_guard.sh"
  fi
  [[ -f "${guard}" ]] || die "Missing docker_swarm_time_sync_guard.sh beside ${SCRIPT_DIR}"
  log "Applying docker_swarm_time_sync_guard.sh (--no-restart)"
  as_root bash "${guard}" --no-restart
}

install_docker_swarm_overlay_recovery() {
  local overlay="${SCRIPT_DIR}/docker_swarm_overlay_recovery.sh"
  local boot="${SCRIPT_DIR}/docker_swarm_boot_recovery.sh"
  if [[ ! -f "${overlay}" ]]; then
    overlay="/tmp/install/docker_swarm_overlay_recovery.sh"
  fi
  if [[ ! -f "${boot}" ]]; then
    boot="/tmp/install/docker_swarm_boot_recovery.sh"
  fi
  [[ -f "${overlay}" ]] || die "Missing docker_swarm_overlay_recovery.sh beside ${SCRIPT_DIR}"
  [[ -f "${boot}" ]] || die "Missing docker_swarm_boot_recovery.sh beside ${SCRIPT_DIR}"

  log "Installing docker_swarm_overlay_recovery.sh and systemd units"
  as_root install -m 0755 "${overlay}" /usr/local/sbin/docker_swarm_overlay_recovery.sh
  as_root install -m 0755 "${boot}" /usr/local/sbin/docker_swarm_boot_recovery.sh

  as_root tee /etc/systemd/system/docker-swarm-overlay-recovery.service >/dev/null <<'EOF'
[Unit]
Description=Recover Swarm overlay networking and NPM edge after WAN/LAN outages
After=docker.service chrony-wait.service network-online.target
Wants=chrony-wait.service network-online.target
ConditionPathExists=/usr/bin/docker

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker_swarm_overlay_recovery.sh

[Install]
WantedBy=multi-user.target
EOF

  as_root tee /etc/systemd/system/docker-swarm-overlay-recovery.timer >/dev/null <<'EOF'
[Unit]
Description=Periodic Swarm overlay and NPM edge recovery

[Timer]
OnBootSec=90s
OnUnitActiveSec=2min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF

  as_root tee /etc/systemd/system/docker-swarm-boot-recovery.service >/dev/null <<'EOF'
[Unit]
Description=Boot-time Swarm overlay and NPM edge recovery
After=docker.service chrony-wait.service network-online.target
Wants=chrony-wait.service network-online.target
ConditionPathExists=/usr/bin/docker

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker_swarm_boot_recovery.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  as_root systemctl daemon-reload
  as_root systemctl enable docker-swarm-boot-recovery.service >/dev/null
  as_root systemctl enable docker-swarm-overlay-recovery.timer >/dev/null
  as_root systemctl restart docker-swarm-overlay-recovery.timer >/dev/null 2>&1 || true
}

install_docker_swarm_boot_recovery() {
  install_docker_swarm_overlay_recovery
}

install_eth0_watchdog() {
  local watchdog="${SCRIPT_DIR}/swarm_pi_eth0_watchdog.sh"
  if [[ ! -f "${watchdog}" ]]; then
    watchdog="/tmp/install/swarm_pi_eth0_watchdog.sh"
  fi
  [[ -f "${watchdog}" ]] || die "Missing swarm_pi_eth0_watchdog.sh beside ${SCRIPT_DIR}"

  local peer="192.168.1.120"
  if [[ "$(hostname -s 2>/dev/null || hostname)" == "swarm-cp-0" ]]; then
    peer="192.168.1.121"
  fi

  log "Installing swarm-pi-eth0-watchdog.timer (peer=${peer})"
  GATEWAY="${GATEWAY_NTP}" PEER="${peer}" as_root env GATEWAY="${GATEWAY_NTP}" PEER="${peer}" bash "${watchdog}" --install
}

reload_chrony() {
  if [[ "${RESTART_CHRONY}" == "0" ]]; then
    log "Skipping chrony restart (--no-restart-chrony)."
    return 0
  fi

  log "Saving fake-hwclock snapshot and reloading chrony"
  as_root fake-hwclock save force 2>/dev/null || true
  if systemctl is-active chrony.service >/dev/null 2>&1; then
    as_root chronyc reload sources 2>/dev/null || true
    as_root systemctl restart chrony.service
    as_root systemctl start chrony-wait.service || true
  fi
}

show_status() {
  echo "=== fake-hwclock ==="
  systemctl is-enabled fake-hwclock-load.service 2>/dev/null || true
  systemctl is-enabled fake-hwclock-save.service 2>/dev/null || true
  systemctl is-enabled fake-hwclock-save.timer 2>/dev/null || true
  systemctl is-enabled fake-hwclock-save-on-sync.service 2>/dev/null || true
  systemctl list-timers fake-hwclock-save.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
  cat /etc/fake-hwclock.data 2>/dev/null || true
  echo "=== chrony ==="
  timedatectl status 2>/dev/null || true
  chronyc sources -v 2>/dev/null | sed -n '1,20p' || true
  echo "=== docker guard ==="
  test -f /etc/systemd/system/docker.service.d/10-wait-for-time-sync.conf \
    && echo "docker time-sync drop-in: YES" || echo "docker time-sync drop-in: NO"
  systemctl is-enabled docker-swarm-boot-recovery.service 2>/dev/null \
    || echo "docker-swarm-boot-recovery: not installed"
  systemctl is-enabled docker-swarm-overlay-recovery.timer 2>/dev/null \
    || echo "docker-swarm-overlay-recovery: not installed"
  systemctl list-timers docker-swarm-overlay-recovery.timer --no-pager 2>/dev/null | sed -n '1,4p' || true
  systemctl is-enabled swarm-pi-eth0-watchdog.timer 2>/dev/null \
    || echo "swarm-pi-eth0-watchdog: not installed"
  if command -v docker >/dev/null 2>&1; then
    docker info --format 'Swarm={{.Swarm.LocalNodeState}}' 2>/dev/null || true
  fi
}

main() {
  parse_args "$@"
  init_privilege_command
  ensure_packages
  write_chrony_bootstrap_sources
  write_chrony_makestep
  write_fake_hwclock_plug_pull_hooks
  apply_docker_time_sync_guard
  install_docker_swarm_boot_recovery
  install_eth0_watchdog
  reload_chrony
  show_status
  log "Done."
}

main "$@"
