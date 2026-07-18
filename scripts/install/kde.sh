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

install_kde_apt() {
  as_root apt-get update -y
  # SDDM is the KDE display manager; preseed so its debconf prompt is silent.
  if command -v debconf-set-selections >/dev/null 2>&1; then
    echo "sddm shared/default-x-display-manager select sddm" | as_root debconf-set-selections
  fi
  if apt-cache show kubuntu-desktop >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" kubuntu-desktop
  elif apt-cache show kde-standard >/dev/null 2>&1; then
    as_root apt-get install "${APT_OPTS[@]}" kde-standard sddm
  else
    die "Could not find kubuntu-desktop or kde-standard in apt repositories."
  fi
}

install_kde_pacman() {
  pkg_install plasma-meta sddm konsole
}

install_kde_dnf() {
  enable_epel_and_crb
  dnf_group_install "KDE Plasma Workspaces"
  pkg_install_best_effort sddm konsole
}

main() {
  if command -v plasmashell >/dev/null 2>&1; then
    log "KDE/Plasma already installed ($(command -v plasmashell)); skipping."
    return 0
  fi

  init_privilege_command
  PKG_MANAGER="$(detect_pkg_manager)"

  log "Installing KDE Plasma via ${PKG_MANAGER}..."
  case "${PKG_MANAGER}" in
    apt) install_kde_apt ;;
    pacman) install_kde_pacman ;;
    dnf) install_kde_dnf ;;
    *) die "Unsupported package manager for KDE: ${PKG_MANAGER}." ;;
  esac

  enable_display_manager sddm

  if command -v plasmashell >/dev/null 2>&1; then
    log "KDE/Plasma installed: $(command -v plasmashell)"
  else
    warn "plasmashell not found in PATH after install (may require login/session setup)."
  fi
  log "Done."
}

main "$@"
