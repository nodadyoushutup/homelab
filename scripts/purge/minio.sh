#!/usr/bin/env bash
set -euo pipefail

# Defaults
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yaml}"
PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
PROJECT_NAME="${PROJECT_NAME:-$(basename "$PROJECT_DIR")}"
RMI_MODE="all"       # options: none, local, all
ASSUME_YES="yes"

# Parse args
for arg in "$@"; do
  case "$arg" in
    --rmi)
      RMI_MODE="all"
      ;;
    --rmi-local)
      RMI_MODE="local"
      ;;
    --keep-images)
      RMI_MODE="none"
      ;;
    --yes|-y)
      ASSUME_YES="yes"
      ;;
    --prompt)
      ASSUME_YES="no"
      ;;
    --project-name=*)
      PROJECT_NAME="${arg#*=}"
      ;;
    --compose-file=*)
      COMPOSE_FILE="${arg#*=}"
      ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--prompt] [--keep-images|--rmi-local|--rmi] [--project-name=NAME] [--compose-file=FILE]

Removes all Docker assets created by the MinIO compose stack:
- Containers, network, and orphans
- Named volumes: minio-data, minio-config
- Images (default); use --keep-images to skip

Env overrides:
  PROJECT_DIR, PROJECT_NAME, COMPOSE_FILE

Examples:
  $(basename "$0")
  $(basename "$0") --prompt --keep-images
EOF
      exit 0
      ;;
  esac
done

# Choose docker compose command
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  DC="docker compose"
elif command -v docker-compose &>/dev/null; then
  DC="docker-compose"
else
  echo "ERROR: docker compose not found." >&2
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: Compose file not found at: $COMPOSE_FILE" >&2
  exit 1
fi

# Derived resource names
VOL_DATA="${PROJECT_NAME}_minio-data"
VOL_CONFIG="${PROJECT_NAME}_minio-config"
NET_DEFAULT="${PROJECT_NAME}_default"

echo "Compose file : $COMPOSE_FILE"
echo "Project name : $PROJECT_NAME"
echo "Volumes      : $VOL_DATA, $VOL_CONFIG"
echo "Network      : $NET_DEFAULT"
echo "Image mode   : ${RMI_MODE}"

if [[ "$ASSUME_YES" != "yes" ]]; then
  read -r -p "This will STOP and REMOVE the stack, volumes, network, and images (${RMI_MODE}). Continue? [y/N] " ans
  case "${ans:-N}" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

echo ">>> Bringing stack down (containers, network, orphans)…"
down_args=(-f "$COMPOSE_FILE" -p "$PROJECT_NAME" down -v --remove-orphans)
case "$RMI_MODE" in
  all) down_args+=(--rmi all) ;;
  local) down_args+=(--rmi local) ;;
esac
$DC "${down_args[@]}" || true

echo ">>> Extra cleanup (named volumes & default network), just in case…"
# Remove volumes if they still exist (defensive)
if docker volume inspect "$VOL_DATA" &>/dev/null; then
  docker volume rm "$VOL_DATA" || true
fi
if docker volume inspect "$VOL_CONFIG" &>/dev/null; then
  docker volume rm "$VOL_CONFIG" || true
fi

# Remove default network if it still exists
if docker network inspect "$NET_DEFAULT" &>/dev/null; then
  docker network rm "$NET_DEFAULT" || true
fi

# Optional image cleanup beyond --rmi local
if [[ "$RMI_MODE" != "none" ]]; then
  echo ">>> Attempting to remove MinIO images (if unused)…"
  while read -r img; do
    [[ -z "$img" ]] && continue
    docker rmi "$img" || true
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | awk '/^minio\/(minio|mc):/')
fi

echo ">>> Done. Stack assets removed for project: $PROJECT_NAME"
