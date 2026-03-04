#!/usr/bin/env bash
set -euo pipefail

# Constants: edit these only if host/service naming changes.
DOCKER_HOST_URI="ssh://nodadyoushutup@192.168.1.26"
SERVICE_NAME="docker-volume-backup"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERR] Missing command: $1" >&2
    exit 1
  }
}

find_container_id() {
  local docker_host="$1"
  local service_name="$2"

  docker --host "${docker_host}" ps \
    --filter "label=com.docker.swarm.service.name=${service_name}" \
    --format '{{.ID}}' \
    | head -n1
}

need_cmd docker

if [[ $# -ne 0 ]]; then
  echo "[ERR] This script takes no arguments. Edit constants at top of file instead." >&2
  exit 2
fi

container_id="$(find_container_id "${DOCKER_HOST_URI}" "${SERVICE_NAME}")"

if [[ -z "${container_id}" ]]; then
  echo "[ERR] No running container found for service '${SERVICE_NAME}' on '${DOCKER_HOST_URI}'." >&2
  exit 1
fi

echo "[INFO] Docker host: ${DOCKER_HOST_URI}"
echo "[INFO] Service: ${SERVICE_NAME}"
echo "[INFO] Container: ${container_id}"
echo "[INFO] Triggering manual backup..."

docker --host "${DOCKER_HOST_URI}" exec "${container_id}" backup

echo "[OK] Manual backup command completed."
