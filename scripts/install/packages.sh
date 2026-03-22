#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()
PACKAGES=(qemu-guest-agent cloud-guest-utils)

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

main() {
  init_privilege_command
  require_cmd apt-get

  log "Installing apt packages: ${PACKAGES[*]}"
  as_root apt-get update -y
  as_root apt-get install "${APT_OPTS[@]}" "${PACKAGES[@]}"

  log "Done."
}

main "$@"
