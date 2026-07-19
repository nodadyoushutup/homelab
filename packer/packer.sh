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
Usage: ./packer/packer.sh --version <version> [options] [packer-build-args...]

Builds into the NFS-backed data/packer directory that the cloud image repository
serves directly, so the artifact is published just by building. The REST upload
is opt-in via --publish (use it to push through the public URL, e.g. when
building off the homelab NFS).

Options:
  --version <X.Y.Z>                       Required image version (semantic version)
  --distro <ubuntu|arch|centos|kali>      Distro to build (default: ubuntu)
  --gui <headless|gnome|kde|xfce>         Desktop environment to install (default: headless)
  --install_node_exporter                 Install host-level node_exporter systemd service (default: off)
  --no_install_node_exporter              Skip host-level node_exporter install (default)
  --ubuntu_release <24.04|26.04>          Ubuntu LTS release (ubuntu only; default: 24.04)
  --centos_stream <10>                    CentOS Stream major release (centos only; default: 10)
  --arch_snapshot <snapshot>              Arch cloud image snapshot (arch only; default: template pin)
  --kali_release <2026.2>                 Kali rolling release checkpoint (kali only; default: 2026.2)
  --target <cloud-image-repository>       Publish target (default: cloud-image-repository)
  --build_arch <amd64|arm64|both>         Build architecture selector (default: amd64)
                                          arch is amd64-only (no upstream arm64 image).
  --amd64_accelerator <kvm|tcg|none>      Accelerator for amd64 source (default: kvm)
  --arm64_accelerator <kvm|tcg|none>      Accelerator for arm64 source (default: kvm)
  --publish                               Also upload artifacts over REST (default: off)
  --packer_log                            Enable PACKER_LOG=1 for this run
  --no_packer_log                         Disable PACKER_LOG for this run
  --packer_log_path <path>                Optional PACKER_LOG_PATH file location
  -h, --help                              Show this help

Environment:
  PACKER_OUTPUT_ROOT   Override the output base dir (default: <repo>/data/packer)

Examples:
  ./packer/packer.sh --version 0.0.3
  ./packer/packer.sh --version 0.0.3 --distro arch --build_arch amd64
  ./packer/packer.sh --version 0.0.3 --distro centos --build_arch both
  ./packer/packer.sh --version 0.0.3 --distro kali --build_arch amd64
  ./packer/packer.sh --version 0.0.3 --distro ubuntu --gui xfce
  ./packer/packer.sh --version 0.0.3 --publish
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
KEY_FILE="${SCRIPT_DIR}/keys/packer-nodadyoushutup"
LOG_DIR="${SCRIPT_DIR}/logs"

[[ -f "${KEY_FILE}" ]] || die "SSH private key not found: ${KEY_FILE}"

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

VERSION=""
VERSION_SET=0

DISTRO="ubuntu"
GUI="headless"
INSTALL_NODE_EXPORTER=0
UBUNTU_RELEASE="24.04"
CENTOS_STREAM="10"
ARCH_SNAPSHOT=""
KALI_RELEASE="2026.2"
TARGET="cloud-image-repository"
BUILD_ARCH="amd64"
AMD64_ACCELERATOR="kvm"
ARM64_ACCELERATOR="kvm"
PUBLISH=0
PACKER_LOG_ENABLED="${PACKER_LOG:-1}"
PACKER_LOG_FILE="${PACKER_LOG_PATH:-}"
PACKER_BUILD_ARGS=()

# Seed defaults from the homelab-config-managed .config/packer/build.pkrvars.hcl
# (if present). Explicit CLI flags parsed below still override these.
# shellcheck source=lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
packer_config_load

cfg_bool() {
  case "${1,,}" in
    1|true|yes|on) echo 1 ;;
    *) echo 0 ;;
  esac
}

[[ -n "${PKRCFG_image_version:-}" ]] && { VERSION="${PKRCFG_image_version}"; VERSION_SET=1; }
[[ -n "${PKRCFG_distro:-}" ]] && DISTRO="${PKRCFG_distro}"
[[ -n "${PKRCFG_gui:-}" ]] && GUI="${PKRCFG_gui}"
[[ -n "${PKRCFG_install_node_exporter:-}" ]] && INSTALL_NODE_EXPORTER="$(cfg_bool "${PKRCFG_install_node_exporter}")"
[[ -n "${PKRCFG_ubuntu_release:-}" ]] && UBUNTU_RELEASE="${PKRCFG_ubuntu_release}"
[[ -n "${PKRCFG_centos_stream:-}" ]] && CENTOS_STREAM="${PKRCFG_centos_stream}"
[[ -n "${PKRCFG_arch_snapshot:-}" ]] && ARCH_SNAPSHOT="${PKRCFG_arch_snapshot}"
[[ -n "${PKRCFG_kali_release:-}" ]] && KALI_RELEASE="${PKRCFG_kali_release}"
[[ -n "${PKRCFG_target:-}" ]] && TARGET="${PKRCFG_target}"
[[ -n "${PKRCFG_build_arch:-}" ]] && BUILD_ARCH="${PKRCFG_build_arch}"
[[ -n "${PKRCFG_amd64_accelerator:-}" ]] && AMD64_ACCELERATOR="${PKRCFG_amd64_accelerator}"
[[ -n "${PKRCFG_arm64_accelerator:-}" ]] && ARM64_ACCELERATOR="${PKRCFG_arm64_accelerator}"
[[ -n "${PKRCFG_publish:-}" ]] && PUBLISH="$(cfg_bool "${PKRCFG_publish}")"

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
    --distro=*)
      DISTRO="${1#--distro=}"
      shift
      ;;
    --distro)
      [[ $# -ge 2 ]] || die "--distro requires a value: ubuntu|arch|centos"
      DISTRO="$2"
      shift 2
      ;;
    --gui=*)
      GUI="${1#--gui=}"
      shift
      ;;
    --gui)
      [[ $# -ge 2 ]] || die "--gui requires a value: headless|gnome|kde|xfce"
      GUI="$2"
      shift 2
      ;;
    --install_node_exporter)
      INSTALL_NODE_EXPORTER=1
      shift
      ;;
    --no_install_node_exporter)
      INSTALL_NODE_EXPORTER=0
      shift
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
    --publish|--upload)
      PUBLISH=1
      shift
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

case "${DISTRO}" in
  ubuntu|arch|centos|kali) ;;
  *) die "Invalid --distro '${DISTRO}'. Expected: ubuntu|arch|centos|kali" ;;
esac

case "${GUI}" in
  headless|gnome|kde|xfce) ;;
  *) die "Invalid --gui '${GUI}'. Expected: headless|gnome|kde|xfce" ;;
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

if bool_true "${PACKER_LOG_ENABLED}"; then
  PACKER_LOG_ENABLED="1"
else
  PACKER_LOG_ENABLED="0"
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

case "${BUILD_ARCH}" in
  amd64|arm64|both) ;;
  *) die "Invalid --build_arch '${BUILD_ARCH}'. Expected: amd64|arm64|both" ;;
esac

# Arch upstream ships no arm64 cloud image; fail fast with the reason.
if [[ "${DISTRO}" == "arch" && "${BUILD_ARCH}" != "amd64" ]]; then
  die "Arch Linux publishes no official arm64 cloud image; arm64 Arch builds are not supported. Use --build_arch amd64."
fi

case "${AMD64_ACCELERATOR}" in
  kvm|tcg|none) ;;
  *) die "Invalid --amd64_accelerator '${AMD64_ACCELERATOR}'. Expected: kvm|tcg|none" ;;
esac

case "${ARM64_ACCELERATOR}" in
  kvm|tcg|none) ;;
  *) die "Invalid --arm64_accelerator '${ARM64_ACCELERATOR}'. Expected: kvm|tcg|none" ;;
esac

for arg in ${PACKER_BUILD_ARGS[@]+"${PACKER_BUILD_ARGS[@]}"}; do
  case "${arg}" in
    -only|-only=*|-except|-except=*)
      die "Do not pass ${arg} directly. Use --build_arch amd64|arm64|both instead."
      ;;
  esac
done

# Resolve distro-specific template, build name, source prefix, and image prefix.
case "${DISTRO}" in
  ubuntu)
    TEMPLATE="${SCRIPT_DIR}/ubuntu-ndysu.pkr.hcl"
    BUILD_NAME="ubuntu-ndysu"
    SOURCE_PREFIX="ubuntu"
    IMAGE_PREFIX="ubuntu-${UBUNTU_RELEASE}-ndysu"
    ;;
  arch)
    TEMPLATE="${SCRIPT_DIR}/arch-ndysu.pkr.hcl"
    BUILD_NAME="arch-ndysu"
    SOURCE_PREFIX="arch"
    IMAGE_PREFIX="arch-ndysu"
    ;;
  centos)
    TEMPLATE="${SCRIPT_DIR}/centos-ndysu.pkr.hcl"
    BUILD_NAME="centos-ndysu"
    SOURCE_PREFIX="centos"
    IMAGE_PREFIX="centos-${CENTOS_STREAM}-ndysu"
    ;;
  kali)
    TEMPLATE="${SCRIPT_DIR}/kali-ndysu.pkr.hcl"
    BUILD_NAME="kali-ndysu"
    SOURCE_PREFIX="kali"
    IMAGE_PREFIX="kali-${KALI_RELEASE}-ndysu"
    ;;
esac
[[ -f "${TEMPLATE}" ]] || die "Template not found: ${TEMPLATE}"

UPLOAD_BASE_URL="${UPLOAD_BASE_URL:-${DEFAULT_UPLOAD_BASE_URL}}"
UPLOAD_FALLBACK_BASE_URL="${UPLOAD_FALLBACK_BASE_URL:-${DEFAULT_UPLOAD_FALLBACK_BASE_URL}}"

PACKER_ONLY_ARGS=()
case "${BUILD_ARCH}" in
  amd64)
    PACKER_ONLY_ARGS=(-only="${BUILD_NAME}.qemu.${SOURCE_PREFIX}_amd64")
    ;;
  arm64)
    PACKER_ONLY_ARGS=(-only="${BUILD_NAME}.qemu.${SOURCE_PREFIX}_arm64")
    ;;
  both)
    ;;
esac

REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
# Output into the NFS-backed data/packer directory the cloud image repository
# serves, so building publishes the artifact without a REST upload.
OUTPUT_ROOT="${PACKER_OUTPUT_ROOT:-${REPO_ROOT}/data/packer}"

# Packer's qemu builder writes directly into its output_directory and, on a
# failed/aborted build, runs "Deleting output directory..." which removes the
# qcow2 leaf but leaves the parent <prefix>/<version> folder behind. Because the
# serve dir IS the output dir, that orphaned skeleton shows up on the web server
# as an empty folder with no image. To make publishing atomic, build into a
# hidden staging root on the SAME filesystem, then rename the finished version
# dir into the served path only after the build succeeds. Failed/aborted builds
# never touch the served tree.
STAGING_ROOT="${OUTPUT_ROOT}/.staging"

if [[ "${INSTALL_NODE_EXPORTER}" -eq 1 ]]; then
  INSTALL_NODE_EXPORTER_VAR="true"
else
  INSTALL_NODE_EXPORTER_VAR="false"
fi

PACKER_VAR_ARGS=(
  -var "image_version=${VERSION}"
  -var "output_root=${STAGING_ROOT}"
  -var "gui=${GUI}"
  -var "install_node_exporter=${INSTALL_NODE_EXPORTER_VAR}"
  -var "amd64_accelerator=${AMD64_ACCELERATOR}"
)
# The arch template has no arm64 source, so it does not define arm64_accelerator.
if [[ "${DISTRO}" != "arch" ]]; then
  PACKER_VAR_ARGS+=( -var "arm64_accelerator=${ARM64_ACCELERATOR}" )
fi
case "${DISTRO}" in
  ubuntu) PACKER_VAR_ARGS+=( -var "ubuntu_release=${UBUNTU_RELEASE}" ) ;;
  centos) PACKER_VAR_ARGS+=( -var "centos_stream=${CENTOS_STREAM}" ) ;;
  arch) [[ -n "${ARCH_SNAPSHOT}" ]] && PACKER_VAR_ARGS+=( -var "arch_snapshot=${ARCH_SNAPSHOT}" ) ;;
  kali) PACKER_VAR_ARGS+=( -var "kali_release=${KALI_RELEASE}" ) ;;
esac

OUTPUT_DIR="${OUTPUT_ROOT}/${IMAGE_PREFIX}/${VERSION}"
STAGING_DIR="${STAGING_ROOT}/${IMAGE_PREFIX}/${VERSION}"
PUBLISHED=0

# On any exit before a successful atomic publish, scrub the staging tree so a
# failed/aborted build leaves no partial artifacts and no empty folders behind
# (neither in staging nor in the served tree). The served OUTPUT_DIR is only
# ever created by the rename below, so it is never left empty.
cleanup_staging() {
  rm -rf "${STAGING_DIR}" 2>/dev/null || true
  # Prune the staging root if it is now empty (ignore failure when not).
  rmdir -p "$(dirname "${STAGING_DIR}")" 2>/dev/null || true
  rmdir "${STAGING_ROOT}" 2>/dev/null || true
}
trap cleanup_staging EXIT

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

# Kali ships a .tar.xz cloud image (raw disk inside), not a bootable qcow2, so we
# extract + convert it locally before Packer runs.
if [[ "${DISTRO}" == "kali" ]]; then
  require_cmd tar
  require_cmd xz
  require_cmd sha256sum
fi

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
log "Distro: ${DISTRO}"
log "GUI: ${GUI}"
log "Host node_exporter: $([[ "${INSTALL_NODE_EXPORTER}" -eq 1 ]] && echo enabled || echo "disabled (swarm/k8s container exporter)")"
case "${DISTRO}" in
  ubuntu) log "Ubuntu release: ${UBUNTU_RELEASE}" ;;
  centos) log "CentOS stream: ${CENTOS_STREAM}" ;;
  arch) log "Arch snapshot: ${ARCH_SNAPSHOT:-<template default>}" ;;
  kali) log "Kali release: ${KALI_RELEASE}" ;;
esac
log "Host arch: ${HOST_ARCH}"
log "Target: ${TARGET}"
log "Build arch: ${BUILD_ARCH}"
log "amd64 accelerator: ${AMD64_ACCELERATOR}"
log "arm64 accelerator: ${ARM64_ACCELERATOR}"
log "Output dir: ${OUTPUT_DIR}"
log "Staging dir: ${STAGING_DIR}"
log "REST publish: $([[ "${PUBLISH}" -eq 1 ]] && echo enabled || echo "disabled (served from NFS)")"
log "Log file: ${LOG_FILE}"
if [[ "${PACKER_LOG_ENABLED}" -eq 1 ]]; then
  log "Packer debug log: ${PACKER_LOG_PATH}"
fi
log "Using template: ${TEMPLATE}"

# Clear any stale staging from a prior interrupted run. The served OUTPUT_DIR is
# left untouched until the new build succeeds, so an existing published image
# survives a failed rebuild.
if [[ -d "${STAGING_DIR}" ]]; then
  log "Removing stale staging directory: ${STAGING_DIR}"
  rm -rf "${STAGING_DIR}"
fi

# Kali: prepare (download + verify + extract + convert) the base qcow2 for each
# selected architecture, then inject the resulting local path + checksum as vars.
if [[ "${DISTRO}" == "kali" ]]; then
  prepare_kali_arch() {
    local build_arch="$1"
    log "Preparing Kali ${KALI_RELEASE} base image (${build_arch})"
    local out
    out="$("${SCRIPT_DIR}/scripts/prepare-kali-image.sh" --arch "${build_arch}" --release "${KALI_RELEASE}")" \
      || die "Failed to prepare Kali ${build_arch} base image."
    local image_path image_checksum
    image_path="$(printf '%s\n' "${out}" | sed -n 's/^KALI_IMAGE_PATH=//p')"
    image_checksum="$(printf '%s\n' "${out}" | sed -n 's/^KALI_IMAGE_CHECKSUM=//p')"
    [[ -n "${image_path}" && -n "${image_checksum}" ]] || die "prepare-kali-image.sh did not return an image path/checksum."
    log "Prepared Kali ${build_arch} image: ${image_path} (${image_checksum})"
    PACKER_VAR_ARGS+=( -var "kali_local_image_${build_arch}=${image_path}" -var "kali_${build_arch}_image_checksum=${image_checksum}" )
  }
  if [[ "${BUILD_ARCH}" == "amd64" || "${BUILD_ARCH}" == "both" ]]; then
    prepare_kali_arch amd64
  fi
  if [[ "${BUILD_ARCH}" == "arm64" || "${BUILD_ARCH}" == "both" ]]; then
    prepare_kali_arch arm64
  fi
fi

log "Running: packer init"
packer init "${TEMPLATE}"

log "Running: packer fmt"
packer fmt "${TEMPLATE}"

log "Running: packer validate"
packer validate "${PACKER_ONLY_ARGS[@]}" "${PACKER_VAR_ARGS[@]}" "${TEMPLATE}"

log "Running: packer build"
packer build -force "${PACKER_ONLY_ARGS[@]}" "${PACKER_VAR_ARGS[@]}" ${PACKER_BUILD_ARGS[@]+"${PACKER_BUILD_ARGS[@]}"} "${TEMPLATE}"

MAX_UPLOAD_BYTES="$((25 * 1024 * 1024 * 1024))"

# Build succeeded: verify the staged qcow2(s) exist, then atomically publish by
# renaming the staged version dir into the served path. Rename is atomic within
# the same filesystem (staging lives under OUTPUT_ROOT), so the web server never
# observes a partial/empty version folder.
mapfile -t STAGED_ARTIFACTS < <(find "${STAGING_DIR}" -type f -name '*.qcow2' | sort)
[[ "${#STAGED_ARTIFACTS[@]}" -gt 0 ]] || die "Build finished but no qcow2 artifacts found under staging: ${STAGING_DIR}"

log "Publishing ${#STAGED_ARTIFACTS[@]} artifact(s) to served path: ${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "$(dirname "${OUTPUT_DIR}")"
mv "${STAGING_DIR}" "${OUTPUT_DIR}"
PUBLISHED=1

mapfile -t ARTIFACT_PATHS < <(find "${OUTPUT_DIR}" -type f -name '*.qcow2' | sort)
[[ "${#ARTIFACT_PATHS[@]}" -gt 0 ]] || die "Publish moved staging but no qcow2 artifacts found under: ${OUTPUT_DIR}"

if [[ "${PUBLISH}" -ne 1 ]]; then
  log "Artifacts written to the NFS-backed serve dir; skipping REST upload (--publish to enable):"
  for ARTIFACT_PATH in "${ARTIFACT_PATHS[@]}"; do
    log "  ${ARTIFACT_PATH}"
  done
  log "Build complete"
  exit 0
fi

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
