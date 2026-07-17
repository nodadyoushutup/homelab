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

# KDE_PROFILE:
# - desktop (default): standard Ubuntu KDE desktop
# - minimal: Plasma desktop with display manager
# - full: full KDE package set
KDE_PROFILE="${KDE_PROFILE:-desktop}"

DISTRO_ID=""
declare -a KDE_PACKAGES=()

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

ensure_supported_os() {
  [[ -f /etc/os-release ]] || die "/etc/os-release not found; unsupported host."
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_ID="${ID:-unknown}"

  [[ "${DISTRO_ID}" == "ubuntu" ]] || die "Unsupported distro: ${DISTRO_ID}. This script supports Ubuntu only."
}

has_apt_package() {
  local package_name="$1"
  apt-cache show "${package_name}" >/dev/null 2>&1
}

configure_display_manager() {
  if ! command -v debconf-set-selections >/dev/null 2>&1; then
    warn "debconf-set-selections not found; skipping SDDM preseeding."
    return 0
  fi

  echo "sddm shared/default-x-display-manager select sddm" | as_root debconf-set-selections
}

resolve_kde_packages() {
  case "${KDE_PROFILE}" in
    desktop)
      if has_apt_package kubuntu-desktop; then
        KDE_PACKAGES=(kubuntu-desktop)
      elif has_apt_package kde-standard; then
        KDE_PACKAGES=(kde-standard)
      else
        die "Could not find kubuntu-desktop or kde-standard in apt repositories."
      fi
      ;;
    minimal)
      KDE_PACKAGES=(kde-plasma-desktop sddm)
      ;;
    full)
      if has_apt_package kde-full; then
        KDE_PACKAGES=(kde-full)
      elif has_apt_package kubuntu-desktop; then
        KDE_PACKAGES=(kubuntu-desktop)
      else
        die "Could not find kde-full or kubuntu-desktop in apt repositories."
      fi
      ;;
    *)
      die "Unsupported KDE_PROFILE='${KDE_PROFILE}'. Use: desktop, minimal, full."
      ;;
  esac
}

install_kde() {
  log "Refreshing apt metadata for KDE install..."
  as_root apt-get update -y
  resolve_kde_packages

  log "Configuring display manager preseeding..."
  configure_display_manager

  log "Installing KDE profile '${KDE_PROFILE}' on Ubuntu: ${KDE_PACKAGES[*]}"
  log "KDE installation can take a long time. Streaming apt output for progress..."
  as_root apt-get install "${APT_OPTS[@]}" "${KDE_PACKAGES[@]}"
}

verify_install() {
  if command -v plasmashell >/dev/null 2>&1; then
    log "KDE/Plasma shell detected: $(command -v plasmashell)"
  else
    warn "plasmashell not found in PATH after install (may require login/session setup)."
  fi

  local package_name
  for package_name in "${KDE_PACKAGES[@]}"; do
    local installed_version
    installed_version="$(dpkg-query -W -f='${Version}' "${package_name}" 2>/dev/null || true)"
    if [[ -n "${installed_version}" ]]; then
      log "Installed ${package_name}=${installed_version}"
    else
      warn "Package ${package_name} is not confirmed as installed."
    fi
  done
}

main() {
  if command -v plasmashell >/dev/null 2>&1; then
    log "KDE/Plasma already installed ($(command -v plasmashell)); skipping."
    return 0
  fi

  require_cmd apt-get
  require_cmd apt-cache
  require_cmd dpkg-query
  require_cmd grep

  init_privilege_command
  ensure_supported_os

  install_kde
  verify_install
  log "Done."
}

main "$@"
