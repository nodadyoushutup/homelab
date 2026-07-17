#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SUDO_CMD=()
KUBECTL_VERSION="${KUBECTL_VERSION:-latest}" # latest or explicit (e.g. v1.32.2 / 1.32.2)
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
KUBECTL_BIN="kubectl"

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

ensure_linux() {
  [[ "$(uname -s)" == "Linux" ]] || die "Unsupported OS: $(uname -s). Linux is required."
}

detect_arch() {
  local machine
  machine="$(uname -m)"
  case "${machine}" in
    x86_64|amd64) KUBECTL_ARCH="amd64" ;;
    aarch64|arm64) KUBECTL_ARCH="arm64" ;;
    *) die "Unsupported architecture for kubectl: ${machine}" ;;
  esac
}

resolve_version() {
  if [[ "${KUBECTL_VERSION}" == "latest" ]]; then
    log "Resolving latest kubectl stable release..."
    KUBECTL_VERSION="$(curl -fsSL --retry 3 https://dl.k8s.io/release/stable.txt)"
  fi

  KUBECTL_VERSION="${KUBECTL_VERSION#v}"
  [[ -n "${KUBECTL_VERSION}" ]] || die "KUBECTL_VERSION resolved empty."
  KUBECTL_VERSION="v${KUBECTL_VERSION}"
}

install_kubectl() {
  local tmp_dir
  local bin_url
  local sum_url
  local expected

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  bin_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"
  sum_url="${bin_url}.sha256"

  log "Downloading ${bin_url}"
  curl -fL --retry 3 -o "${tmp_dir}/kubectl" "${bin_url}"

  log "Fetching checksum ${sum_url}"
  expected="$(curl -fsSL --retry 3 "${sum_url}")"
  [[ -n "${expected}" ]] || die "Could not fetch kubectl checksum."

  echo "${expected}  ${tmp_dir}/kubectl" | sha256sum -c - >/dev/null

  as_root install -m 0755 -d "${INSTALL_DIR}"
  as_root install -m 0755 -o root -g root -T "${tmp_dir}/kubectl" "${INSTALL_DIR}/${KUBECTL_BIN}"
  rm -rf "${tmp_dir}"
  trap - EXIT
}

verify_install() {
  require_cmd "${KUBECTL_BIN}"
  log "Installed $(${KUBECTL_BIN} version --client=true 2>/dev/null | head -n1 || true)"
}

already_installed() {
  if ! command -v "${KUBECTL_BIN}" >/dev/null 2>&1; then
    return 1
  fi

  # Unspecified/latest: any installed kubectl is enough for a fast re-run.
  if [[ "${KUBECTL_VERSION}" == "latest" || -z "${KUBECTL_VERSION}" ]]; then
    log "kubectl already installed: $(${KUBECTL_BIN} version --client=true 2>/dev/null | head -n1 || true); skipping."
    return 0
  fi

  local want have
  want="${KUBECTL_VERSION#v}"
  have="$(${KUBECTL_BIN} version --client=true -o yaml 2>/dev/null | awk '/gitVersion:/ { print $2; exit }' || true)"
  have="${have#v}"
  if [[ -n "${have}" && "${have}" == "${want}" ]]; then
    log "kubectl ${KUBECTL_VERSION} already installed; skipping."
    return 0
  fi
  return 1
}

main() {
  if already_installed; then
    return 0
  fi

  require_cmd curl
  require_cmd sha256sum

  init_privilege_command
  ensure_linux
  detect_arch
  resolve_version
  install_kubectl
  verify_install
  log "Done."
}

main "$@"
