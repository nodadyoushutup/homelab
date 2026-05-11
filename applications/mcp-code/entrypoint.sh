#!/bin/sh
set -eu

WORKSPACE_ROOT="${MCP_CODE_WORKSPACE_ROOT:-/mnt/eapp/code/homelab}"
LISTEN_HOST="${MCP_CODE_HOST:-0.0.0.0}"
LISTEN_PORT="${MCP_CODE_PORT:-8100}"
HTTP_PATH="${MCP_HTTP_PATH:-/mcp}"

if [ ! -d "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_CODE_WORKSPACE_ROOT is missing: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

if [ ! -w "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_CODE_WORKSPACE_ROOT is not writable: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

export PATH="/opt/mcp-code-venv/bin:/opt/npm-global/bin:${PATH}"
export MCP_CODE_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
export MCP_CODE_HOST="${LISTEN_HOST}"
export MCP_CODE_PORT="${LISTEN_PORT}"
export MCP_HTTP_PATH="${HTTP_PATH}"
export MCP_CODE_AST_GREP_PYTHON="${MCP_CODE_AST_GREP_PYTHON:-/opt/mcp-code-venv/bin/python}"
export MCP_CODE_AST_GREP_SERVER_PATH="${MCP_CODE_AST_GREP_SERVER_PATH:-/opt/mcp-code/ast-grep-server.py}"

exec /opt/mcp-code-venv/bin/python -m mcp_code
