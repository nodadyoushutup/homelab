#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
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
  # shellcheck disable=SC1091
  . /etc/os-release

  PKG_MANAGER="$(detect_pkg_manager)"
  DISTRO_ID="${ID:-}"
  DISTRO_CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "${DISTRO_CODENAME}" ]] && [[ "${ID:-}" == "ubuntu" ]] && [[ -n "${UBUNTU_CODENAME:-}" ]]; then
    DISTRO_CODENAME="${UBUNTU_CODENAME}"
  fi
}

install_docker_packages() {
  local profile="$1"
  case "${profile}" in
    full|cli) ;;
    *) die "Unsupported INSTALL_DOCKER_PROFILE='${profile}'. Use 'full' or 'cli'." ;;
  esac

  case "${PKG_MANAGER}" in
    apt) install_docker_apt "${profile}" ;;
    pacman) install_docker_pacman "${profile}" ;;
    dnf) install_docker_dnf "${profile}" ;;
    *) die "Unsupported package manager for Docker: ${PKG_MANAGER}." ;;
  esac
}

install_docker_apt() {
  local profile="$1"
  local arch
  local package_list=()

  [[ "${DISTRO_ID}" == "ubuntu" || "${DISTRO_ID}" == "debian" ]] \
    || die "apt Docker install supports Debian/Ubuntu only (got '${DISTRO_ID}')."
  [[ -n "${DISTRO_CODENAME}" ]] || die "Could not determine OS codename."

  arch="$(dpkg --print-architecture)"

  log "Installing Docker prerequisites..."
  as_root apt-get update -y -q
  as_root apt-get install "${APT_OPTS[@]}" ca-certificates curl gnupg lsb-release >/dev/null

  log "Configuring Docker apt repository..."
  as_root install -m 0755 -d /etc/apt/keyrings
  as_root curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
  as_root chmod a+r /etc/apt/keyrings/docker.asc

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${DISTRO_CODENAME} stable" \
    | as_root tee /etc/apt/sources.list.d/docker.list >/dev/null

  as_root apt-get update -y -q

  case "${profile}" in
    full) package_list=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin) ;;
    cli)  package_list=(docker-ce-cli docker-buildx-plugin docker-compose-plugin) ;;
  esac

  log "Installing Docker packages (profile=${profile})..."
  as_root apt-get install "${APT_OPTS[@]}" "${package_list[@]}" >/dev/null
}

install_docker_pacman() {
  local profile="$1"
  # Arch ships the client and daemon in one 'docker' package; compose/buildx are
  # separate plugins. The full/cli distinction only affects service enablement,
  # which is handled by enable_on_boot.
  log "Installing Docker packages via pacman (profile=${profile})..."
  pkg_install docker docker-compose docker-buildx
}

install_docker_dnf() {
  local profile="$1"
  local package_list=()

  log "Configuring Docker dnf repository..."
  pkg_as_root dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
  pkg_as_root dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1 \
    || pkg_as_root curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo

  case "${profile}" in
    full) package_list=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin) ;;
    cli)  package_list=(docker-ce-cli docker-buildx-plugin docker-compose-plugin) ;;
  esac

  log "Installing Docker packages via dnf (profile=${profile})..."
  pkg_install "${package_list[@]}"
}

ensure_user_access() {
  local target_user="$1"

  getent passwd "${target_user}" >/dev/null 2>&1 || die "User '${target_user}' does not exist."
  getent group docker >/dev/null 2>&1 || as_root groupadd docker

  if id -nG "${target_user}" | tr ' ' '\n' | grep -qx docker; then
    log "User '${target_user}' is already in docker group."
  else
    log "Adding '${target_user}' to docker group..."
    as_root usermod -aG docker "${target_user}"
    warn "Group membership changed for '${target_user}'. Re-login (or run 'newgrp docker') for current shell."
  fi
}

enable_on_boot() {
  if command -v systemctl >/dev/null 2>&1; then
    log "Enabling Docker to start at boot..."
    if ! as_root systemctl enable --now docker.service docker.socket >/dev/null 2>&1; then
      warn "Could not enable/start Docker with systemctl. If this host is a container without systemd, start dockerd via your runtime init."
    fi
    if ! as_root systemctl enable --now containerd.service >/dev/null 2>&1; then
      warn "Could not enable/start containerd.service with systemctl."
    fi
  else
    warn "systemctl not found; skipping boot-time enablement."
  fi
}

verify_docker() {
  local target_user="$1"
  local verify_cmd="docker version --format '{{.Server.Version}}' >/dev/null 2>&1"

  if [[ "${target_user}" == "$(id -un)" ]] && sh -lc "${verify_cmd}"; then
    log "Docker is installed and accessible for '${target_user}'."
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -u "${target_user}" -H sh -lc "${verify_cmd}"; then
    log "Docker is installed and accessible for '${target_user}'."
    return
  fi

  if [[ "$(id -u)" -eq 0 ]] && command -v runuser >/dev/null 2>&1 \
    && runuser -u "${target_user}" -- sh -lc "${verify_cmd}"; then
    log "Docker is installed and accessible for '${target_user}'."
    return
  fi

  if [[ "$(id -u)" -eq 0 ]] && command -v su >/dev/null 2>&1 \
    && su -s /bin/sh - "${target_user}" -c "${verify_cmd}" >/dev/null 2>&1; then
    log "Docker is installed and accessible for '${target_user}'."
    return
  fi

  warn "Docker installed, but current shell may not have refreshed group membership yet."
  warn "Open a new shell session and run: docker ps"
}

main() {
  require_cmd getent
  init_privilege_command
  ensure_supported_os

  local install_profile
  local configure_user
  local enable_service
  local verify_docker_install
  local target_user

  install_profile="${INSTALL_DOCKER_PROFILE:-full}"
  configure_user="${DOCKER_CONFIGURE_USER:-1}"
  enable_service="${DOCKER_ENABLE_SERVICE:-1}"
  verify_docker_install="${DOCKER_VERIFY:-1}"
  target_user="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"
  if [[ "${configure_user}" == "1" || "${verify_docker_install}" == "1" ]]; then
    [[ -n "${target_user}" ]] || die "Unable to determine target user. Set TARGET_USER."
  fi

  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version 2>/dev/null || true); skipping package install."
  else
    install_docker_packages "${install_profile}"
  fi

  if [[ "${configure_user}" == "1" ]]; then
    ensure_user_access "${target_user}"
  else
    log "Skipping docker-group user configuration (DOCKER_CONFIGURE_USER=${configure_user})."
  fi

  if [[ "${enable_service}" == "1" ]] && [[ "${install_profile}" == "full" ]]; then
    enable_on_boot
  else
    log "Skipping service enable/start (DOCKER_ENABLE_SERVICE=${enable_service}, INSTALL_DOCKER_PROFILE=${install_profile})."
  fi

  if [[ "${verify_docker_install}" == "1" ]]; then
    verify_docker "${target_user}"
  else
    log "Skipping runtime Docker verification (DOCKER_VERIFY=${verify_docker_install})."
  fi

  log "Done."
}

main "$@"
