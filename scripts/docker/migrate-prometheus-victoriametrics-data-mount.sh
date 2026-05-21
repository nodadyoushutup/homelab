#!/usr/bin/env bash
# One-time: copy VictoriaMetrics TSDB from the old in-container mount path to the new one
# on the Swarm volume, then apply terraform/swarm/prometheus/database (single mount at new path).
#
# The Docker volume name is already prometheus-victoriametrics-data; only the container
# mount target changes. Data lives at the volume root, so this copy is usually a no-op but
# is safe when both paths are bound to the same volume.
set -euo pipefail

VOLUME_NAME="${VOLUME_NAME:-prometheus-victoriametrics-data}"
SERVICE_NAME="${SERVICE_NAME:-prometheus-victoriametrics}"
OLD_MOUNT="/victoria-metrics-data"
NEW_MOUNT="/prometheus-victoriametrics-data"
MIGRATE_IMAGE="${MIGRATE_IMAGE:-alpine:3.21}"

if ! docker info >/dev/null 2>&1; then
  echo "error: docker daemon not reachable" >&2
  exit 1
fi

if ! docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
  echo "error: volume ${VOLUME_NAME} not found" >&2
  exit 1
fi

echo "Scaling ${SERVICE_NAME} to 0 (skip if service missing)..."
if docker service inspect "${SERVICE_NAME}" >/dev/null 2>&1; then
  docker service scale "${SERVICE_NAME}=0"
  echo "Waiting for tasks to stop..."
  for _ in $(seq 1 60); do
    running="$(docker service ps "${SERVICE_NAME}" --filter desired-state=running --format '{{.CurrentState}}' 2>/dev/null | grep -c Running || true)"
    if [[ "${running}" -eq 0 ]]; then
      break
    fi
    sleep 2
  done
else
  echo "  service ${SERVICE_NAME} not present; continuing"
fi

echo "Copying ${OLD_MOUNT} -> ${NEW_MOUNT} on volume ${VOLUME_NAME}..."
docker run --rm \
  -v "${VOLUME_NAME}:${OLD_MOUNT}" \
  -v "${VOLUME_NAME}:${NEW_MOUNT}" \
  "${MIGRATE_IMAGE}" \
  sh -ceu "
    if [ ! -d '${OLD_MOUNT}' ]; then
      echo 'error: ${OLD_MOUNT} missing in migrate container' >&2
      exit 1
    fi
    mkdir -p '${NEW_MOUNT}'
    if [ -n \"\$(ls -A '${OLD_MOUNT}' 2>/dev/null || true)\" ]; then
      cp -a '${OLD_MOUNT}/.' '${NEW_MOUNT}/'
      echo 'copy finished; top of ${NEW_MOUNT}:'
      ls -la '${NEW_MOUNT}' | head -20
    else
      echo 'volume root empty — nothing to copy (fresh deploy is fine)'
    fi
  "

echo
echo "Next: apply prometheus database Terraform (new -storageDataPath=${NEW_MOUNT}), then scale up if you scaled down:"
echo "  ${SERVICE_NAME}=1  # or re-apply terraform (replicas=1)"
