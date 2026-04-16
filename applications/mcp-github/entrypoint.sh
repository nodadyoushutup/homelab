#!/bin/sh
set -eu

if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
  echo "[ERR] GITHUB_PERSONAL_ACCESS_TOKEN is required" >&2
  exit 1
fi

exec /app/.venv/bin/mcp-proxy \
  --host "${MCP_GITHUB_HOST:-${MCP_BRIDGE_HOST:-0.0.0.0}}" \
  --port "${MCP_GITHUB_LISTEN_PORT:-${MCP_BRIDGE_LISTEN_PORT:-8082}}" \
  --stateless \
  --pass-environment \
  -- \
  /usr/local/bin/github-mcp-server \
  --toolsets "${GITHUB_MCP_TOOLSETS:-all}" \
  stdio
