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
HARBOR_IMAGE_TAG="${HARBOR_IMAGE_TAG:-}"

IMAGE_NAMESPACE=""
PLATFORMS_CSV="linux/amd64,linux/arm64"
PUSH_IMAGES="0"
INSTALL_BINFMT="0"

usage() {
  cat <<USAGE
Usage: $(basename "$0") --namespace <registry/namespace> [options]

Builds Harbor images per architecture and optionally publishes multi-arch manifests.

Required:
  --namespace <value>      Image namespace prefix (example: registry.example.com/homelab)

Options:
  --version <value>        Harbor git tag (default from versions.env)
  --tag <value>            Output image tag (default from versions.env)
  --platforms <csv>        Target platforms (default: linux/amd64,linux/arm64)
  --push                   Push arch tags and publish manifest tags
  --install-binfmt         Install qemu/binfmt via tonistiigi/binfmt before build
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      IMAGE_NAMESPACE="$2"
      shift 2
      ;;
    --version)
      HARBOR_VERSION="$2"
      shift 2
      ;;
    --tag)
      HARBOR_IMAGE_TAG="$2"
      shift 2
      ;;
    --platforms)
      PLATFORMS_CSV="$2"
      shift 2
      ;;
    --push)
      PUSH_IMAGES="1"
      shift
      ;;
    --install-binfmt)
      INSTALL_BINFMT="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERR] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${IMAGE_NAMESPACE}" ]]; then
  echo "[ERR] --namespace is required." >&2
  usage >&2
  exit 2
fi

if [[ -z "${HARBOR_VERSION}" || -z "${HARBOR_SOURCE_REPO}" || -z "${HARBOR_IMAGE_TAG}" ]]; then
  echo "[ERR] HARBOR_VERSION, HARBOR_SOURCE_REPO, and HARBOR_IMAGE_TAG must be set." >&2
  exit 1
fi

for cmd in docker git make curl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERR] Required command not found: ${cmd}" >&2
    exit 1
  fi
done

if [[ "${INSTALL_BINFMT}" == "1" ]]; then
  echo "[INFO] Installing binfmt emulation"
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

IFS=',' read -r -a PLATFORMS <<<"${PLATFORMS_CSV}"
if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
  echo "[ERR] No target platforms provided." >&2
  exit 1
fi

runtime_images=(
  harbor-core
  harbor-portal
  harbor-jobservice
  harbor-registryctl
  harbor-db
  registry-photon
  redis-photon
  nginx-photon
  harbor-log
  trivy-adapter-photon
  harbor-exporter
  prepare
)

build_for_platform() {
  local platform="$1"
  local os arch variant
  IFS='/' read -r os arch variant <<<"${platform}"

  if [[ "${os}" != "linux" || -z "${arch}" ]]; then
    echo "[ERR] Unsupported platform format: ${platform}" >&2
    exit 1
  fi

  local arch_tag="${HARBOR_IMAGE_TAG}-${arch}"
  local workdir repo_dir
  workdir="$(mktemp -d)"
  repo_dir="${workdir}/harbor"

  trap 'rm -rf "${workdir}"' RETURN

  echo "[INFO] Cloning ${HARBOR_SOURCE_REPO} @ ${HARBOR_VERSION} for ${platform}"
  git clone --depth 1 --branch "${HARBOR_VERSION}" "${HARBOR_SOURCE_REPO}" "${repo_dir}" >/dev/null

  pushd "${repo_dir}" >/dev/null

  echo "[INFO] Preflight platform runtime check: ${platform}"
  if ! docker run --rm --platform "${platform}" alpine:3.20 true >/dev/null 2>&1; then
    echo "[ERR] ${platform} containers cannot run on this host (missing binfmt/qemu)." >&2
    echo "[HINT] Re-run with --install-binfmt or build on native ${arch} hardware." >&2
    exit 1
  fi

  local trivy_platform_suffix trivy_version fallback_trivy_version effective_trivy_version trivy_download_url
  case "${arch}" in
    amd64)
      trivy_platform_suffix="Linux-64bit"
      ;;
    arm64)
      trivy_platform_suffix="Linux-ARM64"
      ;;
    *)
      echo "[ERR] Unsupported arch for Trivy download mapping: ${arch}" >&2
      exit 1
      ;;
  esac

  trivy_version="$(awk -F'=' '/^TRIVYVERSION=/{print $2; exit}' Makefile)"
  if [[ -z "${trivy_version}" ]]; then
    echo "[ERR] Failed to resolve TRIVYVERSION from Makefile" >&2
    exit 1
  fi

  fallback_trivy_version="${TRIVY_FALLBACK_VERSION:-v0.69.3}"
  effective_trivy_version="${trivy_version}"
  trivy_download_url="https://github.com/aquasecurity/trivy/releases/download/${effective_trivy_version}/trivy_${effective_trivy_version#v}_${trivy_platform_suffix}.tar.gz"

  if ! curl -fsIL -o /dev/null "${trivy_download_url}"; then
    echo "[WARN] Trivy URL unavailable for ${effective_trivy_version} on ${arch}; trying fallback ${fallback_trivy_version}" >&2
    effective_trivy_version="${fallback_trivy_version}"
    trivy_download_url="https://github.com/aquasecurity/trivy/releases/download/${effective_trivy_version}/trivy_${effective_trivy_version#v}_${trivy_platform_suffix}.tar.gz"
    if ! curl -fsIL -o /dev/null "${trivy_download_url}"; then
      echo "[ERR] Trivy URL unavailable even after fallback: ${trivy_download_url}" >&2
      exit 1
    fi
  fi

  echo "[INFO] Trivy version for ${arch}: ${effective_trivy_version}"
  echo "[INFO] Trivy URL for ${arch}: ${trivy_download_url}"

  echo "[BUILD] make compile (${platform})"
  env \
    DOCKER_DEFAULT_PLATFORM="${platform}" \
    VERSIONTAG="${arch_tag}" \
    BASEIMAGETAG="${arch_tag}" \
    IMAGENAMESPACE="${IMAGE_NAMESPACE}" \
    BASEIMAGENAMESPACE="${IMAGE_NAMESPACE}" \
    DEVFLAG="false" \
    TRIVYFLAG="true" \
    TRIVYVERSION="${effective_trivy_version}" \
    BUILD_INSTALLER="true" \
    BUILD_BASE="true" \
    TRIVY_DOWNLOAD_URL="${trivy_download_url}" \
    PULL_BASE_FROM_DOCKERHUB="false" \
    make -e compile

  echo "[BUILD] make build (${platform})"
  env \
    DOCKER_DEFAULT_PLATFORM="${platform}" \
    VERSIONTAG="${arch_tag}" \
    BASEIMAGETAG="${arch_tag}" \
    IMAGENAMESPACE="${IMAGE_NAMESPACE}" \
    BASEIMAGENAMESPACE="${IMAGE_NAMESPACE}" \
    DEVFLAG="false" \
    TRIVYFLAG="true" \
    TRIVYVERSION="${effective_trivy_version}" \
    BUILD_INSTALLER="true" \
    BUILD_BASE="true" \
    TRIVY_DOWNLOAD_URL="${trivy_download_url}" \
    PULL_BASE_FROM_DOCKERHUB="false" \
    make -e build

  if [[ "${PUSH_IMAGES}" == "1" ]]; then
    for image in "${runtime_images[@]}"; do
      echo "[PUSH] ${IMAGE_NAMESPACE}/${image}:${arch_tag}"
      docker push "${IMAGE_NAMESPACE}/${image}:${arch_tag}"
    done
  fi

  popd >/dev/null
  rm -rf "${workdir}"
  trap - RETURN
}

declare -A arch_to_platform
for platform in "${PLATFORMS[@]}"; do
  IFS='/' read -r os arch variant <<<"${platform}"
  if [[ "${os}" != "linux" || -z "${arch}" ]]; then
    echo "[ERR] Unsupported platform format: ${platform}" >&2
    exit 1
  fi
  arch_to_platform["${arch}"]="${platform}"
done

for platform in "${PLATFORMS[@]}"; do
  build_for_platform "${platform}"
done

if [[ "${PUSH_IMAGES}" == "1" ]]; then
  echo "[INFO] Publishing manifest tags for ${HARBOR_IMAGE_TAG}"

  for image in "${runtime_images[@]}"; do
    manifest_ref="${IMAGE_NAMESPACE}/${image}:${HARBOR_IMAGE_TAG}"

    refs=()
    for platform in "${PLATFORMS[@]}"; do
      IFS='/' read -r os arch variant <<<"${platform}"
      refs+=("${IMAGE_NAMESPACE}/${image}:${HARBOR_IMAGE_TAG}-${arch}")
    done

    docker manifest rm "${manifest_ref}" >/dev/null 2>&1 || true
    docker manifest create "${manifest_ref}" "${refs[@]}"

    for platform in "${PLATFORMS[@]}"; do
      IFS='/' read -r os arch variant <<<"${platform}"
      ref="${IMAGE_NAMESPACE}/${image}:${HARBOR_IMAGE_TAG}-${arch}"
      if [[ -n "${variant:-}" ]]; then
        docker manifest annotate "${manifest_ref}" "${ref}" --os "${os}" --arch "${arch}" --variant "${variant}"
      else
        docker manifest annotate "${manifest_ref}" "${ref}" --os "${os}" --arch "${arch}"
      fi
    done

    docker manifest push --purge "${manifest_ref}"
  done
fi

echo "[DONE] Harbor build workflow finished."
echo "[INFO] Image prefix: ${IMAGE_NAMESPACE}/<component>:${HARBOR_IMAGE_TAG}"
