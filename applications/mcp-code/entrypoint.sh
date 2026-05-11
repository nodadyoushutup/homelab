#!/bin/sh
set -eu

WORKSPACE_ROOT="${MCP_CODE_WORKSPACE_ROOT:-/mnt/eapp/code/homelab}"
LISTEN_HOST="${MCP_CODE_HOST:-0.0.0.0}"
LISTEN_PORT="${MCP_CODE_PORT:-8100}"
HTTP_PATH="${MCP_HTTP_PATH:-/mcp}"

FS_PROXY_PORT="${MCP_CODE_FS_PROXY_PORT:-18101}"
GIT_PROXY_PORT="${MCP_CODE_GIT_PROXY_PORT:-18102}"
AG_PROXY_PORT="${MCP_CODE_AG_PROXY_PORT:-18103}"

if [ ! -d "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_CODE_WORKSPACE_ROOT is missing: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

if [ ! -w "${WORKSPACE_ROOT}" ]; then
  echo "[ERR] MCP_CODE_WORKSPACE_ROOT is not writable: ${WORKSPACE_ROOT}" >&2
  exit 1
fi

MCP_PROXY_BIN="/opt/mcp-proxy-venv/bin/mcp-proxy"
export PATH="/opt/mcp-proxy-venv/bin:/opt/mcp-code-venv/bin:/opt/npm-global/bin:${PATH}"
export MCP_CODE_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
export MCP_CODE_HOST="${LISTEN_HOST}"
export MCP_CODE_PORT="${LISTEN_PORT}"
export MCP_HTTP_PATH="${HTTP_PATH}"
export MCP_CODE_AST_GREP_PYTHON="${MCP_CODE_AST_GREP_PYTHON:-/opt/mcp-code-venv/bin/python}"
export MCP_CODE_AST_GREP_SERVER_PATH="${MCP_CODE_AST_GREP_SERVER_PATH:-/opt/mcp-code/ast-grep-server.py}"

# Defaults for ast-grep child (stdio), consumed by ast-grep MCP server script.
export AST_GREP_DEFAULT_PROJECT_ROOT="${AST_GREP_DEFAULT_PROJECT_ROOT:-${WORKSPACE_ROOT}}"
export AST_GREP_ALLOWED_ROOTS="${AST_GREP_ALLOWED_ROOTS:-${WORKSPACE_ROOT}}"
export AST_GREP_CONFIG="${AST_GREP_CONFIG:-/opt/ast-grep-config/sgconfig.yml}"

PROXY_PIDS=""
cleanup() {
  for pid in ${PROXY_PIDS}; do
    kill "${pid}" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

# Native: pure-Python tool implementations (no subprocess MCP servers).
if [ "${MCP_CODE_USE_NATIVE:-0}" = "1" ] || [ "${MCP_CODE_USE_NATIVE:-0}" = "true" ]; then
  exec /opt/mcp-code-venv/bin/python -m mcp_code
fi

# Default aggregate uses stdio upstreams inside Python (server.py). Optional HTTP mode
# starts local mcp-proxy bridges (brittle; for experiments only).
if [ "${MCP_CODE_UPSTREAM_TRANSPORT:-stdio}" = "http" ]; then
  "${MCP_PROXY_BIN}" \
    --host 127.0.0.1 \
    --port "${FS_PROXY_PORT}" \
    --transport streamablehttp \
    -- \
    /opt/npm-global/bin/mcp-server-filesystem "${WORKSPACE_ROOT}" &
  PROXY_PIDS="${PROXY_PIDS} $!"

  "${MCP_PROXY_BIN}" \
    --host 127.0.0.1 \
    --port "${GIT_PROXY_PORT}" \
    --transport streamablehttp \
    -- \
    /opt/mcp-code-venv/bin/mcp-server-git --repository "${WORKSPACE_ROOT}" &
  PROXY_PIDS="${PROXY_PIDS} $!"

  "${MCP_PROXY_BIN}" \
    --host 127.0.0.1 \
    --port "${AG_PROXY_PORT}" \
    --transport streamablehttp \
    -- \
    "${MCP_CODE_AST_GREP_PYTHON}" "${MCP_CODE_AST_GREP_SERVER_PATH}" --transport stdio &
  PROXY_PIDS="${PROXY_PIDS} $!"

  export MCP_CODE_FILESYSTEM_PROXY_URL="http://127.0.0.1:${FS_PROXY_PORT}/mcp"
  export MCP_CODE_GIT_PROXY_URL="http://127.0.0.1:${GIT_PROXY_PORT}/mcp"
  export MCP_CODE_AST_GREP_PROXY_URL="http://127.0.0.1:${AG_PROXY_PORT}/mcp"

  wait_tcp() {
    _port="$1"
    _label="$2"
    /opt/mcp-code-venv/bin/python - <<PY
import socket, time, sys
port = int("${_port}")
for i in range(200):
    try:
        s = socket.create_connection(("127.0.0.1", port), 2)
        s.close()
        sys.exit(0)
    except OSError:
        time.sleep(0.15)
print("timeout waiting for ${_label} on port", port, file=sys.stderr)
sys.exit(1)
PY
  }

  wait_tcp "${FS_PROXY_PORT}" "filesystem-mcp-proxy"
  wait_tcp "${GIT_PROXY_PORT}" "git-mcp-proxy"
  wait_tcp "${AG_PROXY_PORT}" "ast-grep-mcp-proxy"
fi

exec /opt/mcp-code-venv/bin/python -m mcp_code
