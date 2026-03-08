#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()

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

detect_os() {
  [[ -f /etc/os-release ]] || die "/etc/os-release not found; unsupported host."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
}

install_debian_packages() {
  local packages=("$@")
  [[ ${#packages[@]} -gt 0 ]] || die "No packages provided."

  log "Installing packages via apt: ${packages[*]}"
  as_root apt-get update -y -q
  as_root apt-get install "${APT_OPTS[@]}" "${packages[@]}" >/dev/null
}

main() {
  init_privilege_command
  detect_os

  if [[ "$#" -eq 0 ]]; then
    die "Usage: $0 <package> [package ...]"
  fi

  case "${OS_ID}" in
    ubuntu|debian)
      install_debian_packages "$@"
      ;;
    *)
      die "Unsupported OS: ${OS_ID}. Future versions can add non-apt installers."
      ;;
  esac

  log "Done."
}

main "$@"
