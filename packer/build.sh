#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

bool_true() {
  local value="${1:-}"
  value="${value,,}"
  [[ "${value}" == "1" || "${value}" == "true" || "${value}" == "yes" || "${value}" == "on" ]]
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

usage() {
  cat <<'EOF_USAGE'
Usage: ./packer/build.sh --version <version> [options] [packer-build-args...]

Options:
  --version <X.Y.Z>                       Required image version (semantic version)
  --target <cloud-image-repository>       Publish target (default: cloud-image-repository)
  --build_arch <amd64|arm64|both>         Build architecture selector (default: amd64)
  --amd64_accelerator <kvm|tcg|none>      Accelerator for amd64 source (default: kvm)
  --arm64_accelerator <kvm|tcg|none>      Accelerator for arm64 source (default: kvm)
  --kde_profile <desktop|minimal|full>    Optional KDE profile
  --packer_log                            Enable PACKER_LOG=1 for this run
  --no_packer_log                         Disable PACKER_LOG for this run
  --packer_log_path <path>                Optional PACKER_LOG_PATH file location
  -h, --help                              Show this help

Examples:
  ./packer/build.sh --version 0.0.3
  ./packer/build.sh --version 0.0.3 --build_arch both --amd64_accelerator kvm --arm64_accelerator tcg
  ./packer/build.sh --version 0.0.3 --build_arch arm64 --arm64_accelerator kvm --packer_log
EOF_USAGE
}

human_size() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "${bytes}"
  else
    echo "${bytes}B"
  fi
}

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run with sudo/root on this NFS repo (root_squash). Run as your normal user."
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/ubuntu-24.04-ndysu.pkr.hcl"
KEY_FILE="${SCRIPT_DIR}/keys/packer-nodadyoushutup"
LOG_DIR="${SCRIPT_DIR}/logs"

[[ -f "${TEMPLATE}" ]] || die "Template not found: ${TEMPLATE}"
[[ -f "${KEY_FILE}" ]] || die "SSH private key not found: ${KEY_FILE}"

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

VERSION=""
VERSION_SET=0

TARGET="cloud-image-repository"
BUILD_ARCH="amd64"
AMD64_ACCELERATOR="kvm"
ARM64_ACCELERATOR="kvm"
KDE_PROFILE=""
KDE_PROFILE_SET=0
PACKER_LOG_ENABLED="${PACKER_LOG:-1}"
PACKER_LOG_FILE="${PACKER_LOG_PATH:-}"
PACKER_BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version=*)
      VERSION="${1#--version=}"
      VERSION_SET=1
      shift
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version requires a value: X.Y.Z"
      VERSION="$2"
      VERSION_SET=1
      shift 2
      ;;
    --target=*)
      TARGET="${1#--target=}"
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value: cloud-image-repository"
      TARGET="$2"
      shift 2
      ;;
    --build_arch=*)
      BUILD_ARCH="${1#--build_arch=}"
      shift
      ;;
    --build_arch)
      [[ $# -ge 2 ]] || die "--build_arch requires a value: amd64|arm64|both"
      BUILD_ARCH="$2"
      shift 2
      ;;
    --amd64_accelerator=*)
      AMD64_ACCELERATOR="${1#--amd64_accelerator=}"
      shift
      ;;
    --amd64_accelerator)
      [[ $# -ge 2 ]] || die "--amd64_accelerator requires a value: kvm|tcg|none"
      AMD64_ACCELERATOR="$2"
      shift 2
      ;;
    --arm64_accelerator=*)
      ARM64_ACCELERATOR="${1#--arm64_accelerator=}"
      shift
      ;;
    --arm64_accelerator)
      [[ $# -ge 2 ]] || die "--arm64_accelerator requires a value: kvm|tcg|none"
      ARM64_ACCELERATOR="$2"
      shift 2
      ;;
    --kde_profile=*)
      KDE_PROFILE="${1#--kde_profile=}"
      KDE_PROFILE_SET=1
      shift
      ;;
    --kde_profile)
      [[ $# -ge 2 ]] || die "--kde_profile requires a value: desktop|minimal|full"
      KDE_PROFILE="$2"
      KDE_PROFILE_SET=1
      shift 2
      ;;
    --packer_log)
      PACKER_LOG_ENABLED="1"
      shift
      ;;
    --no_packer_log)
      PACKER_LOG_ENABLED="0"
      shift
      ;;
    --packer_log_path=*)
      PACKER_LOG_FILE="${1#--packer_log_path=}"
      PACKER_LOG_ENABLED="1"
      shift
      ;;
    --packer_log_path)
      [[ $# -ge 2 ]] || die "--packer_log_path requires a value"
      PACKER_LOG_FILE="$2"
      PACKER_LOG_ENABLED="1"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      PACKER_BUILD_ARGS+=("$@")
      break
      ;;
    *)
      PACKER_BUILD_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "${VERSION_SET}" -ne 1 ]]; then
  die "Missing required --version <X.Y.Z> argument."
fi
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid --version '${VERSION}'. Expected semantic version like 0.0.1."
fi
if bool_true "${PACKER_LOG_ENABLED}"; then
  PACKER_LOG_ENABLED="1"
else
  PACKER_LOG_ENABLED="0"
fi

case "${TARGET}" in
  cloud-image-repository)
    DEFAULT_UPLOAD_BASE_URL="https://cloud-image-repository.image.nodadyoushutup.com"
    DEFAULT_UPLOAD_FALLBACK_BASE_URL="http://192.168.1.120:18088"
    ;;
  *)
    die "Unsupported --target '${TARGET}'. Expected: cloud-image-repository"
    ;;
esac

case "${BUILD_ARCH}" in
  amd64|arm64|both)
    ;;
  *)
    die "Invalid --build_arch '${BUILD_ARCH}'. Expected: amd64|arm64|both"
    ;;
esac

case "${AMD64_ACCELERATOR}" in
  kvm|tcg|none)
    ;;
  *)
    die "Invalid --amd64_accelerator '${AMD64_ACCELERATOR}'. Expected: kvm|tcg|none"
    ;;
esac

case "${ARM64_ACCELERATOR}" in
  kvm|tcg|none)
    ;;
  *)
    die "Invalid --arm64_accelerator '${ARM64_ACCELERATOR}'. Expected: kvm|tcg|none"
    ;;
esac

if [[ "${KDE_PROFILE_SET}" -eq 1 ]]; then
  case "${KDE_PROFILE}" in
    desktop|minimal|full)
      ;;
    *)
      die "Invalid --kde_profile '${KDE_PROFILE}'. Expected: desktop|minimal|full"
      ;;
  esac
fi

for arg in "${PACKER_BUILD_ARGS[@]}"; do
  case "${arg}" in
    -only|-only=*|-except|-except=*)
      die "Do not pass ${arg} directly. Use --build_arch amd64|arm64|both instead."
      ;;
  esac
done

UPLOAD_BASE_URL="${UPLOAD_BASE_URL:-${DEFAULT_UPLOAD_BASE_URL}}"
UPLOAD_FALLBACK_BASE_URL="${UPLOAD_FALLBACK_BASE_URL:-${DEFAULT_UPLOAD_FALLBACK_BASE_URL}}"

PACKER_ONLY_ARGS=()
case "${BUILD_ARCH}" in
  amd64)
    PACKER_ONLY_ARGS=(-only=ubuntu-24.04-ndysu.qemu.ubuntu_24_04_amd64)
    ;;
  arm64)
    PACKER_ONLY_ARGS=(-only=ubuntu-24.04-ndysu.qemu.ubuntu_24_04_arm64)
    ;;
  both)
    ;;
esac

PACKER_VAR_ARGS=(
  -var "image_version=${VERSION}"
  -var "amd64_accelerator=${AMD64_ACCELERATOR}"
  -var "arm64_accelerator=${ARM64_ACCELERATOR}"
)
if [[ "${KDE_PROFILE_SET}" -eq 1 ]]; then
  PACKER_VAR_ARGS+=( -var "kde_profile=${KDE_PROFILE}" )
fi

OUTPUT_SUBDIR="output/ubuntu-24.04-ndysu/${VERSION}"
OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_SUBDIR}"

mkdir -p "${LOG_DIR}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/build-${RUN_TS}-v${VERSION}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

if [[ "${PACKER_LOG_ENABLED}" -eq 1 ]]; then
  if [[ -z "${PACKER_LOG_FILE}" ]]; then
    PACKER_LOG_FILE="${LOG_DIR}/packer-debug-${RUN_TS}-v${VERSION}.log"
  fi
  export PACKER_LOG=1
  export PACKER_LOG_PATH="${PACKER_LOG_FILE}"
fi

require_cmd packer
require_cmd xorriso
require_cmd qemu-img
require_cmd curl
require_cmd jq

if [[ "${BUILD_ARCH}" == "amd64" || "${BUILD_ARCH}" == "both" ]]; then
  require_cmd qemu-system-x86_64
fi
if [[ "${BUILD_ARCH}" == "arm64" || "${BUILD_ARCH}" == "both" ]]; then
  require_cmd qemu-system-aarch64
fi

HOST_ARCH="$(uname -m)"
if [[ "${BUILD_ARCH}" == "amd64" || "${BUILD_ARCH}" == "both" ]] && [[ "${AMD64_ACCELERATOR}" == "kvm" ]]; then
  case "${HOST_ARCH}" in
    x86_64|amd64)
      ;;
    *)
      die "amd64_accelerator=kvm requires an x86_64 host. Current host architecture is ${HOST_ARCH}."
      ;;
  esac
fi
if [[ "${BUILD_ARCH}" == "arm64" || "${BUILD_ARCH}" == "both" ]] && [[ "${ARM64_ACCELERATOR}" == "kvm" ]]; then
  case "${HOST_ARCH}" in
    aarch64|arm64)
      ;;
    *)
      die "arm64_accelerator=kvm requires an arm64 host. Current host architecture is ${HOST_ARCH}. Use --arm64_accelerator tcg or none on this host."
      ;;
  esac
fi

KVM_REQUIRED=0
if [[ "${BUILD_ARCH}" == "amd64" || "${BUILD_ARCH}" == "both" ]] && [[ "${AMD64_ACCELERATOR}" == "kvm" ]]; then
  KVM_REQUIRED=1
fi
if [[ "${BUILD_ARCH}" == "arm64" || "${BUILD_ARCH}" == "both" ]] && [[ "${ARM64_ACCELERATOR}" == "kvm" ]]; then
  KVM_REQUIRED=1
fi
if [[ "${KVM_REQUIRED}" -eq 1 ]]; then
  [[ -e /dev/kvm ]] || die "/dev/kvm is missing but a KVM accelerator was selected."
  [[ -r /dev/kvm && -w /dev/kvm ]] || die "/dev/kvm is present but not readable/writable by current user."
fi

cd "${SCRIPT_DIR}"

log "Version: ${VERSION}"
log "Host arch: ${HOST_ARCH}"
log "Target: ${TARGET}"
log "Build arch: ${BUILD_ARCH}"
log "amd64 accelerator: ${AMD64_ACCELERATOR}"
log "arm64 accelerator: ${ARM64_ACCELERATOR}"
log "Log file: ${LOG_FILE}"
if [[ "${PACKER_LOG_ENABLED}" -eq 1 ]]; then
  log "Packer debug log: ${PACKER_LOG_PATH}"
fi
log "Using template: ${TEMPLATE}"
if [[ "${KDE_PROFILE_SET}" -eq 1 ]]; then
  log "KDE profile enabled: ${KDE_PROFILE}"
else
  log "KDE profile not set; GUI install will be skipped."
fi

if [[ -d "${OUTPUT_DIR}" ]]; then
  log "Removing existing output directory: ${OUTPUT_DIR}"
  rm -rf "${OUTPUT_DIR}"
fi

log "Running: packer init"
packer init "${TEMPLATE}"

log "Running: packer fmt"
packer fmt "${TEMPLATE}"

log "Running: packer validate"
packer validate "${PACKER_ONLY_ARGS[@]}" "${PACKER_VAR_ARGS[@]}" "${TEMPLATE}"

log "Running: packer build"
packer build -force "${PACKER_ONLY_ARGS[@]}" "${PACKER_VAR_ARGS[@]}" "${PACKER_BUILD_ARGS[@]}" "${TEMPLATE}"

MAX_UPLOAD_BYTES="$((25 * 1024 * 1024 * 1024))"

mapfile -t ARTIFACT_PATHS < <(find "${OUTPUT_DIR}" -type f -name '*.qcow2' | sort)
[[ "${#ARTIFACT_PATHS[@]}" -gt 0 ]] || die "Build finished but no qcow2 artifacts found under: ${OUTPUT_DIR}"

upload_artifact() {
  local artifact_path="$1"
  local url="$2"
  curl \
    --progress-bar \
    --show-error \
    --output /dev/null \
    --write-out "%{http_code}" \
    --request PUT \
    --header "Content-Type: application/octet-stream" \
    --upload-file "${artifact_path}" \
    "${url}"
}

for ARTIFACT_PATH in "${ARTIFACT_PATHS[@]}"; do
  ARTIFACT_BASENAME="$(basename "${ARTIFACT_PATH}")"
  APPARENT_BYTES="$(stat -c '%s' "${ARTIFACT_PATH}")"
  ALLOCATED_BYTES="$(du -B1 "${ARTIFACT_PATH}" | awk '{print $1}')"

  log "Artifact: ${ARTIFACT_PATH}"
  log "Artifact apparent size: $(human_size "${APPARENT_BYTES}")"
  log "Artifact allocated size: $(human_size "${ALLOCATED_BYTES}")"

  if [ "${APPARENT_BYTES}" -gt "${MAX_UPLOAD_BYTES}" ]; then
    die "Artifact apparent size exceeds 25GiB upload host limit (client_max_body_size 25g): ${ARTIFACT_BASENAME}"
  fi

  UPLOAD_URL="${UPLOAD_BASE_URL}/${ARTIFACT_BASENAME}"
  log "Uploading artifact to: ${UPLOAD_URL}"

  UPLOAD_HTTP_CODE="$(upload_artifact "${ARTIFACT_PATH}" "${UPLOAD_URL}")"

  if [[ "${UPLOAD_HTTP_CODE}" == "413" ]] && [[ -n "${UPLOAD_FALLBACK_BASE_URL}" ]]; then
    UPLOAD_FALLBACK_URL="${UPLOAD_FALLBACK_BASE_URL}/${ARTIFACT_BASENAME}"
    log "Primary upload returned 413. Retrying direct backend upload: ${UPLOAD_FALLBACK_URL}"
    UPLOAD_HTTP_CODE="$(upload_artifact "${ARTIFACT_PATH}" "${UPLOAD_FALLBACK_URL}")"
    UPLOAD_URL="${UPLOAD_FALLBACK_URL}"
  fi

  case "${UPLOAD_HTTP_CODE}" in
    200|201|204)
      ;;
    *)
      die "Upload failed with HTTP status ${UPLOAD_HTTP_CODE} for ${UPLOAD_URL}"
      ;;
  esac

  log "Upload completed with HTTP ${UPLOAD_HTTP_CODE}"
done

log "Build complete"
