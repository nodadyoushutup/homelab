#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()

MC_INSTALL_PATH="${MC_INSTALL_PATH:-/usr/local/bin/mc}"
MC_DOWNLOAD_URL="${MC_DOWNLOAD_URL:-}"

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

ensure_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "Unsupported OS: $(uname -s). Linux is required."
}

install_host_packages() {
  # Best-effort prerequisite install across common Linux package managers.
  if command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update -y
    as_root apt-get install "${APT_OPTS[@]}" "$@"
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y "$@"
  elif command -v yum >/dev/null 2>&1; then
    as_root yum install -y "$@"
  elif command -v zypper >/dev/null 2>&1; then
    as_root zypper install -y "$@"
  elif command -v pacman >/dev/null 2>&1; then
    as_root pacman -Syu --noconfirm "$@"
  else
    die "No supported package manager found to install: $*"
  fi
}

ensure_prereqs() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
  log "Installing curl prerequisite..."
  install_host_packages ca-certificates curl
}

resolve_arch() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) die "Unsupported architecture: ${arch}" ;;
  esac
}

install_mc() {
  local mc_arch url tmp
  mc_arch="$(resolve_arch)"
  url="${MC_DOWNLOAD_URL:-https://dl.min.io/client/mc/release/linux-${mc_arch}/mc}"
  tmp="$(mktemp)"

  log "Downloading MinIO client from ${url}"
  curl -fsSL --retry 3 "${url}" -o "${tmp}"
  as_root install -m 0755 -o root -g root -T "${tmp}" "${MC_INSTALL_PATH}"
  rm -f "${tmp}"
}

verify_install() {
  require_cmd mc
  log "Installed $(mc --version | head -n1)"
}

main() {
  if command -v mc >/dev/null 2>&1; then
    log "mc already installed: $(mc --version 2>/dev/null | head -n1 || true); skipping."
    return 0
  fi

  init_privilege_command
  ensure_linux
  ensure_prereqs
  install_mc
  verify_install
  log "Done."
}

main "$@"
