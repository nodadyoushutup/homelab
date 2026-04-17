#!/bin/sh
set -eu

WORKSPACE_ROOT="${MCP_FILESYSTEM_WORKSPACE_ROOT:-/mnt/eapp/code}"
LISTEN_HOST="${MCP_FILESYSTEM_HOST:-${MCP_BRIDGE_HOST:-0.0.0.0}}"
LISTEN_PORT="${MCP_FILESYSTEM_LISTEN_PORT:-${MCP_BRIDGE_LISTEN_PORT:-8098}}"

if [ ! -d "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_FILESYSTEM_WORKSPACE_ROOT is missing: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

if [ ! -w "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_FILESYSTEM_WORKSPACE_ROOT is not writable: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

export MCP_FILESYSTEM_WORKSPACE_ROOT="${WORKSPACE_ROOT}"

exec /app/.venv/bin/mcp-proxy \
  --host "${LISTEN_HOST}" \
  --port "${LISTEN_PORT}" \
  --stateless \
  -- \
  mcp-server-filesystem "${WORKSPACE_ROOT}"
