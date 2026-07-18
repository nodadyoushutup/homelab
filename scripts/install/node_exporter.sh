#!/usr/bin/env bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

SUDO_CMD=()
PKG_MANAGER=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pkg.sh
. "${SCRIPT_DIR}/lib/pkg.sh"

NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION:-latest}"
NODE_EXPORTER_INSTALL_DIR="${NODE_EXPORTER_INSTALL_DIR:-/usr/local/bin}"
NODE_EXPORTER_BINARY_PATH="${NODE_EXPORTER_INSTALL_DIR}/node_exporter"
NODE_EXPORTER_SERVICE_FILE="${NODE_EXPORTER_SERVICE_FILE:-/etc/systemd/system/node_exporter.service}"
NODE_EXPORTER_SERVICE_NAME="$(basename "${NODE_EXPORTER_SERVICE_FILE}")"
NODE_EXPORTER_USER="${NODE_EXPORTER_USER:-node_exporter}"
NODE_EXPORTER_GROUP="${NODE_EXPORTER_GROUP:-node_exporter}"
NODE_EXPORTER_WEB_LISTEN_ADDRESS="${NODE_EXPORTER_WEB_LISTEN_ADDRESS:-:9100}"
NODE_EXPORTER_WEB_TELEMETRY_PATH="${NODE_EXPORTER_WEB_TELEMETRY_PATH:-/metrics}"
NODE_EXPORTER_EXTRA_ARGS="${NODE_EXPORTER_EXTRA_ARGS:-}"

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -q --no-install-recommends -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

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

detect_arch() {
  local machine
  machine="$(uname -m)"

  case "${machine}" in
    x86_64|amd64) NODE_EXPORTER_ARCH="amd64" ;;
    aarch64|arm64) NODE_EXPORTER_ARCH="arm64" ;;
    armv7l|armv7) NODE_EXPORTER_ARCH="armv7" ;;
    i386|i686) NODE_EXPORTER_ARCH="386" ;;
    ppc64le) NODE_EXPORTER_ARCH="ppc64le" ;;
    s390x) NODE_EXPORTER_ARCH="s390x" ;;
    riscv64) NODE_EXPORTER_ARCH="riscv64" ;;
    *)
      die "Unsupported architecture: ${machine}"
      ;;
  esac
}

ensure_supported_os() {
  [[ -f /etc/os-release ]] || die "/etc/os-release not found; unsupported host."
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  PKG_MANAGER="$(detect_pkg_manager)"
}

ensure_prerequisites() {
  local missing=()
  local cmd

  for cmd in curl tar install getent; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  log "Installing prerequisites via ${PKG_MANAGER}: ${missing[*]}"
  case "${PKG_MANAGER}" in
    apt) pkg_install curl tar coreutils passwd >/dev/null ;;
    pacman) pkg_install curl tar coreutils shadow >/dev/null ;;
    dnf) pkg_install curl tar coreutils shadow-utils >/dev/null ;;
    *) die "Missing required commands and no supported package manager: ${missing[*]}" ;;
  esac
}

resolve_version() {
  if [[ "${NODE_EXPORTER_VERSION}" != "latest" ]]; then
    NODE_EXPORTER_VERSION="${NODE_EXPORTER_VERSION#v}"
    [[ -n "${NODE_EXPORTER_VERSION}" ]] || die "NODE_EXPORTER_VERSION is empty."
    return 0
  fi

  log "Resolving latest node_exporter version..."
  NODE_EXPORTER_VERSION="$(
    curl -fsSL "https://api.github.com/repos/prometheus/node_exporter/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
      | head -n1
  )"
  [[ -n "${NODE_EXPORTER_VERSION}" ]] || die "Unable to resolve latest node_exporter version."
}

installed_version() {
  if [[ ! -x "${NODE_EXPORTER_BINARY_PATH}" ]]; then
    return 1
  fi

  "${NODE_EXPORTER_BINARY_PATH}" --version 2>/dev/null \
    | sed -n 's/^node_exporter, version \([^ ]*\).*/\1/p' \
    | head -n1
}

install_node_exporter_binary() {
  local current_version
  current_version="$(installed_version || true)"
  if [[ -n "${current_version}" && "${current_version}" == "${NODE_EXPORTER_VERSION}" ]]; then
    log "node_exporter ${NODE_EXPORTER_VERSION} already installed at ${NODE_EXPORTER_BINARY_PATH}."
    return 0
  fi

  local release_name="node_exporter-${NODE_EXPORTER_VERSION}.linux-${NODE_EXPORTER_ARCH}"
  local tarball="${release_name}.tar.gz"
  local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  log "Downloading ${url}"
  curl -fL --retry 3 --retry-delay 2 -o "${tmp_dir}/${tarball}" "${url}"
  tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}"

  as_root install -m 0755 -d "${NODE_EXPORTER_INSTALL_DIR}"
  as_root install -m 0755 -o root -g root \
    "${tmp_dir}/${release_name}/node_exporter" "${NODE_EXPORTER_BINARY_PATH}"
  rm -rf "${tmp_dir}"

  log "Installed node_exporter ${NODE_EXPORTER_VERSION} to ${NODE_EXPORTER_BINARY_PATH}"
}

ensure_service_account() {
  local nologin_shell="/usr/sbin/nologin"
  if [[ ! -x "${nologin_shell}" ]]; then
    nologin_shell="/usr/bin/false"
  fi

  if ! getent group "${NODE_EXPORTER_GROUP}" >/dev/null 2>&1; then
    log "Creating group ${NODE_EXPORTER_GROUP}"
    as_root groupadd --system "${NODE_EXPORTER_GROUP}"
  fi

  if ! id -u "${NODE_EXPORTER_USER}" >/dev/null 2>&1; then
    log "Creating user ${NODE_EXPORTER_USER}"
    as_root useradd --system --no-create-home --home-dir / \
      --shell "${nologin_shell}" --gid "${NODE_EXPORTER_GROUP}" "${NODE_EXPORTER_USER}"
  fi
}

write_systemd_unit() {
  local exec_start
  exec_start="${NODE_EXPORTER_BINARY_PATH} --web.listen-address=${NODE_EXPORTER_WEB_LISTEN_ADDRESS} --web.telemetry-path=${NODE_EXPORTER_WEB_TELEMETRY_PATH}"
  if [[ -n "${NODE_EXPORTER_EXTRA_ARGS}" ]]; then
    exec_start="${exec_start} ${NODE_EXPORTER_EXTRA_ARGS}"
  fi

  as_root tee "${NODE_EXPORTER_SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_GROUP}
ExecStart=${exec_start}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
}

enable_and_start_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    die "systemctl not found. Cannot enable node_exporter service on boot without systemd."
  fi

  log "Enabling and starting node_exporter service"
  as_root systemctl daemon-reload
  as_root systemctl enable --now "${NODE_EXPORTER_SERVICE_NAME}"

  as_root systemctl is-enabled --quiet "${NODE_EXPORTER_SERVICE_NAME}" \
    || die "node_exporter service is not enabled."
  as_root systemctl is-active --quiet "${NODE_EXPORTER_SERVICE_NAME}" \
    || die "node_exporter service is not active."
}

main() {
  init_privilege_command
  ensure_supported_os
  detect_arch
  ensure_prerequisites
  resolve_version
  install_node_exporter_binary
  ensure_service_account
  write_systemd_unit
  enable_and_start_service

  log "Done. node_exporter ${NODE_EXPORTER_VERSION} is installed and enabled at boot."
}

main "$@"
