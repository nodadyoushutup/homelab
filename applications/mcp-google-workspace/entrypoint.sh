#!/bin/sh
set -eu

if [ -z "${GOOGLE_OAUTH_CLIENT_ID:-}" ]; then
  echo "[ERR] GOOGLE_OAUTH_CLIENT_ID is required" >&2
  exit 1
fi

if [ -z "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]; then
  echo "[ERR] GOOGLE_OAUTH_CLIENT_SECRET is required" >&2
  exit 1
fi

if [ -z "${WORKSPACE_EXTERNAL_URL:-}" ]; then
  echo "[ERR] WORKSPACE_EXTERNAL_URL is required (public HTTPS origin, no trailing slash)" >&2
  exit 1
fi

LISTEN_PORT="${MCP_GOOGLE_WORKSPACE_LISTEN_PORT:-${PORT:-8086}}"
CREDENTIALS_DIR="${WORKSPACE_MCP_CREDENTIALS_DIR:-/tmp/workspace-mcp/credentials}"
mkdir -p "${CREDENTIALS_DIR}"

export PORT="${LISTEN_PORT}"
export WORKSPACE_MCP_PORT="${LISTEN_PORT}"
export WORKSPACE_MCP_HOST="${WORKSPACE_MCP_HOST:-0.0.0.0}"
export WORKSPACE_MCP_CREDENTIALS_DIR="${CREDENTIALS_DIR}"

set -- workspace-mcp --transport streamable-http --single-user

TOOL_TIER="${GOOGLE_WORKSPACE_MCP_TOOL_TIER:-core}"
if [ -n "${TOOL_TIER}" ]; then
  set -- "$@" --tool-tier "${TOOL_TIER}"
fi

if [ "${GOOGLE_WORKSPACE_MCP_READ_ONLY:-false}" = "true" ]; then
  set -- "$@" --read-only
fi

if [ -n "${GOOGLE_WORKSPACE_MCP_TOOLS:-}" ]; then
  # Intentional word splitting: expected format "gmail drive calendar"
  # shellcheck disable=SC2086
  set -- "$@" --tools ${GOOGLE_WORKSPACE_MCP_TOOLS}
fi

exec "$@"
