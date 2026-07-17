#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
APT_OPTS=(-y -q --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
SUDO_CMD=()

PACKER_VERSION="${PACKER_VERSION:-}" # empty = install current repo version, set for direct release install
INSTALL_DIR="/usr/local/bin"
PACKER_BIN="packer"

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
  case "${ID:-}" in
    ubuntu|debian) ;;
    *) die "Unsupported distro: ${ID:-unknown}. This script supports Debian/Ubuntu only." ;;
  esac

  DISTRO_ID="${ID}"
  OS_CODENAME="${VERSION_CODENAME:-}"
  if [[ -z "${OS_CODENAME}" ]] && [[ "${ID}" == "ubuntu" ]] && [[ -n "${UBUNTU_CODENAME:-}" ]]; then
    OS_CODENAME="${UBUNTU_CODENAME}"
  fi

  ARCH_DEB="$(dpkg --print-architecture || true)"
  case "${ARCH_DEB}" in
    amd64) REL_ARCH="amd64" ;;
    arm64) REL_ARCH="arm64" ;;
    armhf|armel) REL_ARCH="arm" ;;
    *) REL_ARCH="" ;;
  esac
}

have_url() {
  curl -fsSL --retry 3 --max-time 10 -o /dev/null "$1"
}

choose_repo_codename() {
  local codename
  for codename in "${OS_CODENAME:-}" noble jammy focal bullseye bookworm; do
    [[ -n "${codename}" ]] || continue
    if have_url "https://apt.releases.hashicorp.com/dists/${codename}/Release"; then
      echo "${codename}"
      return 0
    fi
  done
  echo ""
}

install_hashicorp_repo() {
  log "Installing HashiCorp apt repository..."
  as_root apt-get update -y -q
  as_root apt-get install "${APT_OPTS[@]}" ca-certificates curl gnupg lsb-release apt-transport-https >/dev/null

  as_root install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/hashicorp.gpg ]]; then
    curl -fsSL --retry 3 https://apt.releases.hashicorp.com/gpg \
      | as_root gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
    as_root chmod a+r /etc/apt/keyrings/hashicorp.gpg
  fi

  local codename
  codename="$(choose_repo_codename)"
  [[ -n "${codename}" ]] || return 1

  echo "deb [arch=${ARCH_DEB} signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${codename} main" \
    | as_root tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  return 0
}

latest_packer_version() {
  if command -v jq >/dev/null 2>&1; then
    curl -fsSL --retry 3 https://releases.hashicorp.com/packer/index.json \
      | jq -r '.versions | keys | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".")|map(tonumber)) | last'
  else
    curl -fsSL --retry 3 https://releases.hashicorp.com/packer/index.json \
      | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -V | tail -n1
  fi
}

install_packer_via_releases() {
  [[ -n "${REL_ARCH}" ]] || die "Direct Packer releases do not support architecture '${ARCH_DEB}'."

  local target_version="${PACKER_VERSION:-}"
  if [[ -z "${target_version}" ]]; then
    log "Discovering latest Packer release..."
    target_version="$(latest_packer_version)"
    [[ -n "${target_version}" ]] || die "Could not determine latest Packer release."
  fi

  local zip_name="packer_${target_version}_linux_${REL_ARCH}.zip"
  local base_url="https://releases.hashicorp.com/packer/${target_version}"
  local zip_url="${base_url}/${zip_name}"
  local sums_url="${base_url}/packer_${target_version}_SHA256SUMS"

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  require_cmd sha256sum
  if ! command -v unzip >/dev/null 2>&1; then
    as_root apt-get update -y -q
    as_root apt-get install "${APT_OPTS[@]}" unzip >/dev/null
  fi

  log "Downloading Packer ${target_version} release..."
  curl -fL --retry 3 -o "${tmp_dir}/${zip_name}" "${zip_url}"
  curl -fL --retry 3 -o "${tmp_dir}/SHA256SUMS" "${sums_url}"

  local expected_sum
  expected_sum="$(grep " ${zip_name}\$" "${tmp_dir}/SHA256SUMS" | awk '{print $1}')" || true
  [[ -n "${expected_sum}" ]] || die "Could not find checksum for ${zip_name}."
  echo "${expected_sum}  ${tmp_dir}/${zip_name}" | sha256sum -c - >/dev/null

  unzip -q -o "${tmp_dir}/${zip_name}" -d "${tmp_dir}"
  as_root install -m 0755 -o root -g root -T "${tmp_dir}/${PACKER_BIN}" "${INSTALL_DIR}/${PACKER_BIN}"
  rm -rf "${tmp_dir}"
}

install_packer() {
  if [[ -n "${PACKER_VERSION}" ]]; then
    log "PACKER_VERSION set (${PACKER_VERSION}); installing via direct release."
    install_packer_via_releases
    return 0
  fi

  if install_hashicorp_repo; then
    as_root apt-get update -y -q
    if as_root apt-get install "${APT_OPTS[@]}" packer >/dev/null; then
      return 0
    fi
    warn "Packer apt install failed; falling back to direct release."
  else
    warn "No suitable HashiCorp apt codename found; falling back to direct release."
  fi

  install_packer_via_releases
}

has_apt_package() {
  local package_name="$1"
  local candidate
  # Reject virtual packages with no install candidate (e.g. qemu-kvm on Resolute).
  candidate="$(apt-cache policy "${package_name}" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')"
  [[ -n "${candidate}" && "${candidate}" != "(none)" ]]
}

install_qemu_kvm_dependencies() {
  if command -v qemu-img >/dev/null 2>&1 \
    && command -v xorriso >/dev/null 2>&1 \
    && command -v qemu-system-x86_64 >/dev/null 2>&1 \
    && command -v qemu-system-aarch64 >/dev/null 2>&1; then
    log "QEMU/KVM dependencies already installed; skipping."
    return 0
  fi

  log "Installing QEMU/KVM dependencies..."
  as_root apt-get update -y -q

  local packages=(qemu-utils xorriso)

  # x86_64 system emulator for amd64 image builds.
  if has_apt_package qemu-system-x86; then
    packages+=(qemu-system-x86)
  elif has_apt_package qemu-system; then
    packages+=(qemu-system)
  else
    die "Could not find qemu-system-x86 or qemu-system in apt repositories."
  fi

  # aarch64 system emulator for arm64 image builds.
  if has_apt_package qemu-system-arm; then
    packages+=(qemu-system-arm)
  elif has_apt_package qemu-system-misc; then
    packages+=(qemu-system-misc)
  elif ! has_apt_package qemu-system; then
    die "Could not find qemu-system-arm/qemu-system-misc (or all-target qemu-system) in apt repositories."
  fi

  log "Installing required QEMU packages: ${packages[*]}"
  as_root apt-get install "${APT_OPTS[@]}" "${packages[@]}" >/dev/null

  # Optional extras — install independently so one missing/virtual package cannot
  # fail the whole Packer dependency step. Do not include qemu-kvm (virtual on
  # modern Ubuntu; qemu-system-* already provides KVM-capable emulators).
  local optional_packages=(
    qemu-efi-aarch64
    qemu-efi-aarch64-sb
    libvirt-daemon-system
    libvirt-clients
    bridge-utils
    cpu-checker
  )
  local package_name
  for package_name in "${optional_packages[@]}"; do
    if ! has_apt_package "${package_name}"; then
      warn "Optional package not installable via apt: ${package_name}"
      continue
    fi
    if as_root apt-get install "${APT_OPTS[@]}" "${package_name}" >/dev/null; then
      log "Installed optional package: ${package_name}"
    else
      warn "Optional package install failed: ${package_name}"
    fi
  done
}

configure_kvm_access() {
  local target_user="$1"
  local changed_membership=0

  if [[ ! -e /dev/kvm ]]; then
    warn "/dev/kvm not found; KVM acceleration may be unavailable on this host."
    return 0
  fi

  getent passwd "${target_user}" >/dev/null 2>&1 || die "User '${target_user}' does not exist."

  local group_name
  for group_name in kvm libvirt; do
    if ! getent group "${group_name}" >/dev/null 2>&1; then
      warn "Group '${group_name}' does not exist; skipping user membership."
      continue
    fi

    if id -nG "${target_user}" | tr ' ' '\n' | grep -qx "${group_name}"; then
      log "User '${target_user}' already in '${group_name}' group."
      continue
    fi

    log "Adding '${target_user}' to '${group_name}' group..."
    as_root usermod -aG "${group_name}" "${target_user}"
    changed_membership=1
  done

  if [[ "${changed_membership}" -eq 1 ]]; then
    warn "Group membership updated for '${target_user}'. Re-login is required for current shell."
  fi
}

verify_install() {
  command -v "${PACKER_BIN}" >/dev/null 2>&1 || die "Packer not found after installation."
  command -v qemu-img >/dev/null 2>&1 || die "qemu-img not found after installation."
  command -v xorriso >/dev/null 2>&1 || die "xorriso not found after installation."

  if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    log "qemu-system-x86_64 is installed."
  else
    die "qemu-system-x86_64 not found in PATH after install."
  fi

  if command -v qemu-system-aarch64 >/dev/null 2>&1; then
    log "qemu-system-aarch64 is installed."
  else
    die "qemu-system-aarch64 not found in PATH after install."
  fi

  if [[ -e /dev/kvm ]]; then
    log "/dev/kvm is present."
  else
    warn "/dev/kvm is not present. KVM acceleration is unavailable."
  fi

  log "Installed $(${PACKER_BIN} version | head -n1)"
}

packer_stack_installed() {
  command -v "${PACKER_BIN}" >/dev/null 2>&1 \
    && command -v qemu-img >/dev/null 2>&1 \
    && command -v xorriso >/dev/null 2>&1 \
    && command -v qemu-system-x86_64 >/dev/null 2>&1 \
    && command -v qemu-system-aarch64 >/dev/null 2>&1
}

main() {
  require_cmd apt-get
  require_cmd curl
  require_cmd dpkg
  require_cmd getent
  require_cmd grep

  init_privilege_command
  ensure_supported_os

  local configure_user
  local target_user
  configure_user="${PACKER_CONFIGURE_USER:-1}"
  target_user="${TARGET_USER:-${SUDO_USER:-${USER:-}}}"

  if packer_stack_installed; then
    log "Packer and QEMU dependencies already installed ($(${PACKER_BIN} version | head -n1)); skipping package/binary installs."
  else
    if command -v "${PACKER_BIN}" >/dev/null 2>&1; then
      log "Packer already installed ($(${PACKER_BIN} version | head -n1)); skipping Packer download/install."
    else
      install_packer
    fi
    install_qemu_kvm_dependencies
  fi

  if [[ "${configure_user}" == "1" ]]; then
    [[ -n "${target_user}" ]] || die "Unable to determine target user. Set TARGET_USER."
    configure_kvm_access "${target_user}"
  else
    log "Skipping user group configuration (PACKER_CONFIGURE_USER=${configure_user})."
  fi

  verify_install
  log "Done."
}

main "$@"
