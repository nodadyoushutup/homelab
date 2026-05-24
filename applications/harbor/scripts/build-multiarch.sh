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
RETAG_FROM_NAMESPACE=""
SELECTED_COMPONENTS=()
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
  --component <name>       Build/push one runtime image (repeatable; default: full runtime set)
  --components <csv>       Same as repeated --component (comma-separated image names)
  --retag-from-namespace <src>  Skip build; retag existing <src>/<image>:<tag> into --namespace and push
  --install-binfmt         Install qemu/binfmt via tonistiigi/binfmt before build
  -h, --help               Show this help

Environment:
  HARBOR_BUILD_TMP_PARENT  Existing directory for Harbor clones (default: GITHUB_WORKSPACE,
                           else RUNNER_TEMP, TMPDIR, /tmp). Use when Docker bind mounts must
                           resolve on the engine host (CI / nested Docker).
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
    --component)
      SELECTED_COMPONENTS+=("$2")
      shift 2
      ;;
    --components)
      IFS=',' read -r -a _components_csv <<<"$2"
      for _component in "${_components_csv[@]}"; do
        _component="${_component// /}"
        [[ -n "${_component}" ]] || continue
        SELECTED_COMPONENTS+=("${_component}")
      done
      shift 2
      ;;
    --retag-from-namespace)
      RETAG_FROM_NAMESPACE="$2"
      shift 2
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

# Docker bind-mounts source paths from the engine host. Clones under job-local /tmp do not
# exist on that host, so `docker run -v "$repo:$repo"` sees an empty directory (no Makefile).
# GitHub Actions bind-mounts GITHUB_WORKSPACE (and usually RUNNER_TEMP) from the host.
# Runner-in-Docker with only docker.sock: workspace is not on the engine host; prefer host
# make+go (HAS_HOST_MAKE) or HARBOR_BUILD_TMP_PARENT on a path shared with the daemon.
harbor_temp_parent_dir() {
  if [[ -n "${HARBOR_BUILD_TMP_PARENT:-}" ]]; then
    if ! mkdir -p "${HARBOR_BUILD_TMP_PARENT}"; then
      echo "[ERR] HARBOR_BUILD_TMP_PARENT=${HARBOR_BUILD_TMP_PARENT} is set but mkdir -p failed." >&2
      exit 1
    fi
    if [[ ! -d "${HARBOR_BUILD_TMP_PARENT}" ]]; then
      echo "[ERR] HARBOR_BUILD_TMP_PARENT=${HARBOR_BUILD_TMP_PARENT} is not a directory." >&2
      exit 1
    fi
    printf '%s\n' "${HARBOR_BUILD_TMP_PARENT}"
    return 0
  fi
  if [[ -n "${GITHUB_WORKSPACE:-}" && -d "${GITHUB_WORKSPACE}" ]]; then
    printf '%s\n' "${GITHUB_WORKSPACE}"
    return 0
  fi
  if [[ -n "${RUNNER_TEMP:-}" && -d "${RUNNER_TEMP}" ]]; then
    printf '%s\n' "${RUNNER_TEMP}"
    return 0
  fi
  if [[ -n "${TMPDIR:-}" && -d "${TMPDIR}" ]]; then
    printf '%s\n' "${TMPDIR}"
    return 0
  fi
  printf '%s\n' "/tmp"
}

# Registry publish names (all use the harbor- prefix). Upstream `make build` may tag
# photon images without that prefix; push_runtime_image retags before push.
runtime_images=(
  harbor-core
  harbor-portal
  harbor-jobservice
  harbor-registryctl
  harbor-db
  harbor-registry-photon
  harbor-redis-photon
  harbor-nginx-photon
  harbor-log
  harbor-trivy-adapter-photon
  harbor-exporter
  harbor-prepare
)

upstream_image_name() {
  case "$1" in
    harbor-registry-photon) printf '%s' "registry-photon" ;;
    harbor-redis-photon) printf '%s' "redis-photon" ;;
    harbor-nginx-photon) printf '%s' "nginx-photon" ;;
    harbor-trivy-adapter-photon) printf '%s' "trivy-adapter-photon" ;;
    harbor-prepare) printf '%s' "prepare" ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

validate_runtime_component() {
  local image="$1"
  local allowed

  for allowed in "${runtime_images[@]}"; do
    if [[ "${image}" == "${allowed}" ]]; then
      return 0
    fi
  done

  echo "[ERR] Unsupported runtime component: ${image}" >&2
  echo "[HINT] Allowed: ${runtime_images[*]}" >&2
  return 1
}

resolve_runtime_images() {
  if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
    printf '%s\n' "${runtime_images[@]}"
    return 0
  fi

  local image
  local -a unique_components=()
  for image in "${SELECTED_COMPONENTS[@]}"; do
    validate_runtime_component "${image}"
    local seen=false
    local existing
    for existing in "${unique_components[@]}"; do
      if [[ "${existing}" == "${image}" ]]; then
        seen=true
        break
      fi
    done
    if [[ "${seen}" == "false" ]]; then
      unique_components+=("${image}")
    fi
  done

  printf '%s\n' "${unique_components[@]}"
}

component_compile_target() {
  case "$1" in
    harbor-core) printf '%s' "compile_core" ;;
    harbor-jobservice) printf '%s' "compile_jobservice" ;;
    harbor-registryctl) printf '%s' "compile_registryctl" ;;
    *) return 1 ;;
  esac
}

harbor_makefile_var() {
  local makefile="$1"
  local key="$2"

  awk -v k="$key" -F= '$1 == k { sub(/^[^=]*=/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); print; exit }' "${makefile}"
}

expand_makefile_template() {
  local template="$1"
  local name="$2"
  local value="$3"

  template="${template//\$\{${name}\}/${value}}"
  template="${template//\$\(${name}\)/${value}}"
  printf '%s' "${template}"
}

# Photon targets expect the same -e exports as top-level `make build` provides.
append_harbor_photon_env() {
  local repo_dir="$1"
  local -n _env="${2}"
  local makefile="${repo_dir}/Makefile"

  if [[ ! -f "${makefile}" ]]; then
    echo "[ERR] Missing Harbor Makefile: ${makefile}" >&2
    exit 1
  fi

  local -a keys=(
    GOBUILDIMAGE
    NODEBUILDIMAGE
    REGISTRYVERSION
    REGISTRY_SRC_TAG
    DISTRIBUTION_SRC
    TRIVYADAPTERVERSION
    DOCKERNETWORK
    NPM_REGISTRY
    REGISTRYUSER
    REGISTRYPASSWORD
  )
  local key value registry_version trivy_adapter_version registry_url trivy_adapter_url

  for key in "${keys[@]}"; do
    value="$(harbor_makefile_var "${makefile}" "${key}")"
    if [[ -n "${value}" ]]; then
      _env+=("${key}=${value}")
    fi
  done

  registry_version="$(harbor_makefile_var "${makefile}" REGISTRYVERSION)"
  trivy_adapter_version="$(harbor_makefile_var "${makefile}" TRIVYADAPTERVERSION)"

  registry_url="$(harbor_makefile_var "${makefile}" REGISTRYURL)"
  if [[ -n "${registry_url}" && -n "${registry_version}" ]]; then
    registry_url="$(expand_makefile_template "${registry_url}" REGISTRYVERSION "${registry_version}")"
    _env+=("REGISTRYURL=${registry_url}")
  fi

  trivy_adapter_url="$(harbor_makefile_var "${makefile}" TRIVY_ADAPTER_DOWNLOAD_URL)"
  if [[ -n "${trivy_adapter_url}" && -n "${trivy_adapter_version}" ]]; then
    trivy_adapter_url="$(expand_makefile_template "${trivy_adapter_url}" TRIVYADAPTERVERSION "${trivy_adapter_version}")"
    _env+=("TRIVY_ADAPTER_DOWNLOAD_URL=${trivy_adapter_url}")
  fi

  _env+=(
    "BUILDREG=false"
    "BUILDTRIVYADP=false"
    "PUSHBASEIMAGE=false"
  )
}

component_photon_target() {
  case "$1" in
    harbor-db) printf '%s' "_build_db" ;;
    harbor-portal) printf '%s' "_build_portal" ;;
    harbor-core) printf '%s' "_build_core" ;;
    harbor-jobservice) printf '%s' "_build_jobservice" ;;
    harbor-log) printf '%s' "_build_log" ;;
    harbor-trivy-adapter-photon) printf '%s' "_build_trivy_adapter" ;;
    harbor-nginx-photon) printf '%s' "_build_nginx" ;;
    harbor-registry-photon) printf '%s' "_build_registry" ;;
    harbor-registryctl) printf '%s' "_build_registryctl" ;;
    harbor-redis-photon) printf '%s' "_build_redis" ;;
    harbor-prepare) printf '%s' "_build_prepare" ;;
    harbor-exporter) printf '%s' "_compile_and_build_exporter" ;;
    *)
      echo "[ERR] No photon build target for component: $1" >&2
      return 1
      ;;
  esac
}

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

  # Per-arch tags are often pushed via Buildx as manifest lists (indexes). The classic
  # `docker manifest create` path rejects list inputs ("X is a manifest list"). Buildx
  # `imagetools create` merges registry-side and accepts list or single-platform sources.
  if ! docker buildx imagetools create --help >/dev/null 2>&1; then
    echo "[ERR] docker buildx imagetools create is required to publish Harbor multi-arch manifests." >&2
    echo "[HINT] Install a current Docker Buildx plugin, or add docker/setup-buildx-action before this step." >&2
    exit 1
  fi

  local -a images_to_publish=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && images_to_publish+=("${image}")
  done < <(resolve_runtime_images)

  for image in "${images_to_publish[@]}"; do
    local manifest_ref
    manifest_ref="$(publish_image_ref "${image}" "${HARBOR_IMAGE_TAG}")"

    local -a refs=()
    for platform in "${PLATFORMS[@]}"; do
      local os arch variant
      IFS='/' read -r os arch variant <<<"${platform}"
      refs+=("$(publish_image_ref "${image}" "${HARBOR_IMAGE_TAG}-${arch}")")
    done

    echo "[INFO] buildx imagetools create ${manifest_ref} ← ${refs[*]}"
    docker buildx imagetools create -t "${manifest_ref}" "${refs[@]}"
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

run_photon_make_target() {
  local repo_dir="$1"
  local target="$2"
  shift 2
  local -a env_pairs=("$@")
  local photon_makefile="${repo_dir}/make/photon/Makefile"

  if [[ ! -f "${photon_makefile}" ]]; then
    echo "[ERR] Missing photon Makefile: ${photon_makefile}" >&2
    exit 1
  fi

  if [[ "${HAS_HOST_MAKE}" == "1" ]]; then
    (
      cd "${repo_dir}"
      env "TERM=${TERM:-xterm}" "${env_pairs[@]}" make -e -f make/photon/Makefile "${target}"
    )
    return
  fi

  local -a docker_args env_args
  docker_args=(
    --rm
    --entrypoint sh
    -v /var/run/docker.sock:/var/run/docker.sock
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

  env_args+=(-e "DOCKER_HOST=unix:///var/run/docker.sock")

  if [[ "${MAKE_HELPER_ANNOUNCED}" == "0" ]]; then
    echo "[WARN] Host make+go not both available; using ${MAKE_HELPER_IMAGE} helper container." >&2
    MAKE_HELPER_ANNOUNCED="1"
  fi

  docker run \
    "${docker_args[@]}" \
    "${env_args[@]}" \
    "${MAKE_HELPER_IMAGE}" \
    -c '
      set -eu
      apk add --no-cache bash coreutils curl git make >/dev/null
      export TERM="${TERM:-xterm}"
      git config --global --add safe.directory "$PWD"
      test -f make/photon/Makefile || {
        echo "[ERR] No make/photon/Makefile in $(pwd)." >&2
        exit 1
      }
      if [ -z "${1:-}" ]; then
        echo "[ERR] photon make goal missing (helper argv bug)." >&2
        exit 1
      fi
      exec make -e -f make/photon/Makefile "$1"
    ' _ "${target}"
}

find_local_image_ref() {
  local publish_name="$1"
  local arch_tag="$2"
  local upstream_name="$3"
  shift 3
  local -a prefixes=("$@")
  local prefix candidate

  local -a names=("${upstream_name}")
  if [[ "${publish_name}" != "${upstream_name}" ]]; then
    names+=("${publish_name}")
  fi

  for prefix in "${prefixes[@]}"; do
    [[ -n "${prefix}" ]] || continue
    for candidate in "${names[@]}"; do
      candidate="${prefix}/${candidate}:${arch_tag}"
      if docker image inspect "${candidate}" >/dev/null 2>&1; then
        printf '%s' "${candidate}"
        return 0
      fi
    done
  done

  return 1
}

push_runtime_image() {
  local publish_name="$1"
  local arch_tag="$2"

  local upstream_name source_ref target_ref
  upstream_name="$(upstream_image_name "${publish_name}")"
  target_ref="$(publish_image_ref "${publish_name}" "${arch_tag}")"

  if ! source_ref="$(find_local_image_ref "${publish_name}" "${arch_tag}" "${upstream_name}" \
    "${IMAGE_NAMESPACE}" "goharbor")"; then
    echo "[ERR] Built image not found for ${publish_name}:${arch_tag}." >&2
    echo "[HINT] Expected tags under ${IMAGE_NAMESPACE}/ or goharbor/ (upstream: ${upstream_name})." >&2
    exit 1
  fi

  if [[ "${source_ref}" != "${target_ref}" ]]; then
    echo "[INFO] Retagging ${source_ref} -> ${target_ref}"
    docker tag "${source_ref}" "${target_ref}"
  fi

  echo "[PUSH] ${target_ref}"
  docker push "${target_ref}"
}

retag_and_push_for_platform() {
  local platform="$1"
  local os arch variant
  IFS='/' read -r os arch variant <<<"${platform}"

  if [[ "${os}" != "linux" || -z "${arch}" ]]; then
    echo "[ERR] Unsupported platform format: ${platform}" >&2
    exit 1
  fi

  if [[ -z "${RETAG_FROM_NAMESPACE}" ]]; then
    echo "[ERR] --retag-from-namespace is required for retag-only publish." >&2
    exit 1
  fi

  local arch_tag="${HARBOR_IMAGE_TAG}-${arch}"
  local -a images_to_push=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && images_to_push+=("${image}")
  done < <(resolve_runtime_images)

  echo "[INFO] Retag ${RETAG_FROM_NAMESPACE}/*:${arch_tag} -> ${IMAGE_NAMESPACE}/*:${arch_tag}"

  local image
  for image in "${images_to_push[@]}"; do
    local upstream_name source_ref target_ref
    upstream_name="$(upstream_image_name "${image}")"
    target_ref="$(publish_image_ref "${image}" "${arch_tag}")"

    if ! source_ref="$(find_local_image_ref "${image}" "${arch_tag}" "${upstream_name}" \
      "${RETAG_FROM_NAMESPACE}")"; then
      echo "[ERR] Source image missing on ${RETAG_FROM_NAMESPACE} for ${image}:${arch_tag}." >&2
      exit 1
    fi

    if [[ "${source_ref}" != "${target_ref}" ]]; then
      echo "[INFO] Retagging ${source_ref} -> ${target_ref}"
      docker tag "${source_ref}" "${target_ref}"
    fi

    echo "[PUSH] ${target_ref}"
    docker push "${target_ref}"
  done
}

build_runtime_component() {
  local repo_dir="$1"
  local image="$2"
  shift 2
  local -a build_env=("$@")
  local compile_target photon_target

  if compile_target="$(component_compile_target "${image}" 2>/dev/null)"; then
    echo "[BUILD] make ${compile_target} (${image})"
    run_make_target "${repo_dir}" "${compile_target}" "${build_env[@]}"
  fi

  photon_target="$(component_photon_target "${image}")"
  echo "[BUILD] make -f make/photon/Makefile ${photon_target} (${image})"
  run_photon_make_target "${repo_dir}" "${photon_target}" "${build_env[@]}"
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
  local workdir repo_dir temp_parent
  temp_parent="$(harbor_temp_parent_dir)"
  workdir="$(mktemp -d "${temp_parent}/harbor-build.XXXXXX")"
  repo_dir="${workdir}/harbor"

  trap 'rm -rf "${workdir}"' RETURN

  echo "[INFO] Harbor build dir: ${workdir} (temp parent: ${temp_parent})"
  echo "[INFO] Image namespace for this build: ${IMAGE_NAMESPACE}"
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

  local -a images_to_build=()
  while IFS= read -r image; do
    [[ -n "${image}" ]] && images_to_build+=("${image}")
  done < <(resolve_runtime_images)

  if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
    echo "[BUILD] make compile (${platform})"
    run_make_target "${repo_dir}" compile "${build_env[@]}"

    echo "[BUILD] make build (${platform})"
    run_make_target "${repo_dir}" build "${build_env[@]}"
  else
    append_harbor_photon_env "${repo_dir}" build_env
    for image in "${images_to_build[@]}"; do
      build_runtime_component "${repo_dir}" "${image}" "${build_env[@]}"
    done
  fi

  if [[ "${PUSH_IMAGES}" == "1" ]]; then
    for image in "${images_to_build[@]}"; do
      push_runtime_image "${image}" "${arch_tag}"
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

if [[ -n "${RETAG_FROM_NAMESPACE}" ]]; then
  if [[ "${PUSH_IMAGES}" != "1" ]]; then
    echo "[ERR] --retag-from-namespace requires --push." >&2
    exit 1
  fi
  if [[ ${#SELECTED_COMPONENTS[@]} -eq 0 ]]; then
    echo "[ERR] --retag-from-namespace requires --component (or --components)." >&2
    exit 1
  fi
  for platform in "${PLATFORMS[@]}"; do
    retag_and_push_for_platform "${platform}"
  done
elif [[ "${MANIFEST_ONLY}" != "1" ]]; then
  for platform in "${PLATFORMS[@]}"; do
    build_for_platform "${platform}"
  done
fi

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
