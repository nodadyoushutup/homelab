#!/usr/bin/env bash
# Build (optional), log in to Harbor, push mcp-code image, then apply Swarm Terraform locally.
# Requires HARBOR_USERNAME and HARBOR_PASSWORD (e.g. in .config/docker/agents.env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERSION="${MCP_CODE_VERSION:-2026.05.11.1}"
TAG="harbor.nodadyoushutup.com/homelab/mcp-code:${VERSION}-arm64"
export ROOT_DIR="${ROOT}"
# shellcheck source=../terraform/load_docker_env.sh
source "${ROOT}/scripts/terraform/load_docker_env.sh"

: "${HARBOR_USERNAME:?Set HARBOR_USERNAME (e.g. in .config/docker/agents.env)}"
: "${HARBOR_PASSWORD:?Set HARBOR_PASSWORD (e.g. in .config/docker/agents.env)}"

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
