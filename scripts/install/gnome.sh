#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
APT_OPTS=(-y -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()
PKG_MANAGER=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pkg.sh
. "${SCRIPT_DIR}/lib/pkg.sh"

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

install_gnome_apt() {
  as_root apt-get update -y
  if apt-cache show ubuntu-desktop >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" ubuntu-desktop
  elif apt-cache show gnome-shell >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" gnome-shell gdm3
  else
    die "Could not find ubuntu-desktop or gnome-shell in apt repositories."
  fi
}

install_gnome_pacman() {
  pkg_install gnome gdm
}

install_gnome_dnf() {
  enable_epel_and_crb
  dnf_group_install "Workstation" 2>/dev/null \
    || dnf_group_install "GNOME Desktop Environment" 2>/dev/null \
    || pkg_install gnome-shell gdm
  pkg_install_best_effort gdm gnome-terminal
}

main() {
  if command -v gnome-shell >/dev/null 2>&1; then
    log "GNOME already installed ($(command -v gnome-shell)); skipping."
    return 0
  fi

  init_privilege_command
  PKG_MANAGER="$(detect_pkg_manager)"

  local display_manager="gdm"
  log "Installing GNOME via ${PKG_MANAGER}..."
  case "${PKG_MANAGER}" in
    apt) install_gnome_apt; display_manager="gdm3" ;;
    pacman) install_gnome_pacman ;;
    dnf) install_gnome_dnf ;;
    *) die "Unsupported package manager for GNOME: ${PKG_MANAGER}." ;;
  esac

  enable_display_manager "${display_manager}"

  if command -v gnome-shell >/dev/null 2>&1; then
    log "GNOME installed: $(command -v gnome-shell)"
  else
    warn "gnome-shell not found in PATH after install (may require login/session setup)."
  fi
  log "Done."
}

main "$@"
