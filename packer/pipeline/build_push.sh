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
Usage: packer/pipeline/build_push.sh --version <version> [options]

Emulates the repo's Packer GitHub Actions workflow with a repo-native bash
entrypoint by running the existing packer build and upload scripts in order.

Required:
  --version <X.Y.Z>                Image version to build

Options:
  --target <cloud-image-repository> Publish target (default: cloud-image-repository)
  --amd64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --arm64_accelerator <value>      kvm, tcg, or none (default: kvm)
  --build_arch <value>             amd64, arm64, or both (default: amd64)
  -h, --help                       Show this help
EOF_USAGE
}

VERSION=""
TARGET="cloud-image-repository"
AMD64_ACCELERATOR="kvm"
ARM64_ACCELERATOR="kvm"
BUILD_ARCH="amd64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
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

log "Version: ${VERSION}"
log "Target: ${TARGET}"
log "AMD64 accelerator: ${AMD64_ACCELERATOR}"
log "ARM64 accelerator: ${ARM64_ACCELERATOR}"
log "Build arch: ${BUILD_ARCH}"

(
  cd "${ROOT_DIR}"
  ./packer/build.sh \
    --version "${VERSION}" \
    --target "${TARGET}" \
    --build_arch "${BUILD_ARCH}" \
    --amd64_accelerator "${AMD64_ACCELERATOR}" \
    --arm64_accelerator "${ARM64_ACCELERATOR}"
)

(
  cd "${ROOT_DIR}"
  ./packer/upload.sh "${VERSION}" \
    --target "${TARGET}" \
    --build_arch "${BUILD_ARCH}"
)
