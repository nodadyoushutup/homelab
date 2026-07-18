#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

log() {
  printf '[packer-pipeline] %s\n' "$*"
}

die() {
  printf '[packer-pipeline] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF_USAGE'
Usage: packer/pipeline/packer.sh --version <version> [options]

Emulates the repo's Packer GitHub Actions workflow with a repo-native bash
entrypoint by running the existing packer build and upload scripts in order.

Required:
  --version <X.Y.Z>                Image version to build

Options:
  --distro <ubuntu|arch|centos|kali> Distro to build (default: ubuntu)
  --gui <headless|gnome|kde|xfce>  Desktop environment to install (default: headless)
  --install_node_exporter          Install host-level node_exporter systemd service (default: off)
  --ubuntu_release <24.04|26.04>   Ubuntu LTS release (ubuntu only; default: 24.04)
  --centos_stream <10>             CentOS Stream major release (centos only; default: 10)
  --arch_snapshot <snapshot>       Arch cloud image snapshot (arch only; default: template pin)
  --kali_release <2026.2>          Kali rolling release checkpoint (kali only; default: 2026.2)
  --target <cloud-image-repository> Publish target (default: cloud-image-repository)
  --amd64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --arm64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --build_arch <value>             amd64, arm64, or both (default: amd64)
                                   arch is amd64-only (no upstream arm64 image).
  --publish                        Also upload artifacts over REST (default: off,
                                   served straight from the NFS data/packer dir)
  -h, --help                       Show this help
EOF_USAGE
}

VERSION=""
DISTRO="ubuntu"
GUI="headless"
INSTALL_NODE_EXPORTER=0
UBUNTU_RELEASE="24.04"
CENTOS_STREAM="10"
ARCH_SNAPSHOT=""
KALI_RELEASE="2026.2"
TARGET="cloud-image-repository"
AMD64_ACCELERATOR="kvm"
ARM64_ACCELERATOR="kvm"
BUILD_ARCH="amd64"
PUBLISH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --distro)
      DISTRO="$2"
      shift 2
      ;;
    --gui)
      GUI="$2"
      shift 2
      ;;
    --install_node_exporter)
      INSTALL_NODE_EXPORTER=1
      shift
      ;;
    --ubuntu_release)
      UBUNTU_RELEASE="$2"
      shift 2
      ;;
    --centos_stream)
      CENTOS_STREAM="$2"
      shift 2
      ;;
    --arch_snapshot)
      ARCH_SNAPSHOT="$2"
      shift 2
      ;;
    --kali_release)
      KALI_RELEASE="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --amd64_accelerator)
      AMD64_ACCELERATOR="$2"
      shift 2
      ;;
    --arm64_accelerator)
      ARM64_ACCELERATOR="$2"
      shift 2
      ;;
    --build_arch)
      BUILD_ARCH="$2"
      shift 2
      ;;
    --publish|--upload)
      PUBLISH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${VERSION}" ]] || die "--version is required"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid version '${VERSION}'. Expected semantic version like 0.0.1"

case "${DISTRO}" in
  ubuntu|arch|centos|kali) ;;
  *) die "Invalid distro '${DISTRO}'. Expected: ubuntu|arch|centos|kali" ;;
esac

case "${GUI}" in
  headless|gnome|kde|xfce) ;;
  *) die "Invalid gui '${GUI}'. Expected: headless|gnome|kde|xfce" ;;
esac

case "${TARGET}" in
  cloud-image-repository) ;;
  *) die "Unsupported target '${TARGET}'" ;;
esac

case "${AMD64_ACCELERATOR}" in
  kvm|tcg|none) ;;
  *) die "Invalid amd64 accelerator '${AMD64_ACCELERATOR}'" ;;
esac

case "${ARM64_ACCELERATOR}" in
  kvm|tcg|none) ;;
  *) die "Invalid arm64 accelerator '${ARM64_ACCELERATOR}'" ;;
esac

case "${BUILD_ARCH}" in
  amd64|arm64|both) ;;
  *) die "Invalid build_arch '${BUILD_ARCH}'" ;;
esac

if [[ "${DISTRO}" == "arch" && "${BUILD_ARCH}" != "amd64" ]]; then
  die "Arch Linux publishes no official arm64 cloud image; arm64 Arch builds are not supported. Use --build_arch amd64."
fi

# Per-distro release/snapshot arguments.
RELEASE_ARGS=()
case "${DISTRO}" in
  ubuntu) RELEASE_ARGS=(--ubuntu_release "${UBUNTU_RELEASE}") ;;
  centos) RELEASE_ARGS=(--centos_stream "${CENTOS_STREAM}") ;;
  arch) [[ -n "${ARCH_SNAPSHOT}" ]] && RELEASE_ARGS=(--arch_snapshot "${ARCH_SNAPSHOT}") ;;
  kali) RELEASE_ARGS=(--kali_release "${KALI_RELEASE}") ;;
esac

NODE_EXPORTER_ARGS=()
if [[ "${INSTALL_NODE_EXPORTER}" -eq 1 ]]; then
  NODE_EXPORTER_ARGS=(--install_node_exporter)
fi

log "Version: ${VERSION}"
log "Distro: ${DISTRO}"
log "GUI: ${GUI}"
log "Host node_exporter: $([[ "${INSTALL_NODE_EXPORTER}" -eq 1 ]] && echo enabled || echo "disabled (swarm/k8s container exporter)")"
log "Target: ${TARGET}"
log "AMD64 accelerator: ${AMD64_ACCELERATOR}"
log "ARM64 accelerator: ${ARM64_ACCELERATOR}"
log "Build arch: ${BUILD_ARCH}"
log "REST publish: $([[ "${PUBLISH}" -eq 1 ]] && echo enabled || echo "disabled (served from NFS)")"

(
  cd "${ROOT_DIR}"
  ./packer/packer.sh \
    --version "${VERSION}" \
    --distro "${DISTRO}" \
    --gui "${GUI}" \
    --target "${TARGET}" \
    --build_arch "${BUILD_ARCH}" \
    --amd64_accelerator "${AMD64_ACCELERATOR}" \
    --arm64_accelerator "${ARM64_ACCELERATOR}" \
    ${NODE_EXPORTER_ARGS[@]+"${NODE_EXPORTER_ARGS[@]}"} \
    ${RELEASE_ARGS[@]+"${RELEASE_ARGS[@]}"}
)

if [[ "${PUBLISH}" -eq 1 ]]; then
  (
    cd "${ROOT_DIR}"
    ./packer/upload.sh "${VERSION}" \
      --distro "${DISTRO}" \
      --target "${TARGET}" \
      --build_arch "${BUILD_ARCH}" \
      ${RELEASE_ARGS[@]+"${RELEASE_ARGS[@]}"}
  )
else
  log "Skipping REST upload (--publish to enable); artifacts served from NFS data/packer."
fi
