#!/usr/bin/env bash
# Recover eth0 when the link stays up but LAN connectivity dies (switch/NIC wedge).
set -euo pipefail

log()  { echo "[eth0-watchdog] $*"; logger -t swarm-pi-eth0-watchdog "$*"; }
die()  { echo "[eth0-watchdog] ERROR: $*" >&2; logger -t swarm-pi-eth0-watchdog "ERROR: $*"; exit 1; }

IFACE="${IFACE:-eth0}"
GATEWAY="${GATEWAY:-192.168.1.1}"
PEER="${PEER:-192.168.1.120}"
PING_COUNT="${PING_COUNT:-3}"
PING_WAIT_SEC="${PING_WAIT_SEC:-2}"
STATE_DIR="/run/swarm-pi-eth0-watchdog"
FAIL_FILE="${STATE_DIR}/fail_count"
BOUNCE_FILE="${STATE_DIR}/last_bounce_epoch"
POST_BOUNCE_FAIL_FILE="${STATE_DIR}/post_bounce_fail_count"

usage() {
  cat <<EOF
Usage: swarm_pi_eth0_watchdog.sh [--install]

Ping GATEWAY and PEER on IFACE. After ${PING_COUNT} consecutive failures:
  1. Bounce ${IFACE} once (down/up + netplan/networkd reapply).
  2. If still failing after another ${PING_COUNT} checks, reboot.

Environment:
  IFACE, GATEWAY, PEER, PING_COUNT, PING_WAIT_SEC
EOF
}

init_privilege_command() {
  if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=()
  else
    command -v sudo >/dev/null 2>&1 || die "Run as root or install sudo."
    SUDO=(sudo)
  fi
}

as_root() {
  "${SUDO[@]}" "$@"
}

ping_target() {
  local target="$1"
  ping -I "${IFACE}" -c 1 -W "${PING_WAIT_SEC}" "${target}" >/dev/null 2>&1
}

lan_ok() {
  ping_target "${GATEWAY}" || return 1
  ping_target "${PEER}" || return 1
}

read_fail_count() {
  if [[ -f "${FAIL_FILE}" ]]; then
    cat "${FAIL_FILE}"
  else
    echo 0
  fi
}

write_fail_count() {
  as_root mkdir -p "${STATE_DIR}"
  echo "$1" | as_root tee "${FAIL_FILE}" >/dev/null
}

read_post_bounce_fail_count() {
  if [[ -f "${POST_BOUNCE_FAIL_FILE}" ]]; then
    cat "${POST_BOUNCE_FAIL_FILE}"
  else
    echo 0
  fi
}

write_post_bounce_fail_count() {
  as_root mkdir -p "${STATE_DIR}"
  echo "$1" | as_root tee "${POST_BOUNCE_FAIL_FILE}" >/dev/null
}

clear_state() {
  write_fail_count 0
  write_post_bounce_fail_count 0
}

bounce_iface() {
  local now
  now="$(date +%s)"
  if [[ -f "${BOUNCE_FILE}" ]]; then
    local last
    last="$(cat "${BOUNCE_FILE}")"
    if (( now - last < 300 )); then
      log "Skipping eth0 bounce; last bounce was $((now - last))s ago"
      return 0
    fi
  fi

  log "Bouncing ${IFACE} (link-up but LAN dead)"
  as_root ip link set "${IFACE}" down
  sleep 2
  as_root ip link set "${IFACE}" up
  if command -v netplan >/dev/null 2>&1; then
    as_root netplan apply >/dev/null 2>&1 || true
  fi
  if systemctl is-active systemd-networkd.service >/dev/null 2>&1; then
    as_root networkctl reconfigure "${IFACE}" >/dev/null 2>&1 || true
  fi
  echo "${now}" | as_root tee "${BOUNCE_FILE}" >/dev/null
  sleep 5
}

install_systemd() {
  init_privilege_command
  as_root install -d -m 0755 /usr/local/sbin
  as_root install -m 0755 "$0" /usr/local/sbin/swarm_pi_eth0_watchdog.sh

  as_root tee /etc/systemd/system/swarm-pi-eth0-watchdog.service >/dev/null <<EOF
[Unit]
Description=Swarm Pi eth0 LAN connectivity watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=GATEWAY=${GATEWAY}
Environment=PEER=${PEER}
Environment=IFACE=${IFACE}
ExecStart=/usr/local/sbin/swarm_pi_eth0_watchdog.sh
EOF

  as_root tee /etc/systemd/system/swarm-pi-eth0-watchdog.timer >/dev/null <<'EOF'
[Unit]
Description=Run Swarm Pi eth0 watchdog every minute

[Timer]
OnBootSec=3min
OnUnitActiveSec=1min
AccuracySec=15s
Persistent=true

[Install]
WantedBy=timers.target
EOF

  as_root systemctl daemon-reload
  as_root systemctl enable swarm-pi-eth0-watchdog.timer >/dev/null
  as_root systemctl restart swarm-pi-eth0-watchdog.timer
  log "Installed swarm-pi-eth0-watchdog.timer"
}

main() {
  if [[ "${1:-}" == "--install" ]]; then
    install_systemd
    exit 0
  fi

  init_privilege_command
  as_root mkdir -p "${STATE_DIR}"

  if ip link show "${IFACE}" 2>/dev/null | grep -q "state DOWN"; then
    log "${IFACE} is down; letting networkd/netplan handle it"
    write_fail_count 0
    exit 0
  fi

  if lan_ok; then
    clear_state
    exit 0
  fi

  local fails bounced_recently=0
  fails="$(read_fail_count)"
  fails=$((fails + 1))
  write_fail_count "${fails}"

  if [[ -f "${BOUNCE_FILE}" ]]; then
    local last now
    now="$(date +%s)"
    last="$(cat "${BOUNCE_FILE}")"
    if (( now - last < 600 )); then
      bounced_recently=1
    fi
  fi

  if (( bounced_recently )); then
    local post_fails
    post_fails="$(read_post_bounce_fail_count)"
    post_fails=$((post_fails + 1))
    write_post_bounce_fail_count "${post_fails}"
    log "LAN still dead after recent ${IFACE} bounce (${post_fails}/${PING_COUNT})"
    if (( post_fails >= PING_COUNT )); then
      log "Rebooting — ${IFACE} up but LAN dead after bounce"
      as_root systemctl reboot
    fi
    exit 0
  fi

  log "LAN check failed (${fails}/${PING_COUNT}) via ${IFACE} -> ${GATEWAY}, ${PEER}"

  if (( fails < PING_COUNT )); then
    exit 0
  fi

  bounce_iface
  write_fail_count 0
  write_post_bounce_fail_count 0

  if lan_ok; then
    log "LAN recovered after ${IFACE} bounce"
    clear_state
    exit 0
  fi

  write_post_bounce_fail_count 1
  log "LAN still dead immediately after ${IFACE} bounce"
}

main "$@"
