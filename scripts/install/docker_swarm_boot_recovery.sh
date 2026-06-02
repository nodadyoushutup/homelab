#!/usr/bin/env bash
# One-shot boot recovery: restart Docker if Swarm is stuck in error after NTP sync.
set -euo pipefail

log() { echo "[docker-swarm-boot-recovery] $*"; logger -t docker-swarm-boot-recovery "$*"; }

if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi

if ! systemctl is-active docker.service >/dev/null 2>&1; then
  exit 0
fi

swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
if [[ "${swarm_state}" != "error" ]]; then
  exit 0
fi

if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)" != "yes" ]]; then
  log "Swarm=error but NTP not synchronized yet; leaving docker alone"
  exit 0
fi

log "Swarm=error with NTP synchronized; restarting docker.service"
systemctl restart docker.service

sleep 3
swarm_state="$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || true)"
log "After restart: Swarm=${swarm_state:-unknown}"
