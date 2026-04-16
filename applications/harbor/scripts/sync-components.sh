#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARBOR_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${HARBOR_DIR}/versions.env"

if [[ ! -f "${VERSIONS_FILE}" ]]; then
  echo "[ERR] Missing versions file: ${VERSIONS_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${VERSIONS_FILE}"

HARBOR_VERSION="${HARBOR_VERSION:-}"
HARBOR_SOURCE_REPO="${HARBOR_SOURCE_REPO:-}"
KEEP_WORKDIR="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      HARBOR_VERSION="$2"
      shift 2
      ;;
    --repo)
      HARBOR_SOURCE_REPO="$2"
      shift 2
      ;;
    --keep-workdir)
      KEEP_WORKDIR="1"
      shift
      ;;
    *)
      echo "[ERR] Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "${HARBOR_VERSION}" || -z "${HARBOR_SOURCE_REPO}" ]]; then
  echo "[ERR] HARBOR_VERSION and HARBOR_SOURCE_REPO must be set." >&2
  exit 1
fi

for cmd in git; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERR] Required command not found: ${cmd}" >&2
    exit 1
  fi
done

WORKDIR="$(mktemp -d)"
cleanup() {
  if [[ "${KEEP_WORKDIR}" == "1" ]]; then
    echo "[INFO] Keeping workdir: ${WORKDIR}"
  else
    rm -rf "${WORKDIR}"
  fi
}
trap cleanup EXIT

REPO_DIR="${WORKDIR}/harbor"

echo "[INFO] Cloning ${HARBOR_SOURCE_REPO} @ ${HARBOR_VERSION}"
git clone --depth 1 --branch "${HARBOR_VERSION}" "${HARBOR_SOURCE_REPO}" "${REPO_DIR}" >/dev/null

components=(
  prepare
  core
  db
  jobservice
  log
  nginx
  portal
  redis
  registry
  registryctl
  trivy-adapter
  exporter
  standalone-db-migrator
)

for component in "${components[@]}"; do
  src_dir="${REPO_DIR}/make/photon/${component}"
  dst_dir="${HARBOR_DIR}/${component}"

  if [[ ! -d "${src_dir}" ]]; then
    echo "[ERR] Missing upstream component directory: ${src_dir}" >&2
    exit 1
  fi

  rm -rf "${dst_dir}"
  mkdir -p "${dst_dir}"
  cp -a "${src_dir}/." "${dst_dir}/"
  echo "[SYNC] ${component}"
done

rm -rf "${HARBOR_DIR}/common"
mkdir -p "${HARBOR_DIR}/common"
cp -a "${REPO_DIR}/make/photon/common/." "${HARBOR_DIR}/common/"

cat > "${HARBOR_DIR}/UPSTREAM_VERSION" <<META
repo=${HARBOR_SOURCE_REPO}
version=${HARBOR_VERSION}
synced_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
META

echo "[DONE] Harbor component files synced into ${HARBOR_DIR}"
