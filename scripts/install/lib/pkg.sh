# shellcheck shell=bash
# Shared package-manager helpers for scripts/install/*.sh.
#
# Source from a script that lives in scripts/install/ with:
#   SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
#   . "${SCRIPT_DIR}/lib/pkg.sh"
#
# The whole scripts/install directory is copied to the guest during image
# builds, so this relative source path is always available.

# Provide logging only if the caller has not already defined it.
if ! declare -F log >/dev/null 2>&1; then log() { echo "[INFO] $*"; }; fi
if ! declare -F warn >/dev/null 2>&1; then warn() { echo "[WARN] $*" >&2; }; fi
if ! declare -F die >/dev/null 2>&1; then die() { echo "[ERROR] $*" >&2; exit 1; }; fi

PKG_MANAGER="${PKG_MANAGER:-}"
OS_ID="${OS_ID:-}"
PKG_SUDO=()
PKG_SUDO_INIT=0

# Detect and cache the OS ID from /etc/os-release (e.g. ubuntu, debian, arch, centos).
os_id() {
  if [[ -z "${OS_ID}" && -r /etc/os-release ]]; then
    OS_ID="$(. /etc/os-release && echo "${ID:-}")"
  fi
  echo "${OS_ID}"
}

# Detect and cache the native package manager. Supported: apt, dnf, pacman.
detect_pkg_manager() {
  if [[ -z "${PKG_MANAGER}" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER="dnf"
    elif command -v pacman >/dev/null 2>&1; then
      PKG_MANAGER="pacman"
    else
      die "No supported package manager found (looked for apt-get, dnf, pacman)."
    fi
  fi
  echo "${PKG_MANAGER}"
}

pkg_init_privilege() {
  if [[ "$(id -u)" -eq 0 ]]; then
    PKG_SUDO=()
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required when running unprivileged."
    PKG_SUDO=(sudo)
  fi
  PKG_SUDO_INIT=1
}

# Run a command as root, injecting the noninteractive env that sudo strips.
pkg_as_root() {
  [[ "${PKG_SUDO_INIT}" -eq 1 ]] || pkg_init_privilege
  "${PKG_SUDO[@]}" env \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    NEEDRESTART_MODE=a \
    NEEDRESTART_SUSPEND=1 \
    "$@"
}

# Refresh package metadata (best-effort; never fatal on its own).
pkg_update() {
  local pm
  pm="$(detect_pkg_manager)"
  case "${pm}" in
    apt) pkg_as_root apt-get update -y -q ;;
    dnf) pkg_as_root dnf -y -q makecache || true ;;
    pacman) pkg_as_root pacman -Sy --noconfirm ;;
  esac
}

# Install one or more packages (fails if the batch install fails).
pkg_install() {
  local pm
  pm="$(detect_pkg_manager)"
  case "${pm}" in
    apt)
      pkg_as_root apt-get install -y -q --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" \
        "$@"
      ;;
    dnf) pkg_as_root dnf install -y "$@" ;;
    pacman) pkg_as_root pacman -S --needed --noconfirm "$@" ;;
  esac
}

# Install each package independently, warning (not failing) on any miss. Use for
# large cross-distro baselines where a single wrong name must not abort the run.
pkg_install_best_effort() {
  local package_name
  for package_name in "$@"; do
    if pkg_installed "${package_name}"; then
      continue
    fi
    if pkg_install "${package_name}" >/dev/null 2>&1; then
      log "Installed ${package_name}"
    else
      warn "Package not installable on this distro; skipping: ${package_name}"
    fi
  done
}

pkg_installed() {
  local pm package_name
  pm="$(detect_pkg_manager)"
  package_name="$1"
  case "${pm}" in
    apt) dpkg-query -W -f='${Status}\n' "${package_name}" 2>/dev/null | grep -qx 'install ok installed' ;;
    dnf) rpm -q "${package_name}" >/dev/null 2>&1 ;;
    pacman) pacman -Q "${package_name}" >/dev/null 2>&1 ;;
  esac
}

# Enable EPEL + CRB (CodeReady Builder) on dnf-based hosts. Many baseline tools
# (htop, ripgrep, neovim, ...) live in these repos on CentOS Stream / RHEL.
enable_epel_and_crb() {
  local pm
  pm="$(detect_pkg_manager)"
  [[ "${pm}" == "dnf" ]] || return 0

  pkg_as_root dnf install -y dnf-plugins-core >/dev/null 2>&1 || true

  if ! rpm -q epel-release >/dev/null 2>&1; then
    log "Enabling EPEL repository"
    pkg_as_root dnf install -y epel-release >/dev/null 2>&1 \
      || pkg_as_root dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm >/dev/null 2>&1 \
      || warn "Could not enable EPEL; some packages may be unavailable."
  fi

  # CRB is named 'crb' on Stream 9/10 and 'powertools' on older releases.
  pkg_as_root dnf config-manager --set-enabled crb >/dev/null 2>&1 \
    || pkg_as_root dnf config-manager --set-enabled powertools >/dev/null 2>&1 \
    || true
}

# Install a dnf package group (handles both dnf4 and dnf5 subcommand spelling).
dnf_group_install() {
  pkg_as_root dnf group install -y "$@" 2>/dev/null \
    || pkg_as_root dnf groupinstall -y "$@"
}

# Enable a display manager and boot to the graphical target (systemd hosts).
enable_display_manager() {
  local dm="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not found; cannot enable ${dm} or set graphical target."
    return 0
  fi
  pkg_as_root systemctl enable "${dm}.service" >/dev/null 2>&1 \
    || warn "Could not enable ${dm}.service."
  pkg_as_root systemctl set-default graphical.target >/dev/null 2>&1 \
    || warn "Could not set default target to graphical.target."
}
