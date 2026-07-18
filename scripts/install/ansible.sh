#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()
PKG_MANAGER=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pkg.sh
. "${SCRIPT_DIR}/lib/pkg.sh"

ANSIBLE_PACKAGE="${ANSIBLE_PACKAGE:-ansible}"

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
  # sudo strips DEBIAN_FRONTEND by default; inject noninteractive env explicitly.
  "${SUDO_CMD[@]}" env \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    NEEDRESTART_MODE=a \
    NEEDRESTART_SUSPEND=1 \
    "$@"
}

ensure_supported_os() {
  [[ -f /etc/os-release ]] || die "/etc/os-release not found; unsupported host."
  PKG_MANAGER="$(detect_pkg_manager)"
}

install_ansible() {
  case "${PKG_MANAGER}" in
    apt)
      log "Refreshing apt metadata..."
      as_root apt-get update -y
      log "Installing ${ANSIBLE_PACKAGE}..."
      as_root apt-get install "${APT_OPTS[@]}" "${ANSIBLE_PACKAGE}"
      ;;
    pacman)
      log "Installing ansible via pacman..."
      pkg_install ansible
      ;;
    dnf)
      enable_epel_and_crb
      log "Installing ansible-core via dnf..."
      pkg_install ansible-core
      ;;
    *)
      die "Unsupported package manager for Ansible: ${PKG_MANAGER}."
      ;;
  esac
}

verify_install() {
  require_cmd ansible
  log "Installed $(ansible --version | head -n1)"
}

main() {
  if command -v ansible >/dev/null 2>&1; then
    log "ansible already installed: $(ansible --version | head -n1); skipping."
    return 0
  fi

  init_privilege_command
  ensure_supported_os
  install_ansible
  verify_install
  log "Done."
}

main "$@"
