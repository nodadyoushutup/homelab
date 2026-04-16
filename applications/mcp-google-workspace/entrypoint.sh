#!/bin/sh
set -eu

SERVICE_ACCOUNT_FILE="${WORKSPACE_MCP_SERVICE_ACCOUNT_FILE:-/run/secrets/service_account.json}"
DELEGATED_USER="${WORKSPACE_MCP_DELEGATED_USER:-}"
LISTEN_PORT="${MCP_GOOGLE_WORKSPACE_LISTEN_PORT:-${PORT:-8086}}"

if [ ! -r "${SERVICE_ACCOUNT_FILE}" ]; then
  echo "[ERR] WORKSPACE_MCP_SERVICE_ACCOUNT_FILE is missing or unreadable: ${SERVICE_ACCOUNT_FILE}" >&2
  exit 1
fi

if [ -z "${DELEGATED_USER}" ]; then
  echo "[ERR] WORKSPACE_MCP_DELEGATED_USER is required" >&2
  exit 1
fi

case "${DELEGATED_USER}" in
  *@*) ;;
  *)
    echo "[ERR] WORKSPACE_MCP_DELEGATED_USER must be an email address" >&2
    exit 1
    ;;
esac

CREDENTIALS_DIR="${WORKSPACE_MCP_CREDENTIALS_DIR:-/tmp/workspace-mcp/credentials}"
mkdir -p "${CREDENTIALS_DIR}"

export PORT="${LISTEN_PORT}"
export WORKSPACE_MCP_PORT="${LISTEN_PORT}"
export WORKSPACE_MCP_HOST="${WORKSPACE_MCP_HOST:-0.0.0.0}"
export WORKSPACE_MCP_USE_SERVICE_ACCOUNT="true"
export WORKSPACE_MCP_SERVICE_ACCOUNT_FILE="${SERVICE_ACCOUNT_FILE}"
export WORKSPACE_MCP_DELEGATED_USER="${DELEGATED_USER}"
export USER_GOOGLE_EMAIL="${USER_GOOGLE_EMAIL:-${DELEGATED_USER}}"
export MCP_ENABLE_OAUTH21="${MCP_ENABLE_OAUTH21:-false}"
export WORKSPACE_MCP_STATELESS_MODE="${WORKSPACE_MCP_STATELESS_MODE:-false}"
export WORKSPACE_MCP_CREDENTIALS_DIR="${CREDENTIALS_DIR}"

set -- workspace-mcp --transport streamable-http --single-user

TOOL_TIER="${GOOGLE_WORKSPACE_MCP_TOOL_TIER:-complete}"
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
