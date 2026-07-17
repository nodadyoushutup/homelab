#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SUDO_CMD=()
K9S_VERSION="${K9S_VERSION:-latest}" # latest or explicit (e.g. v0.50.7 / 0.50.7)
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
K9S_BIN="k9s"

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
    x86_64|amd64) K9S_ARCH="amd64" ;;
    aarch64|arm64) K9S_ARCH="arm64" ;;
    armv7l|armv7) K9S_ARCH="arm" ;;
    *) die "Unsupported architecture for k9s: ${machine}" ;;
  esac
}

resolve_version() {
  if [[ "${K9S_VERSION}" == "latest" ]]; then
    log "Resolving latest k9s release..."
    K9S_VERSION="$(
      curl -fsSL --retry 3 https://api.github.com/repos/derailed/k9s/releases/latest \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1
    )"
  fi

  K9S_VERSION="${K9S_VERSION#v}"
  [[ -n "${K9S_VERSION}" ]] || die "K9S_VERSION resolved empty."
  K9S_VERSION="v${K9S_VERSION}"
}

install_k9s() {
  local tmp_dir
  local tarball
  local url

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  tarball="k9s_Linux_${K9S_ARCH}.tar.gz"
  url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/${tarball}"

  log "Downloading ${url}"
  curl -fL --retry 3 -o "${tmp_dir}/${tarball}" "${url}"

  tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}"
  [[ -f "${tmp_dir}/k9s" ]] || die "k9s binary not found in extracted archive."

  as_root install -m 0755 -d "${INSTALL_DIR}"
  as_root install -m 0755 -o root -g root -T "${tmp_dir}/k9s" "${INSTALL_DIR}/${K9S_BIN}"
  rm -rf "${tmp_dir}"
  trap - EXIT
}

verify_install() {
  require_cmd "${K9S_BIN}"
  log "Installed $(${K9S_BIN} version --short 2>/dev/null | head -n1 || ${K9S_BIN} version 2>/dev/null | head -n1 || true)"
}

already_installed() {
  if ! command -v "${K9S_BIN}" >/dev/null 2>&1; then
    return 1
  fi

  if [[ "${K9S_VERSION}" == "latest" || -z "${K9S_VERSION}" ]]; then
    log "k9s already installed: $(${K9S_BIN} version --short 2>/dev/null | head -n1 || ${K9S_BIN} version 2>/dev/null | head -n1 || true); skipping."
    return 0
  fi

  local want have
  want="${K9S_VERSION#v}"
  have="$(${K9S_BIN} version --short 2>/dev/null | head -n1 || true)"
  have="${have#v}"
  if [[ -n "${have}" && "${have}" == "${want}" ]]; then
    log "k9s v${want} already installed; skipping."
    return 0
  fi
  return 1
}

main() {
  if already_installed; then
    return 0
  fi

  require_cmd curl
  require_cmd tar

  init_privilege_command
  ensure_linux
  detect_arch
  resolve_version
  install_k9s
  verify_install
  log "Done."
}

main "$@"
