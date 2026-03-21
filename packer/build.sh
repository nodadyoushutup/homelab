#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

usage() {
  cat <<'EOF'
Usage: ./packer/build.sh <version> [--kde_profile=<desktop|minimal|full>] [packer-build-args...]

Example:
  ./packer/build.sh 0.0.1
  ./packer/build.sh 0.0.3 --kde_profile=desktop
EOF
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
UPLOAD_BASE_URL="${UPLOAD_BASE_URL:-https://webserver.image.nodadyoushutup.com}"
UPLOAD_FALLBACK_BASE_URL="${UPLOAD_FALLBACK_BASE_URL:-http://192.168.1.120:18088}"

[[ -f "${TEMPLATE}" ]] || die "Template not found: ${TEMPLATE}"
[[ -f "${KEY_FILE}" ]] || die "SSH private key not found: ${KEY_FILE}"

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

VERSION="$1"
shift
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid version '${VERSION}'. Expected semantic version like 0.0.1."
fi

KDE_PROFILE=""
KDE_PROFILE_SET=0
PACKER_BUILD_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
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
    *)
      PACKER_BUILD_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "${KDE_PROFILE_SET}" -eq 1 ]]; then
  case "${KDE_PROFILE}" in
    desktop|minimal|full)
      ;;
    *)
      die "Invalid --kde_profile '${KDE_PROFILE}'. Expected: desktop|minimal|full"
      ;;
  esac
fi

PACKER_VAR_ARGS=(
  -var "image_version=${VERSION}"
)
if [[ "${KDE_PROFILE_SET}" -eq 1 ]]; then
  PACKER_VAR_ARGS+=(-var "kde_profile=${KDE_PROFILE}")
fi

OUTPUT_SUBDIR="output/ubuntu-24.04-ndysu/${VERSION}"
OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_SUBDIR}"

mkdir -p "${LOG_DIR}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/build-${RUN_TS}-v${VERSION}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_cmd packer
require_cmd qemu-img
require_cmd curl

NEED_AMD64_QEMU=1
NEED_ARM64_QEMU=1
ONLY_EXPR=""
for ((i = 0; i < ${#PACKER_BUILD_ARGS[@]}; i++)); do
  arg="${PACKER_BUILD_ARGS[$i]}"
  if [[ "${arg}" == "-only" ]] && [[ $((i + 1)) -lt ${#PACKER_BUILD_ARGS[@]} ]]; then
    ONLY_EXPR="${PACKER_BUILD_ARGS[$((i + 1))]}"
  elif [[ "${arg}" == -only=* ]]; then
    ONLY_EXPR="${arg#-only=}"
  fi
done

if [[ -n "${ONLY_EXPR}" ]]; then
  NEED_AMD64_QEMU=0
  NEED_ARM64_QEMU=0
  IFS=',' read -r -a ONLY_TARGETS <<< "${ONLY_EXPR}"
  for target in "${ONLY_TARGETS[@]}"; do
    [[ "${target}" == *amd64* ]] && NEED_AMD64_QEMU=1
    [[ "${target}" == *arm64* ]] && NEED_ARM64_QEMU=1
  done
fi

if [[ "${NEED_AMD64_QEMU}" -eq 1 ]]; then
  require_cmd qemu-system-x86_64
fi
if [[ "${NEED_ARM64_QEMU}" -eq 1 ]]; then
  require_cmd qemu-system-aarch64
fi

cd "${SCRIPT_DIR}"

log "Version: ${VERSION}"
log "Log file: ${LOG_FILE}"
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
packer validate "${PACKER_VAR_ARGS[@]}" "${TEMPLATE}"

log "Running: packer build"
packer build -force "${PACKER_VAR_ARGS[@]}" "${PACKER_BUILD_ARGS[@]}" "${TEMPLATE}"

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
    die "Artifact apparent size exceeds 25GiB webserver limit (client_max_body_size 25g): ${ARTIFACT_BASENAME}"
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
