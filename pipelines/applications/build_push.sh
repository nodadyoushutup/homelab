#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"

GHCR_NAMESPACE_DEFAULT="ghcr.io/nodadyoushutup"
HARBOR_REGISTRY_DEFAULT="harbor.nodadyoushutup.com"
# Harbor project (flat namespace before repo name): registry/<project>/<repo>:<tag>
HARBOR_PROJECT_DEFAULT="homelab"

log() {
  printf '[docker-pipeline] %s\n' "$*"
}

die() {
  printf '[docker-pipeline] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF_USAGE'
Usage: pipelines/applications/build_push.sh --version <version> --target_registry <github|harbor|both> --build_target <target> [options]

Emulates the repo's Docker GitHub Actions workflow with a repo-native bash
entrypoint.

Required:
  --version <X.Y.Z>                Version tag to publish
  --target_registry <value>        Registry target: github, harbor, or both
  --build_target <value>           Build target from the workflow target list

Options:
  --build_platforms <value>        both, amd64, or arm64 (default: both)
  --phase <value>                  all, build-direct-arch, publish-direct-manifest,
                                   or build-harbor-runtime-set (default: all)
  --native_arch <value>            amd64 or arm64; required for build-direct-arch
  --install_binfmt                 Install qemu/binfmt before cross-arch builds
  --github_username <value>        Override GHCR username
  --github_token <value>           Override GHCR token/PAT
  --harbor_username <value>        Override Harbor username
  --harbor_password <value>        Override Harbor password
  -h, --help                       Show this help

Environment fallbacks:
  GHCR_USERNAME / GITHUB_ACTOR
  GHCR_TOKEN / GITHUB_TOKEN
  HARBOR_PROJECT (default: homelab; Harbor project segment before image name)
  HARBOR_USERNAME
  HARBOR_PASSWORD
EOF_USAGE
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Missing required command: ${cmd}"
}

ensure_buildx() {
  require_cmd docker
  docker buildx version >/dev/null 2>&1 || die "docker buildx is required"
  if ! docker buildx inspect >/dev/null 2>&1; then
    docker buildx create --name homelab-pipelines --use >/dev/null
  fi
  docker buildx inspect --bootstrap >/dev/null
}

install_binfmt_if_requested() {
  if [[ "${INSTALL_BINFMT}" == "1" ]]; then
    log "Installing qemu/binfmt handlers"
    docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null
  fi
}

registry_login() {
  require_cmd docker

  case "${TARGET_REGISTRY}" in
    both)
      registry_login_github
      registry_login_harbor
      ;;
    github)
      registry_login_github
      ;;
    harbor)
      registry_login_harbor
      ;;
    *)
      die "Unsupported target_registry: ${TARGET_REGISTRY}"
      ;;
  esac
}

registry_login_github() {
  local username token
  username="${GITHUB_USERNAME:-${GHCR_USERNAME:-${GITHUB_ACTOR:-}}}"
  token="${GITHUB_TOKEN_VALUE:-${GHCR_TOKEN:-${GITHUB_TOKEN:-}}}"

  [[ -n "${username}" ]] || die "GitHub registry username is required via --github_username, GHCR_USERNAME, or GITHUB_ACTOR"
  [[ -n "${token}" ]] || die "GitHub registry token is required via --github_token, GHCR_TOKEN, or GITHUB_TOKEN"

  printf '%s' "${token}" | docker login ghcr.io --username "${username}" --password-stdin >/dev/null
}

registry_login_harbor() {
  local username password
  username="${HARBOR_USERNAME_VALUE:-${HARBOR_USERNAME:-}}"
  password="${HARBOR_PASSWORD_VALUE:-${HARBOR_PASSWORD:-}}"

  [[ -n "${username}" ]] || die "Harbor username is required via --harbor_username or HARBOR_USERNAME"
  [[ -n "${password}" ]] || die "Harbor password is required via --harbor_password or HARBOR_PASSWORD"

  printf '%s' "${password}" | docker login "${HARBOR_REGISTRY}" --username "${username}" --password-stdin >/dev/null
}

resolve_build_target() {
  SUPPORTED_PLATFORMS="linux/amd64,linux/arm64"
  BUILD_STRATEGY=""
  IMAGE_NAME=""
  DOCKER_CONTEXT=""
  DOCKERFILE=""

  case "${BUILD_TARGET}" in
    cloud-image-repository)
      IMAGE_NAME="cloud-image-repository"
      DOCKER_CONTEXT="applications/cloud-image-repository"
      BUILD_STRATEGY="direct"
      ;;
    gha-runner)
      IMAGE_NAME="gha-runner"
      DOCKER_CONTEXT="."
      DOCKERFILE="applications/gha-runner/Dockerfile"
      BUILD_STRATEGY="direct"
      ;;
    harbor-runtime-set)
      IMAGE_NAME="harbor-runtime-set"
      DOCKER_CONTEXT="applications/harbor"
      BUILD_STRATEGY="harbor-runtime-set"
      ;;
    jenkins-agent)
      IMAGE_NAME="jenkins-agent"
      DOCKER_CONTEXT="."
      DOCKERFILE="applications/jenkins-agent/Dockerfile"
      BUILD_STRATEGY="direct"
      ;;
    jenkins-controller)
      IMAGE_NAME="jenkins-controller"
      DOCKER_CONTEXT="."
      DOCKERFILE="applications/jenkins-controller/Dockerfile"
      BUILD_STRATEGY="direct"
      ;;
    langchain-agent-chat)
      IMAGE_NAME="langchain-agent-chat"
      DOCKER_CONTEXT="applications/langchain-agent-chat"
      SUPPORTED_PLATFORMS="linux/amd64"
      BUILD_STRATEGY="direct"
      ;;
    langgraph)
      IMAGE_NAME="langgraph"
      DOCKER_CONTEXT="applications/langgraph"
      DOCKERFILE="applications/langgraph/docker/Dockerfile"
      SUPPORTED_PLATFORMS="linux/amd64"
      BUILD_STRATEGY="direct"
      ;;
    mcp-atlassian)
      IMAGE_NAME="mcp-atlassian"
      DOCKER_CONTEXT="applications/mcp-atlassian"
      BUILD_STRATEGY="direct"
      ;;
    mcp-cloudflare)
      IMAGE_NAME="mcp-cloudflare"
      DOCKER_CONTEXT="applications/mcp-cloudflare"
      BUILD_STRATEGY="direct"
      ;;
    mcp-code)
      IMAGE_NAME="mcp-code"
      DOCKER_CONTEXT="."
      DOCKERFILE="applications/mcp-code/Dockerfile"
      BUILD_STRATEGY="direct"
      ;;
    mcp-fortigate)
      IMAGE_NAME="mcp-fortigate"
      DOCKER_CONTEXT="applications/mcp-fortigate"
      BUILD_STRATEGY="direct"
      ;;
    mcp-github)
      IMAGE_NAME="mcp-github"
      DOCKER_CONTEXT="applications/mcp-github"
      BUILD_STRATEGY="direct"
      ;;
    mcp-google-workspace)
      IMAGE_NAME="mcp-google-workspace"
      DOCKER_CONTEXT="applications/mcp-google-workspace"
      BUILD_STRATEGY="direct"
      ;;
    mcp-rag)
      IMAGE_NAME="mcp-rag"
      DOCKER_CONTEXT="applications/mcp-rag"
      BUILD_STRATEGY="direct"
      ;;
    mcp-terraform)
      IMAGE_NAME="mcp-terraform"
      DOCKER_CONTEXT="applications/mcp-terraform"
      BUILD_STRATEGY="direct"
      ;;
    rag-engine)
      IMAGE_NAME="rag-engine"
      DOCKER_CONTEXT="applications/rag-engine"
      BUILD_STRATEGY="direct"
      ;;
    *)
      die "Unsupported build target: ${BUILD_TARGET}"
      ;;
  esac

  if [[ "${BUILD_STRATEGY}" == "direct" ]]; then
    DOCKERFILE="${DOCKERFILE:-${DOCKER_CONTEXT}/Dockerfile}"
    [[ -f "${ROOT_DIR}/${DOCKERFILE}" ]] || die "Dockerfile not found: ${DOCKERFILE}"
  fi
}

resolve_registry_target() {
  case "${TARGET_REGISTRY}" in
    both)
      PUBLISH_GITHUB="1"
      PUBLISH_HARBOR="1"
      ;;
    github)
      PUBLISH_GITHUB="1"
      PUBLISH_HARBOR="0"
      ;;
    harbor)
      PUBLISH_GITHUB="0"
      PUBLISH_HARBOR="1"
      ;;
    *)
      die "Unsupported target_registry: ${TARGET_REGISTRY}"
      ;;
  esac

  GHCR_IMAGE_BASE=""
  HARBOR_IMAGE_BASE=""

  if [[ "${BUILD_STRATEGY}" == "direct" ]]; then
    if [[ "${PUBLISH_GITHUB}" == "1" ]]; then
      GHCR_IMAGE_BASE="${GHCR_NAMESPACE}/${IMAGE_NAME}"
    fi

    if [[ "${PUBLISH_HARBOR}" == "1" ]]; then
      HARBOR_IMAGE_BASE="${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}"
    fi
  fi
}

resolve_platforms() {
  local requested_csv

  case "${BUILD_PLATFORMS}" in
    both) requested_csv="linux/amd64,linux/arm64" ;;
    amd64) requested_csv="linux/amd64" ;;
    arm64) requested_csv="linux/arm64" ;;
    *) die "Unsupported build_platforms selection: ${BUILD_PLATFORMS}" ;;
  esac

  FILTERED_PLATFORMS=()
  IFS=',' read -r -a supported_platform_list <<<"${SUPPORTED_PLATFORMS}"
  for platform in "${supported_platform_list[@]}"; do
    [[ -n "${platform}" ]] || continue
    case ",${requested_csv}," in
      *,"${platform}",*) FILTERED_PLATFORMS+=("${platform}") ;;
    esac
  done

  [[ "${#FILTERED_PLATFORMS[@]}" -gt 0 ]] || die "Build target ${BUILD_TARGET} does not support requested build_platforms=${BUILD_PLATFORMS}"

  PLATFORMS_CSV="$(IFS=,; echo "${FILTERED_PLATFORMS[*]}")"
  BUILD_AMD64="0"
  BUILD_ARM64="0"
  for platform in "${FILTERED_PLATFORMS[@]}"; do
    case "${platform}" in
      linux/amd64) BUILD_AMD64="1" ;;
      linux/arm64) BUILD_ARM64="1" ;;
    esac
  done
}

build_direct_arch() {
  local arch="$1"
  local -a image_refs tag_args
  local image_ref
  image_refs=()
  tag_args=()

  if [[ "${PUBLISH_GITHUB}" == "1" ]]; then
    image_ref="${GHCR_IMAGE_BASE}:${VERSION}-${arch}"
    image_refs+=("${image_ref}")
    tag_args+=(--tag "${image_ref}")
  fi

  if [[ "${PUBLISH_HARBOR}" == "1" ]]; then
    image_ref="${HARBOR_IMAGE_BASE}:${VERSION}-${arch}"
    image_refs+=("${image_ref}")
    tag_args+=(--tag "${image_ref}")
  fi

  [[ "${#image_refs[@]}" -gt 0 ]] || die "No registry targets were prepared for publish"

  ensure_buildx

  log "Building ${IMAGE_NAME}:${VERSION}-${arch} from ${DOCKERFILE} for ${TARGET_REGISTRY}"
  (
    cd "${ROOT_DIR}"
    docker buildx build \
      --platform "linux/${arch}" \
      --provenance=false \
      --file "${DOCKERFILE}" \
      --load \
      "${tag_args[@]}" \
      "${DOCKER_CONTEXT}"
  )

  for image_ref in "${image_refs[@]}"; do
    log "Pushing ${image_ref}"
    docker push "${image_ref}"
  done
}

publish_direct_manifests() {
  export DOCKER_CLI_EXPERIMENTAL=enabled

  publish_manifest_for_base() {
    local image_base="$1"
    local refs=()
    local ref arch

    if [[ "${BUILD_AMD64}" == "1" ]]; then
      refs+=("${image_base}:${VERSION}-amd64")
    fi
    if [[ "${BUILD_ARM64}" == "1" ]]; then
      refs+=("${image_base}:${VERSION}-arm64")
    fi

    [[ "${#refs[@]}" -gt 0 ]] || die "No per-architecture image refs were prepared for manifest publish"

    docker manifest rm "${image_base}:${VERSION}" >/dev/null 2>&1 || true
    docker manifest create "${image_base}:${VERSION}" "${refs[@]}"

    docker manifest rm "${image_base}:latest" >/dev/null 2>&1 || true
    docker manifest create "${image_base}:latest" "${refs[@]}"

    for ref in "${refs[@]}"; do
      arch="${ref##*-}"
      docker manifest annotate "${image_base}:${VERSION}" "${ref}" --os linux --arch "${arch}"
      docker manifest annotate "${image_base}:latest" "${ref}" --os linux --arch "${arch}"
    done

    log "Publishing manifest tags ${image_base}:${VERSION} and ${image_base}:latest"
    docker manifest push "${image_base}:${VERSION}"
    docker manifest push "${image_base}:latest"
  }

  if [[ "${PUBLISH_GITHUB}" == "1" ]]; then
    publish_manifest_for_base "${GHCR_IMAGE_BASE}"
  fi

  if [[ "${PUBLISH_HARBOR}" == "1" ]]; then
    publish_manifest_for_base "${HARBOR_IMAGE_BASE}"
  fi
}

build_harbor_runtime_set() {
  publish_runtime_set() {
    local namespace="$1"
    local path_mode="$2"
    local -a args

    args=(
      --namespace "${namespace}"
      --tag "${VERSION}"
      --path-mode "${path_mode}"
      --platforms "${PLATFORMS_CSV}"
      --push
    )

    if [[ "${INSTALL_BINFMT}" == "1" ]]; then
      args+=(--install-binfmt)
    fi

    log "Building Harbor runtime set:${VERSION} for ${PLATFORMS_CSV} into ${namespace}"
    (
      cd "${ROOT_DIR}"
      chmod 0755 applications/harbor/scripts/build-multiarch.sh
      applications/harbor/scripts/build-multiarch.sh "${args[@]}"
    )
  }

  if [[ "${PUBLISH_GITHUB}" == "1" ]]; then
    publish_runtime_set "${GHCR_NAMESPACE}" "namespace-component"
  fi

  if [[ "${PUBLISH_HARBOR}" == "1" ]]; then
    publish_runtime_set "${HARBOR_REGISTRY}/${HARBOR_PROJECT}" "namespace-component"
  fi
}

VERSION=""
TARGET_REGISTRY=""
BUILD_TARGET=""
BUILD_PLATFORMS="both"
PHASE="all"
NATIVE_ARCH=""
INSTALL_BINFMT="0"
GITHUB_USERNAME=""
GITHUB_TOKEN_VALUE=""
HARBOR_USERNAME_VALUE=""
HARBOR_PASSWORD_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --target_registry)
      TARGET_REGISTRY="$2"
      shift 2
      ;;
    --build_target)
      BUILD_TARGET="$2"
      shift 2
      ;;
    --build_platforms)
      BUILD_PLATFORMS="$2"
      shift 2
      ;;
    --phase)
      PHASE="$2"
      shift 2
      ;;
    --native_arch)
      NATIVE_ARCH="$2"
      shift 2
      ;;
    --install_binfmt)
      INSTALL_BINFMT="1"
      shift
      ;;
    --github_username)
      GITHUB_USERNAME="$2"
      shift 2
      ;;
    --github_token)
      GITHUB_TOKEN_VALUE="$2"
      shift 2
      ;;
    --harbor_username)
      HARBOR_USERNAME_VALUE="$2"
      shift 2
      ;;
    --harbor_password)
      HARBOR_PASSWORD_VALUE="$2"
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
[[ -n "${TARGET_REGISTRY}" ]] || die "--target_registry is required"
[[ -n "${BUILD_TARGET}" ]] || die "--build_target is required"

case "${PHASE}" in
  all|build-direct-arch|publish-direct-manifest|build-harbor-runtime-set)
    ;;
  *)
    die "Unsupported --phase '${PHASE}'"
    ;;
esac

case "${NATIVE_ARCH}" in
  ""|amd64|arm64)
    ;;
  *)
    die "Unsupported --native_arch '${NATIVE_ARCH}'"
    ;;
esac

GHCR_NAMESPACE="${GHCR_NAMESPACE:-${GHCR_NAMESPACE_DEFAULT}}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-${HARBOR_REGISTRY_DEFAULT}}"
HARBOR_PROJECT="${HARBOR_PROJECT:-${HARBOR_PROJECT_DEFAULT}}"

resolve_build_target
resolve_registry_target
resolve_platforms

log "Version: ${VERSION}"
log "Target registry: ${TARGET_REGISTRY}"
log "Build target: ${BUILD_TARGET}"
log "Build strategy: ${BUILD_STRATEGY}"
log "Platforms: ${PLATFORMS_CSV}"
log "Phase: ${PHASE}"

registry_login
install_binfmt_if_requested

case "${BUILD_STRATEGY}:${PHASE}" in
  direct:all)
    if [[ "${BUILD_AMD64}" == "1" ]]; then
      build_direct_arch amd64
    fi
    if [[ "${BUILD_ARM64}" == "1" ]]; then
      build_direct_arch arm64
    fi
    publish_direct_manifests
    ;;
  direct:build-direct-arch)
    [[ -n "${NATIVE_ARCH}" ]] || die "--native_arch is required for --phase build-direct-arch"
    case "${NATIVE_ARCH}" in
      amd64)
        [[ "${BUILD_AMD64}" == "1" ]] || die "Requested native arch amd64 is not enabled by --build_platforms"
        ;;
      arm64)
        [[ "${BUILD_ARM64}" == "1" ]] || die "Requested native arch arm64 is not enabled by --build_platforms"
        ;;
    esac
    build_direct_arch "${NATIVE_ARCH}"
    ;;
  direct:publish-direct-manifest)
    publish_direct_manifests
    ;;
  harbor-runtime-set:all|harbor-runtime-set:build-harbor-runtime-set)
    build_harbor_runtime_set
    ;;
  harbor-runtime-set:*)
    die "Phase ${PHASE} is not supported for build strategy ${BUILD_STRATEGY}"
    ;;
  *)
    die "Unhandled phase ${PHASE} for build strategy ${BUILD_STRATEGY}"
    ;;
esac
