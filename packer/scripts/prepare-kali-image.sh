#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

# Prepare a Kali Linux cloud base image for Packer.
#
# Kali does not publish a ready-to-boot qcow2 cloud image. It ships a
# `.tar.xz` tarball containing a single raw disk (`disk.raw`). Packer's qemu
# builder cannot fetch/extract that tarball, so this script:
#   1. downloads the pinned tarball for the requested release + architecture,
#   2. verifies it against the pinned upstream SHA256,
#   3. extracts the raw disk,
#   4. converts it to a qcow2 in the cache dir,
#   5. prints two KEY=VALUE lines on stdout (everything else goes to stderr):
#        KALI_IMAGE_PATH=<absolute path to the prepared qcow2>
#        KALI_IMAGE_CHECKSUM=sha256:<hex of the prepared qcow2>
#
# The KEY=VALUE contract lets callers consume it directly:
#   - packer/packer.sh:  source <(scripts/prepare-kali-image.sh ...)
#   - GitHub Actions:    scripts/prepare-kali-image.sh ... >> "$GITHUB_ENV"

log() { echo "[prepare-kali] $*" >&2; }
die() { echo "[prepare-kali] ERROR: $*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF_USAGE'
Usage: prepare-kali-image.sh --arch <amd64|arm64> [--release <X.Y>] [--cache-dir <dir>]

Options:
  --arch <amd64|arm64>   Architecture to prepare (required)
  --release <X.Y>        Kali release checkpoint (default: 2026.2)
  --cache-dir <dir>      Where to cache/convert images (default: <packer>/.cache/kali)
  -h, --help             Show this help
EOF_USAGE
}

ARCH=""
RELEASE="2026.2"
CACHE_DIR=""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PACKER_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) [[ $# -ge 2 ]] || die "--arch requires a value"; ARCH="$2"; shift 2 ;;
    --arch=*) ARCH="${1#--arch=}"; shift ;;
    --release) [[ $# -ge 2 ]] || die "--release requires a value"; RELEASE="$2"; shift 2 ;;
    --release=*) RELEASE="${1#--release=}"; shift ;;
    --cache-dir) [[ $# -ge 2 ]] || die "--cache-dir requires a value"; CACHE_DIR="$2"; shift 2 ;;
    --cache-dir=*) CACHE_DIR="${1#--cache-dir=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unexpected argument: $1" ;;
  esac
done

case "${ARCH}" in
  amd64|arm64) ;;
  *) usage; die "Invalid --arch '${ARCH}'. Expected: amd64|arm64" ;;
esac

CACHE_DIR="${CACHE_DIR:-${PACKER_DIR}/.cache/kali}"

command -v curl >/dev/null 2>&1 || die "Missing required command: curl"
command -v tar >/dev/null 2>&1 || die "Missing required command: tar"
command -v xz >/dev/null 2>&1 || die "Missing required command: xz"
command -v qemu-img >/dev/null 2>&1 || die "Missing required command: qemu-img"
command -v sha256sum >/dev/null 2>&1 || die "Missing required command: sha256sum"

# Pinned upstream tarball SHA256s, keyed by "<release>:<arch>". Bump these
# together with the release when moving to a newer Kali cloud image. Source:
# https://kali.download/cloud-images/kali-<release>/SHA256SUMS
declare -A KALI_TARBALL_SHA256=(
  ["2026.2:amd64"]="3f4ca86ae1eca0dc2bf2092f065a959508e186c6b44f85758813a8e9a0604f3e"
  ["2026.2:arm64"]="9ab19c28d049fdc6f1d5d30f6cc93b8b01997f11c89f6992f690c07b16b7b7e4"
)

PIN_KEY="${RELEASE}:${ARCH}"
EXPECTED_SHA256="${KALI_TARBALL_SHA256[${PIN_KEY}]:-}"
[[ -n "${EXPECTED_SHA256}" ]] || die "No pinned checksum for Kali release '${RELEASE}' arch '${ARCH}'. Add it to KALI_TARBALL_SHA256 (see https://kali.download/cloud-images/kali-${RELEASE}/SHA256SUMS)."

TARBALL_NAME="kali-linux-${RELEASE}-cloud-genericcloud-${ARCH}.tar.xz"
TARBALL_URL="https://kali.download/cloud-images/kali-${RELEASE}/${TARBALL_NAME}"
QCOW2_NAME="kali-${RELEASE}-cloudimg-${ARCH}.qcow2"
QCOW2_PATH="${CACHE_DIR}/${QCOW2_NAME}"
TARBALL_PATH="${CACHE_DIR}/${TARBALL_NAME}"

mkdir -p "${CACHE_DIR}"

emit_result() {
  local checksum
  checksum="$(sha256sum "${QCOW2_PATH}" | awk '{print $1}')"
  echo "KALI_IMAGE_PATH=${QCOW2_PATH}"
  echo "KALI_IMAGE_CHECKSUM=sha256:${checksum}"
}

# Reuse an already-converted qcow2 if present (idempotent across runs).
if [[ -f "${QCOW2_PATH}" ]]; then
  log "Reusing cached prepared image: ${QCOW2_PATH}"
  emit_result
  exit 0
fi

verify_tarball() {
  echo "${EXPECTED_SHA256}  ${TARBALL_PATH}" | sha256sum -c - >/dev/null 2>&1
}

if [[ -f "${TARBALL_PATH}" ]] && verify_tarball; then
  log "Reusing cached verified tarball: ${TARBALL_PATH}"
else
  log "Downloading ${TARBALL_URL}"
  curl -fL --retry 3 --output "${TARBALL_PATH}" "${TARBALL_URL}"
  log "Verifying SHA256 (${EXPECTED_SHA256})"
  verify_tarball || die "SHA256 mismatch for ${TARBALL_NAME}; refusing to use it."
fi

WORK_DIR="$(mktemp -d "${CACHE_DIR}/extract.XXXXXX")"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

log "Extracting raw disk from ${TARBALL_NAME}"
tar -xJf "${TARBALL_PATH}" -C "${WORK_DIR}"

RAW_PATH="$(find "${WORK_DIR}" -maxdepth 2 -type f -name '*.raw' | head -n1)"
[[ -n "${RAW_PATH}" ]] || die "No raw disk (*.raw) found inside ${TARBALL_NAME}."

log "Converting raw disk to qcow2: ${QCOW2_PATH}"
# Convert into a temp file first, then atomically move, so an interrupted run
# never leaves a half-written qcow2 that the idempotent reuse check would trust.
TMP_QCOW2="${QCOW2_PATH}.tmp.$$"
rm -f "${TMP_QCOW2}"
qemu-img convert -f raw -O qcow2 "${RAW_PATH}" "${TMP_QCOW2}"
mv -f "${TMP_QCOW2}" "${QCOW2_PATH}"

log "Prepared ${QCOW2_PATH}"
emit_result
