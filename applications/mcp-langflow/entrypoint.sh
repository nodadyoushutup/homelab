#!/bin/sh
set -eu

if [ -z "${LANGFLOW_BASE_URL:-}" ]; then
  echo "[ERR] LANGFLOW_BASE_URL is required" >&2
  exit 1
fi

if [ -z "${LANGFLOW_API_KEY:-}" ]; then
  echo "[ERR] LANGFLOW_API_KEY is required" >&2
  exit 1
fi

exec /app/.venv/bin/mcp-proxy \
  --host "${MCP_LANGFLOW_HOST:-${MCP_BRIDGE_HOST:-0.0.0.0}}" \
  --port "${MCP_LANGFLOW_LISTEN_PORT:-${MCP_BRIDGE_LISTEN_PORT:-8102}}" \
  --stateless \
  --pass-environment \
  -- \
  /usr/local/bin/langflow-mcp-server
