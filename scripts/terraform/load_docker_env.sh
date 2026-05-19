#!/usr/bin/env bash
# Source split dotenv files under <repo>/.config/docker/ in a fixed order (later files win).
# Sourced by load_root_env.sh, agent_server.sh, and other host tooling.

if [[ "${HOMELAB_DOCKER_ENV_LOADED:-0}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

_homelab_docker_env_root="${HOMELAB_DOCKER_ENV_ROOT:-${ROOT_DIR:-}}"
if [[ -z "${_homelab_docker_env_root}" ]]; then
  _homelab_docker_env_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  _homelab_docker_env_root="$(cd "${_homelab_docker_env_script_dir}/../.." && pwd)"
fi

_homelab_docker_env_dir="${HOMELAB_CONFIG_ENV_DIR:-${_homelab_docker_env_root}/.config/docker}"
_homelab_monolithic_env="${_homelab_docker_env_dir}/.env"

if [[ -f "${_homelab_monolithic_env}" ]]; then
  echo "[homelab] Remove ${_homelab_monolithic_env} and split values into .config/docker/*.env (see .config/docker/README.md)." >&2
  return 1 2>/dev/null || exit 1
fi

_homelab_docker_env_files=(
  site.env
  shared.env
  postgres.env
  rag.env
  mcp.env
  langgraph.env
  agents.env
  argocd.env
  minio.env
  qbittorrent.env
)

_homelab_docker_env_found=0
for _homelab_docker_env_name in "${_homelab_docker_env_files[@]}"; do
  _homelab_docker_env_path="${_homelab_docker_env_dir}/${_homelab_docker_env_name}"
  if [[ -f "${_homelab_docker_env_path}" ]]; then
    _homelab_docker_env_found=1
    break
  fi
done

if [[ "${_homelab_docker_env_found}" != "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

_homelab_docker_restore_allexport=0
_homelab_docker_restore_nounset=0
if [[ "$-" == *a* ]]; then
  _homelab_docker_restore_allexport=1
fi
if [[ "$-" == *u* ]]; then
  _homelab_docker_restore_nounset=1
  set +u
fi

set -a
for _homelab_docker_env_name in "${_homelab_docker_env_files[@]}"; do
  _homelab_docker_env_path="${_homelab_docker_env_dir}/${_homelab_docker_env_name}"
  if [[ -f "${_homelab_docker_env_path}" ]]; then
    # shellcheck disable=SC1090
    source "${_homelab_docker_env_path}"
  fi
done
if [[ "${_homelab_docker_restore_allexport}" != "1" ]]; then
  set +a
fi
if [[ "${_homelab_docker_restore_nounset}" == "1" ]]; then
  set -u
fi

export HOMELAB_DOCKER_ENV_LOADED=1
