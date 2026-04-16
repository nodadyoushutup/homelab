#!/bin/sh
set -eu

REPOSITORY_ROOT="${MCP_GIT_REPOSITORY_ROOT:-/mnt/epool/code/homelab}"
LISTEN_HOST="${MCP_GIT_HOST:-${MCP_BRIDGE_HOST:-0.0.0.0}}"
LISTEN_PORT="${MCP_GIT_LISTEN_PORT:-${MCP_BRIDGE_LISTEN_PORT:-8099}}"

if [ ! -d "${REPOSITORY_ROOT}" ]; then
  echo "[ERR] MCP_GIT_REPOSITORY_ROOT is missing: ${REPOSITORY_ROOT}" >&2
  exit 1
fi

if [ ! -d "${REPOSITORY_ROOT}/.git" ]; then
  echo "[ERR] MCP_GIT_REPOSITORY_ROOT is not a git repository: ${REPOSITORY_ROOT}" >&2
  exit 1
fi

if [ ! -w "${REPOSITORY_ROOT}" ]; then
  echo "[ERR] MCP_GIT_REPOSITORY_ROOT is not writable: ${REPOSITORY_ROOT}" >&2
  exit 1
fi

export MCP_GIT_REPOSITORY_ROOT="${REPOSITORY_ROOT}"

exec /app/.venv/bin/mcp-proxy \
  --host "${LISTEN_HOST}" \
  --port "${LISTEN_PORT}" \
  --stateless \
  -- \
  mcp-server-git --repository "${REPOSITORY_ROOT}"
