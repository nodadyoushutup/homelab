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

install_xfce_apt() {
  as_root apt-get update -y
  if apt-cache show xubuntu-desktop >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" xubuntu-desktop
  elif apt-cache show xfce4 >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" xfce4 xfce4-goodies lightdm
  else
    die "Could not find xubuntu-desktop or xfce4 in apt repositories."
  fi
}

install_xfce_pacman() {
  pkg_install xfce4 xfce4-goodies lightdm lightdm-gtk-greeter
}

install_xfce_dnf() {
  enable_epel_and_crb
  dnf_group_install "Xfce" 2>/dev/null \
    || dnf_group_install "Xfce Desktop" 2>/dev/null \
    || pkg_install_best_effort @xfce
  pkg_install_best_effort lightdm lightdm-gtk
}

main() {
  if command -v xfce4-session >/dev/null 2>&1; then
    log "XFCE already installed ($(command -v xfce4-session)); skipping."
    return 0
  fi

  init_privilege_command
  PKG_MANAGER="$(detect_pkg_manager)"

  log "Installing XFCE via ${PKG_MANAGER}..."
  case "${PKG_MANAGER}" in
    apt) install_xfce_apt ;;
    pacman) install_xfce_pacman ;;
    dnf) install_xfce_dnf ;;
    *) die "Unsupported package manager for XFCE: ${PKG_MANAGER}." ;;
  esac

  enable_display_manager lightdm

  if command -v xfce4-session >/dev/null 2>&1; then
    log "XFCE installed: $(command -v xfce4-session)"
  else
    warn "xfce4-session not found in PATH after install (may require login/session setup)."
  fi
  log "Done."
}

main "$@"
