#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

log()  { echo "[INFO] $*"; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./packer/upload.sh <version>

Example:
  ./packer/upload.sh 0.0.3
EOF
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

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

VERSION="$1"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "Invalid version '${VERSION}'. Expected semantic version like 0.0.1."
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOG_DIR="${SCRIPT_DIR}/logs"
UPLOAD_BASE_URL="${UPLOAD_BASE_URL:-https://webserver.image.nodadyoushutup.com}"
UPLOAD_FALLBACK_BASE_URL="${UPLOAD_FALLBACK_BASE_URL:-http://192.168.1.120:18088}"
MAX_UPLOAD_BYTES="$((25 * 1024 * 1024 * 1024))"

[[ -d "${OUTPUT_DIR}" ]] || die "Output directory not found: ${OUTPUT_DIR}"

mkdir -p "${LOG_DIR}"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOG_FILE="${LOG_DIR}/upload-${RUN_TS}-v${VERSION}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

require_cmd curl

mapfile -t ARTIFACT_PATHS < <(
  find "${OUTPUT_DIR}" -type f \( -name '*.qcow2' -o -name '*.img' \) -path "*/${VERSION}/*" | sort
)

[[ "${#ARTIFACT_PATHS[@]}" -gt 0 ]] || die "No artifacts found under ${OUTPUT_DIR} for version ${VERSION}."

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

log "Upload complete"
