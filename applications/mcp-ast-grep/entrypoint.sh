#!/bin/sh
set -eu

DEFAULT_PROJECT_ROOT="${AST_GREP_DEFAULT_PROJECT_ROOT:-/mnt/eapp/code/homelab}"
ALLOWED_ROOTS="${AST_GREP_ALLOWED_ROOTS:-${DEFAULT_PROJECT_ROOT}}"
LISTEN_HOST="${AST_GREP_HOST:-0.0.0.0}"
LISTEN_PORT="${AST_GREP_PORT:-8096}"
HTTP_PATH="${MCP_HTTP_PATH:-/mcp}"
CONFIG_PATH="${AST_GREP_CONFIG:-/opt/ast-grep-config/sgconfig.yml}"

if [ ! -d "${DEFAULT_PROJECT_ROOT}" ]; then
  echo "[ERR] AST_GREP_DEFAULT_PROJECT_ROOT is missing: ${DEFAULT_PROJECT_ROOT}" >&2
  exit 1
fi

if [ ! -r "${CONFIG_PATH}" ]; then
  echo "[ERR] AST_GREP_CONFIG is missing or unreadable: ${CONFIG_PATH}" >&2
  exit 1
fi

export AST_GREP_DEFAULT_PROJECT_ROOT="${DEFAULT_PROJECT_ROOT}"
export AST_GREP_ALLOWED_ROOTS="${ALLOWED_ROOTS}"
export AST_GREP_CONFIG="${CONFIG_PATH}"

exec python /usr/local/bin/ast-grep-mcp-server.py \
  --transport streamable-http \
  --host "${LISTEN_HOST}" \
  --port "${LISTEN_PORT}" \
  --path "${HTTP_PATH}" \
  --config "${CONFIG_PATH}"
