#!/usr/bin/env bash
# Build (optional), log in to Harbor, push mcp-code image, then apply Swarm Terraform locally.
# Requires HARBOR_USERNAME and HARBOR_PASSWORD (e.g. in .config/.env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${MCP_CODE_VERSION:-2026.05.11.1}"
TAG="harbor.nodadyoushutup.com/homelab/mcp-code:${VERSION}-arm64"
SECRETS="${HOMELAB_CONFIG_ENV:-${HOMELAB_SECRETS_ENV:-${ROOT}/.config/.env}}"
if [[ ! -f "${SECRETS}" && -f "${ROOT}/.secrets/.env" ]]; then
  SECRETS="${ROOT}/.secrets/.env"
fi

if [[ -f "${SECRETS}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${SECRETS}"
  set +a
fi

: "${HARBOR_USERNAME:?Set HARBOR_USERNAME (e.g. in .config/.env)}"
: "${HARBOR_PASSWORD:?Set HARBOR_PASSWORD (e.g. in .config/.env)}"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  docker buildx build --platform linux/arm64 \
    -f "${ROOT}/applications/mcp-code/Dockerfile" \
    -t "${TAG}" \
    --load \
    "${ROOT}"
fi

printf '%s' "${HARBOR_PASSWORD}" | docker login harbor.nodadyoushutup.com \
  --username "${HARBOR_USERNAME}" --password-stdin

docker push "${TAG}"

echo ""
echo "Pushed ${TAG}"
echo "Default Terraform pin updated in terraform/swarm/mcp-code/app/variables.tf to this tag."
echo "Apply Swarm stack (from a host with Docker Swarm + <homelab>/.config/terraform/providers/docker_arm64.tfvars):"
echo "  ${ROOT}/pipelines/terraform/swarm/mcp-code/app.sh"
