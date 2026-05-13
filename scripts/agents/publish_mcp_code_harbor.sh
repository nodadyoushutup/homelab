#!/usr/bin/env bash
# Build (optional), log in to Harbor, push mcp-code image, then apply Swarm Terraform locally.
# Requires HARBOR_USERNAME and HARBOR_PASSWORD (e.g. in .secrets/.env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${MCP_CODE_VERSION:-2026.05.11.1}"
TAG="harbor.nodadyoushutup.com/homelab/mcp-code:${VERSION}-arm64"
SECRETS="${HOMELAB_SECRETS_ENV:-${ROOT}/.secrets/.env}"

if [[ -f "${SECRETS}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${SECRETS}"
  set +a
fi

: "${HARBOR_USERNAME:?Set HARBOR_USERNAME (e.g. in .secrets/.env)}"
: "${HARBOR_PASSWORD:?Set HARBOR_PASSWORD (e.g. in .secrets/.env)}"

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
echo "Apply Swarm stack (from a host with Docker Swarm + /mnt/eapp/config/providers/docker.tfvars):"
echo "  ${ROOT}/pipelines/terraform/swarm/mcp-code/app.sh"
