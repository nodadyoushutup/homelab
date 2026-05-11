#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()
PACKAGES=(
  apt-transport-https
  curl
  gnupg
  lsb-release
  jq
  python3
  python3-pip
  python3-venv
  bat
  bridge-utils
  btop
  cloud-guest-utils
  dnsutils
  duf
  ethtool
  fd-find
  gh
  git
  htop
  ifupdown
  iotop
  iperf3
  iptables
  libvirt-clients
  libvirt-daemon-system
  lshw
  lsof
  make
  default-mysql-client
  nano
  net-tools
  netcat-openbsd
  neovim
  nfs-common
  nmap
  open-iscsi
  parted
  postgresql-client
  qemu-guest-agent
  ripgrep
  rsync
  screen
  smartmontools
  strace
  tcpdump
  tmux
  traceroute
  tree
  ufw
  unzip
  util-linux
  vim
  virtinst
  wget
  whois
  xorriso
  zip
)

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

  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Unsupported distro: ${ID:-unknown}. This script supports Debian/Ubuntu only." ;;
  esac
}

resolve_packages() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  case "${arch}" in
    amd64|x86_64)
      PACKAGES+=(cpu-checker qemu-kvm qemu-system-x86)
      ;;
    arm64|aarch64)
      # Match AMD64 baseline: system QEMU + KVM meta where apt provides it (host still supplies /dev/kvm).
      PACKAGES+=(cpu-checker qemu-kvm qemu-system-arm)
      ;;
    *)
      die "Unsupported architecture: ${arch}"
      ;;
  esac
}

main() {
  init_privilege_command
  ensure_supported_os
  require_cmd apt-get
  resolve_packages

  log "Installing apt packages: ${PACKAGES[*]}"
  as_root apt-get update -y
  as_root apt-get install "${APT_OPTS[@]}" "${PACKAGES[@]}"

  log "Done."
}

main "$@"
