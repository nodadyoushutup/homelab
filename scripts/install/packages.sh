#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pkg.sh
. "${SCRIPT_DIR}/lib/pkg.sh"

# Keep apt/debconf fully noninteractive (must also be passed through sudo; see as_root).
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
APT_OPTS=(
  -y
  --no-install-recommends
  -o Dpkg::Options::="--force-confdef"
  -o Dpkg::Options::="--force-confold"
  -o APT::Get::Assume-Yes=true
)
SUDO_CMD=()
PKG_MANAGER=""

# Full baseline for Debian/Ubuntu hosts.
APT_PACKAGES=(
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
  bind9-dnsutils
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

# Portable core set for non-apt package managers (names kept intentionally common).
CORE_PACKAGES=(
  ca-certificates
  curl
  git
  htop
  jq
  make
  python3
  rsync
  tmux
  tree
  unzip
  wget
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

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  else
    die "No supported package manager found (looked for apt-get, dnf, yum, zypper, pacman)."
  fi
  log "Detected package manager: ${PKG_MANAGER}"
}

resolve_apt_packages() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"

  case "${arch}" in
    amd64|x86_64)
      # qemu-kvm is a virtual package on newer Ubuntu and has no install candidate;
      # qemu-system-x86 provides the KVM-capable system emulator.
      APT_PACKAGES+=(cpu-checker qemu-system-x86)
      ;;
    arm64|aarch64)
      APT_PACKAGES+=(cpu-checker qemu-system-arm)
      ;;
    *)
      die "Unsupported architecture: ${arch}"
      ;;
  esac
}

apt_package_installed() {
  local package_name="$1"
  local installed
  if dpkg-query -W -f='${Status}\n' "${package_name}" 2>/dev/null \
    | grep -qx 'install ok installed'; then
    return 0
  fi
  # Transitional/virtual names (e.g. dnsutils -> bind9-dnsutils) may already be
  # satisfied even when the requested package name is not installed directly.
  installed="$(apt-cache policy "${package_name}" 2>/dev/null | awk '/Installed:/ { print $2; exit }')"
  [[ -n "${installed}" && "${installed}" != "(none)" ]]
}

filter_missing_apt_packages() {
  local package_name
  local missing=()
  for package_name in "${APT_PACKAGES[@]}"; do
    if apt_package_installed "${package_name}"; then
      continue
    fi
    missing+=("${package_name}")
  done
  APT_PACKAGES=("${missing[@]}")
}

preseed_apt_debconf() {
  # Answer known interactive package prompts up front (headless installs).
  log "Preseeding debconf answers for noninteractive package installs"
  as_root debconf-set-selections <<'EOF'
iperf3 iperf3/start_daemon boolean false
EOF
}

install_with_apt() {
  resolve_apt_packages
  filter_missing_apt_packages
  if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
    log "All requested apt packages already installed; skipping."
    return 0
  fi
  preseed_apt_debconf
  log "Installing missing apt packages: ${APT_PACKAGES[*]}"
  as_root apt-get update -y
  as_root apt-get install "${APT_OPTS[@]}" "${APT_PACKAGES[@]}"
}

rpm_package_installed() {
  local package_name="$1"
  rpm -q "${package_name}" >/dev/null 2>&1
}

filter_missing_rpm_packages() {
  local -n _pkgs_ref=$1
  local package_name
  local missing=()
  for package_name in "${_pkgs_ref[@]}"; do
    if rpm_package_installed "${package_name}"; then
      continue
    fi
    missing+=("${package_name}")
  done
  _pkgs_ref=("${missing[@]}")
}

install_core_with_dnf_or_yum() {
  local pm="$1"
  local pkgs=("${CORE_PACKAGES[@]}" python3-pip python3-virtualenv)
  filter_missing_rpm_packages pkgs
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log "All requested ${pm} packages already installed; skipping."
    return 0
  fi
  log "Installing missing ${pm} packages: ${pkgs[*]}"
  as_root "${pm}" install -y "${pkgs[@]}"
}

install_core_with_zypper() {
  local pkgs=("${CORE_PACKAGES[@]}" python3-pip python3-venv)
  filter_missing_rpm_packages pkgs
  if [[ ${#pkgs[@]} -eq 0 ]]; then
    log "All requested zypper packages already installed; skipping."
    return 0
  fi
  log "Installing missing zypper packages: ${pkgs[*]}"
  as_root zypper install -y "${pkgs[@]}"
}

# Full baseline for CentOS Stream / RHEL-family hosts (dnf), mapped from the apt
# set. EPEL + CRB are enabled first so the extended tools resolve.
install_with_dnf() {
  enable_epel_and_crb

  # Critical tools must install as a batch (fail fast if a core name is wrong).
  local core=(
    ca-certificates
    curl
    git
    jq
    make
    python3
    python3-pip
    rsync
    tmux
    tree
    unzip
    wget
    qemu-guest-agent
  )
  log "Installing core dnf packages: ${core[*]}"
  pkg_install "${core[@]}"

  # Extended baseline: install per-package so a name that is absent on this
  # release cannot abort the whole provisioning step.
  local extended=(
    bash-completion bat bind-utils bridge-utils btop duf ethtool fd-find gnupg2
    htop iotop iperf3 iptables iscsi-initiator-utils libvirt libvirt-client lshw
    lsof mariadb nano net-tools neovim nfs-utils nmap nmap-ncat parted
    postgresql qemu-kvm ripgrep screen smartmontools strace tcpdump traceroute
    vim-enhanced virt-install whois xorriso zip
  )
  log "Installing extended dnf packages (best-effort)"
  pkg_install_best_effort "${extended[@]}"
}

# Full baseline for Arch Linux hosts (pacman), mapped from the apt set.
install_with_pacman() {
  local core=(
    ca-certificates
    curl
    git
    jq
    make
    python
    python-pip
    rsync
    tmux
    tree
    unzip
    wget
    qemu-guest-agent
  )
  log "Installing core pacman packages: ${core[*]}"
  pkg_install "${core[@]}"

  local extended=(
    bash-completion bat bind bridge-utils btop duf ethtool fd gnupg htop iotop
    iperf3 iptables libisoburn libvirt lshw lsof mariadb-clients nano net-tools
    neovim nfs-utils nmap open-iscsi openbsd-netcat parted postgresql qemu-base
    ripgrep screen smartmontools strace tcpdump traceroute vim virt-install
    whois zip
  )
  log "Installing extended pacman packages (best-effort)"
  pkg_install_best_effort "${extended[@]}"
}

# Cloud images need the guest agent running so the hypervisor can manage them.
enable_qemu_guest_agent() {
  command -v systemctl >/dev/null 2>&1 || return 0
  pacman_package_installed qemu-guest-agent 2>/dev/null || rpm -q qemu-guest-agent >/dev/null 2>&1 || return 0
  as_root systemctl enable qemu-guest-agent >/dev/null 2>&1 || true
}

pacman_package_installed() {
  local package_name="$1"
  pacman -Q "${package_name}" >/dev/null 2>&1
}

main() {
  init_privilege_command
  ensure_linux
  detect_package_manager

  case "${PKG_MANAGER}" in
    apt) install_with_apt ;;
    dnf) install_with_dnf; enable_qemu_guest_agent ;;
    yum) install_core_with_dnf_or_yum yum ;;
    zypper) install_core_with_zypper ;;
    pacman) install_with_pacman; enable_qemu_guest_agent ;;
    *) die "Unhandled package manager: ${PKG_MANAGER}" ;;
  esac

  log "Done."
}

main "$@"
