#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<'EOF_USAGE'
Usage: ./packer/upload.sh <version> [options]

Options:
  --distro <ubuntu|arch|centos|kali>      Distro to upload (default: ubuntu)
  --ubuntu_release <24.04|26.04>          Ubuntu LTS release to upload (ubuntu only; default: 24.04)
  --centos_stream <10>                    CentOS Stream major release (centos only; default: 10)
  --arch_snapshot <snapshot>              Accepted and ignored (arch prefix has no snapshot)
  --kali_release <2026.2>                 Kali rolling release checkpoint (kali only; default: 2026.2)
  --target <cloud-image-repository>       Publish target (default: cloud-image-repository)
  --build_arch <amd64|arm64|both>         Upload architecture selector (default: both)
  -h, --help                              Show this help

Examples:
  ./packer/upload.sh 0.0.3
  ./packer/upload.sh 0.0.3 --build_arch amd64
  ./packer/upload.sh 0.0.3 --distro centos --build_arch both
EOF_USAGE
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
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

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

VERSION="$1"
shift
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid version '${VERSION}'. Expected semantic version like 0.0.1."
fi

TARGET="cloud-image-repository"
BUILD_ARCH="both"
DISTRO="ubuntu"
UBUNTU_RELEASE="24.04"
CENTOS_STREAM="10"
ARCH_SNAPSHOT=""
KALI_RELEASE="2026.2"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --distro=*)
      DISTRO="${1#--distro=}"
      shift
      ;;
    --distro)
      [[ $# -ge 2 ]] || die "--distro requires a value: ubuntu|arch|centos"
      DISTRO="$2"
      shift 2
      ;;
    --ubuntu_release=*)
      UBUNTU_RELEASE="${1#--ubuntu_release=}"
      shift
      ;;
    --ubuntu_release)
      [[ $# -ge 2 ]] || die "--ubuntu_release requires a value: 24.04|26.04"
      UBUNTU_RELEASE="$2"
      shift 2
      ;;
    --centos_stream=*)
      CENTOS_STREAM="${1#--centos_stream=}"
      shift
      ;;
    --centos_stream)
      [[ $# -ge 2 ]] || die "--centos_stream requires a value: 10"
      CENTOS_STREAM="$2"
      shift 2
      ;;
    --arch_snapshot=*)
      ARCH_SNAPSHOT="${1#--arch_snapshot=}"
      shift
      ;;
    --arch_snapshot)
      [[ $# -ge 2 ]] || die "--arch_snapshot requires a value"
      ARCH_SNAPSHOT="$2"
      shift 2
      ;;
    --kali_release=*)
      KALI_RELEASE="${1#--kali_release=}"
      shift
      ;;
    --kali_release)
      [[ $# -ge 2 ]] || die "--kali_release requires a value: 2026.2"
      KALI_RELEASE="$2"
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unexpected argument: $1"
      ;;
  esac
done

case "${DISTRO}" in
  ubuntu|arch|centos|kali) ;;
  *) die "Invalid --distro '${DISTRO}'. Expected: ubuntu|arch|centos|kali" ;;
esac

if [[ "${DISTRO}" == "ubuntu" ]]; then
  case "${UBUNTU_RELEASE}" in
    24.04|26.04) ;;
    *) die "Invalid --ubuntu_release '${UBUNTU_RELEASE}'. Expected: 24.04|26.04" ;;
  esac
fi

if [[ "${DISTRO}" == "centos" ]]; then
  [[ "${CENTOS_STREAM}" =~ ^[0-9]+$ ]] || die "Invalid --centos_stream '${CENTOS_STREAM}'. Expected a major version like 10."
fi

case "${TARGET}" in
  cloud-image-repository)
    DEFAULT_UPLOAD_BASE_URL="https://cloud-image-repository.nodadyoushutup.com"
    DEFAULT_UPLOAD_FALLBACK_BASE_URL="http://192.168.1.120:18088"
    ;;
  *)
    die "Unsupported --target '${TARGET}'. Expected: cloud-image-repository"
    ;;
esac

case "${DISTRO}" in
  ubuntu) IMAGE_PREFIX="ubuntu-${UBUNTU_RELEASE}-ndysu" ;;
  arch) IMAGE_PREFIX="arch-ndysu" ;;
  centos) IMAGE_PREFIX="centos-${CENTOS_STREAM}-ndysu" ;;
  kali) IMAGE_PREFIX="kali-${KALI_RELEASE}-ndysu" ;;
esac

if [[ "${DISTRO}" == "arch" && "${BUILD_ARCH}" != "amd64" ]]; then
  die "Arch Linux publishes no official arm64 cloud image; arm64 Arch artifacts do not exist. Use --build_arch amd64."
fi

case "${BUILD_ARCH}" in
  amd64)
    PATH_FILTER="*/${IMAGE_PREFIX}/${VERSION}/amd64/*"
    ;;
  arm64)
    PATH_FILTER="*/${IMAGE_PREFIX}/${VERSION}/arm64/*"
    ;;
  both)
    PATH_FILTER="*/${IMAGE_PREFIX}/${VERSION}/*"
    ;;
  *)
    die "Invalid --build_arch '${BUILD_ARCH}'. Expected: amd64|arm64|both"
    ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# Artifacts live in the NFS-backed data/packer dir the repository serves.
OUTPUT_DIR="${PACKER_OUTPUT_ROOT:-${REPO_ROOT}/data/packer}"
LOG_DIR="${SCRIPT_DIR}/logs"
UPLOAD_BASE_URL="${UPLOAD_BASE_URL:-${DEFAULT_UPLOAD_BASE_URL}}"
UPLOAD_FALLBACK_BASE_URL="${UPLOAD_FALLBACK_BASE_URL:-${DEFAULT_UPLOAD_FALLBACK_BASE_URL}}"
MAX_UPLOAD_BYTES="$((25 * 1024 * 1024 * 1024))"

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}"

mkdir -p "${LOG_DIR}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/upload-${RUN_TS}-v${VERSION}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_cmd curl
require_cmd stat

mapfile -t ARTIFACT_PATHS < <(
  find "${OUTPUT_DIR}" -type f -name '*.qcow2' -path "${PATH_FILTER}" | sort
)

[[ "${#ARTIFACT_PATHS[@]}" -gt 0 ]] || die "No qcow2 artifacts found under ${OUTPUT_DIR} for version ${VERSION} and build_arch ${BUILD_ARCH}."

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

log "Version: ${VERSION}"
log "Distro: ${DISTRO}"
case "${DISTRO}" in
  ubuntu) log "Ubuntu release: ${UBUNTU_RELEASE}" ;;
  centos) log "CentOS stream: ${CENTOS_STREAM}" ;;
  arch) log "Arch image prefix: ${IMAGE_PREFIX}" ;;
  kali) log "Kali release: ${KALI_RELEASE}" ;;
esac
log "Target: ${TARGET}"
log "Build arch: ${BUILD_ARCH}"
log "Log file: ${LOG_FILE}"
log "Upload base URL: ${UPLOAD_BASE_URL}"

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

log "Upload complete"
