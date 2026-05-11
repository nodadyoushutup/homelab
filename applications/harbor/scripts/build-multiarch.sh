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
PATH_MODE="namespace-component"
MANIFEST_ONLY="0"
NO_MANIFEST_PUBLISH="0"
MAKE_HELPER_IMAGE="${MAKE_HELPER_IMAGE:-docker:27-cli}"
HAS_HOST_MAKE="0"
MAKE_HELPER_ANNOUNCED="0"

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
  --path-mode <value>      Publish path layout:
                           namespace-component => <namespace>/<component>:<tag>
                           project-per-image   => <namespace>/<component>/<component>:<tag>
  --push                   Push arch tags and publish manifest tags (unless --no-manifest-publish)
  --no-manifest-publish    With --push: push per-arch tags only (for split CI jobs; manifests separately)
  --manifest-only          Skip builds; create and push multi-arch manifests for existing per-arch tags
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
    --path-mode)
      PATH_MODE="$2"
      shift 2
      ;;
    --push)
      PUSH_IMAGES="1"
      shift
      ;;
    --no-manifest-publish)
      NO_MANIFEST_PUBLISH="1"
      shift
      ;;
    --manifest-only)
      MANIFEST_ONLY="1"
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

case "${PATH_MODE}" in
  namespace-component|project-per-image)
    ;;
  *)
    echo "[ERR] Unsupported --path-mode: ${PATH_MODE}" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "${MANIFEST_ONLY}" == "1" ]]; then
  if [[ -z "${HARBOR_IMAGE_TAG}" ]]; then
    echo "[ERR] --tag is required with --manifest-only." >&2
    exit 1
  fi
else
  if [[ -z "${HARBOR_VERSION}" || -z "${HARBOR_SOURCE_REPO}" || -z "${HARBOR_IMAGE_TAG}" ]]; then
    echo "[ERR] HARBOR_VERSION, HARBOR_SOURCE_REPO, and HARBOR_IMAGE_TAG must be set." >&2
    exit 1
  fi
fi

if [[ "${MANIFEST_ONLY}" == "1" ]]; then
  for cmd in docker; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "[ERR] Required command not found: ${cmd}" >&2
      exit 1
    fi
  done
else
  for cmd in docker git curl; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      echo "[ERR] Required command not found: ${cmd}" >&2
      exit 1
    fi
  done
fi

# Harbor's Makefile parses `$(shell go env GOPATH)` even for targets that compile inside
# golang Docker images. Prefer host make only when both make and go exist; otherwise
# keep using the docker CLI helper (apk installs make there). Installing only `make`
# on a runner would skip the helper but still lack Go — noisy and unlike the intended path.
if command -v make >/dev/null 2>&1 && command -v go >/dev/null 2>&1; then
  HAS_HOST_MAKE="1"
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

publish_image_ref() {
  local image="$1"
  local tag="$2"

  case "${PATH_MODE}" in
    namespace-component)
      printf '%s/%s:%s\n' "${IMAGE_NAMESPACE}" "${image}" "${tag}"
      ;;
    project-per-image)
      printf '%s/%s/%s:%s\n' "${IMAGE_NAMESPACE}" "${image}" "${image}" "${tag}"
      ;;
  esac
}

publish_multiarch_manifests() {
  echo "[INFO] Publishing manifest tags for ${HARBOR_IMAGE_TAG}"

  for image in "${runtime_images[@]}"; do
    local manifest_ref ref os arch variant
    manifest_ref="$(publish_image_ref "${image}" "${HARBOR_IMAGE_TAG}")"

    local -a refs=()
    for platform in "${PLATFORMS[@]}"; do
      IFS='/' read -r os arch variant <<<"${platform}"
      refs+=("$(publish_image_ref "${image}" "${HARBOR_IMAGE_TAG}-${arch}")")
    done

    docker manifest rm "${manifest_ref}" >/dev/null 2>&1 || true
    docker manifest create "${manifest_ref}" "${refs[@]}"

    for platform in "${PLATFORMS[@]}"; do
      IFS='/' read -r os arch variant <<<"${platform}"
      ref="$(publish_image_ref "${image}" "${HARBOR_IMAGE_TAG}-${arch}")"
      if [[ -n "${variant:-}" ]]; then
        docker manifest annotate "${manifest_ref}" "${ref}" --os "${os}" --arch "${arch}" --variant "${variant}"
      else
        docker manifest annotate "${manifest_ref}" "${ref}" --os "${os}" --arch "${arch}"
      fi
    done

    docker manifest push --purge "${manifest_ref}"
  done
}

run_make_target() {
  local repo_dir="$1"
  local target="$2"
  shift 2
  local -a env_pairs=("$@")

  if [[ "${HAS_HOST_MAKE}" == "1" ]]; then
    (
      cd "${repo_dir}"
      env "TERM=${TERM:-xterm}" "${env_pairs[@]}" make -e "${target}"
    )
    return
  fi

  local -a docker_args env_args
  docker_args=(
    --rm
    # Official docker:*-cli entrypoint rewrites argv (docker help "$1"); run plain sh.
    --entrypoint sh
    -v /var/run/docker.sock:/var/run/docker.sock
    # Harbor's make targets launch nested docker builds through the host daemon.
    # Mount the repo at the same absolute host path so those nested bind mounts
    # resolve correctly outside the helper container as well.
    -v "${repo_dir}:${repo_dir}"
    -w "${repo_dir}"
  )
  env_args=()

  if [[ -d "${HOME:-}/.docker" ]]; then
    docker_args+=(-v "${HOME}/.docker:/root/.docker:ro")
  fi

  for pair in "${env_pairs[@]}"; do
    env_args+=(-e "${pair}")
  done

  # Entrypoint bypass skips auto DOCKER_HOST; socket is mounted at the default path.
  env_args+=(-e "DOCKER_HOST=unix:///var/run/docker.sock")

  if [[ "${MAKE_HELPER_ANNOUNCED}" == "0" ]]; then
    echo "[WARN] Host make+go not both available; using ${MAKE_HELPER_IMAGE} helper container." >&2
    MAKE_HELPER_ANNOUNCED="1"
  fi

  # Pass the make goal via sh -c positional args (POSIX: sh -c '...' name arg1 → $1=arg1).
  # Avoid -l (login) and env-only passing; both broke compile vs build on some runners.
  docker run \
    "${docker_args[@]}" \
    "${env_args[@]}" \
    "${MAKE_HELPER_IMAGE}" \
    -c '
      set -eu
      apk add --no-cache bash coreutils curl git make >/dev/null
      export TERM="${TERM:-xterm}"
      git config --global --add safe.directory "$PWD"
      test -f Makefile || {
        echo "[ERR] No Makefile in $(pwd) (repo mount or working dir wrong)." >&2
        exit 1
      }
      if [ -z "${1:-}" ]; then
        echo "[ERR] make goal missing (helper argv bug)." >&2
        exit 1
      fi
      exec make -e "$1"
    ' _ "${target}"
}

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

  # Spectral v6 may not pick up .spectral.yaml in some docker/CI runs; upstream invokes
  # `spectral lint ./api/v2.0/swagger.yaml` without -r. Pin the ruleset path like the CLI docs recommend.
  makefile="${repo_dir}/Makefile"
  if [[ -f "${makefile}" ]] && grep -Fq '$(SPECTRAL) lint ./api/v2.0/swagger.yaml' "${makefile}" &&
    ! grep -Fq '$(SPECTRAL) lint -r .spectral.yaml ./api/v2.0/swagger.yaml' "${makefile}"; then
    python3 -c '
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = "$(SPECTRAL) lint ./api/v2.0/swagger.yaml"
new = "$(SPECTRAL) lint -r .spectral.yaml ./api/v2.0/swagger.yaml"
if old in text and new not in text:
    p.write_text(text.replace(old, new, 1))
' "${makefile}"
  fi

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

  local -a build_env
  build_env=(
    "DOCKER_DEFAULT_PLATFORM=${platform}"
    "VERSIONTAG=${arch_tag}"
    "BASEIMAGETAG=${arch_tag}"
    "IMAGENAMESPACE=${IMAGE_NAMESPACE}"
    "BASEIMAGENAMESPACE=${IMAGE_NAMESPACE}"
    "DEVFLAG=false"
    "TRIVYFLAG=true"
    "TRIVYVERSION=${effective_trivy_version}"
    "BUILD_INSTALLER=true"
    "BUILD_BASE=true"
    "TRIVY_DOWNLOAD_URL=${trivy_download_url}"
    "PULL_BASE_FROM_DOCKERHUB=false"
  )

  # Harbor Makefile builds tool images (spectral, swagger) with `docker build` then
  # runs `docker run`. If the active buildx builder uses the docker-container driver,
  # BuildKit keeps the image only in cache ("No output specified with docker-container
  # driver"); the image never appears in the local engine and lint_apis/gen_apis fail.
  if docker buildx version >/dev/null 2>&1 && docker buildx inspect default >/dev/null 2>&1; then
    echo "[INFO] buildx use default (docker driver) for Harbor Makefile docker builds"
    docker buildx use default
  fi

  echo "[BUILD] make compile (${platform})"
  run_make_target "${repo_dir}" compile "${build_env[@]}"

  echo "[BUILD] make build (${platform})"
  run_make_target "${repo_dir}" build "${build_env[@]}"

  if [[ "${PUSH_IMAGES}" == "1" ]]; then
    for image in "${runtime_images[@]}"; do
      local source_ref target_ref
      source_ref="${IMAGE_NAMESPACE}/${image}:${arch_tag}"
      target_ref="$(publish_image_ref "${image}" "${arch_tag}")"

      if [[ "${source_ref}" != "${target_ref}" ]]; then
        docker tag "${source_ref}" "${target_ref}"
      fi

      echo "[PUSH] ${target_ref}"
      docker push "${target_ref}"
    done
  fi

  popd >/dev/null
  rm -rf "${workdir}"
  trap - RETURN
}

IFS=',' read -r -a PLATFORMS <<<"${PLATFORMS_CSV}"
if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
  echo "[ERR] No target platforms provided." >&2
  exit 1
fi

if [[ "${MANIFEST_ONLY}" == "1" ]]; then
  publish_multiarch_manifests
  echo "[DONE] Harbor manifest publish finished."
  case "${PATH_MODE}" in
    namespace-component)
      echo "[INFO] Image prefix: ${IMAGE_NAMESPACE}/<component>:${HARBOR_IMAGE_TAG}"
      ;;
    project-per-image)
      echo "[INFO] Image prefix: ${IMAGE_NAMESPACE}/<component>/<component>:${HARBOR_IMAGE_TAG}"
      ;;
  esac
  exit 0
fi

if [[ "${INSTALL_BINFMT}" == "1" ]]; then
  echo "[INFO] Installing binfmt emulation"
  docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
fi

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

if [[ "${PUSH_IMAGES}" == "1" && "${NO_MANIFEST_PUBLISH}" == "0" ]]; then
  publish_multiarch_manifests
fi

echo "[DONE] Harbor build workflow finished."
case "${PATH_MODE}" in
  namespace-component)
    echo "[INFO] Image prefix: ${IMAGE_NAMESPACE}/<component>:${HARBOR_IMAGE_TAG}"
    ;;
  project-per-image)
    echo "[INFO] Image prefix: ${IMAGE_NAMESPACE}/<component>/<component>:${HARBOR_IMAGE_TAG}"
    ;;
esac
