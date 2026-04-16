#!/usr/bin/env bash
set -euo pipefail

: "${FORTIGATE_HOST:?FORTIGATE_HOST is required}"

FORTIGATE_PORT="${FORTIGATE_PORT:-443}"
FORTIGATE_VDOM="${FORTIGATE_VDOM:-root}"
FORTIGATE_VERIFY_SSL="${FORTIGATE_VERIFY_SSL:-false}"
FORTIGATE_TIMEOUT="${FORTIGATE_TIMEOUT:-30}"
FORTIGATE_API_TOKEN="${FORTIGATE_API_TOKEN:-}"
FORTIGATE_USERNAME="${FORTIGATE_USERNAME:-}"
FORTIGATE_PASSWORD="${FORTIGATE_PASSWORD:-}"
MCP_SERVER_PORT="${MCP_SERVER_PORT:-8814}"
MCP_HTTP_PATH="${MCP_HTTP_PATH:-/mcp}"

if [[ -z "${FORTIGATE_API_TOKEN}" ]] && ([[ -z "${FORTIGATE_USERNAME}" ]] || [[ -z "${FORTIGATE_PASSWORD}" ]]); then
  echo "Either FORTIGATE_API_TOKEN or both FORTIGATE_USERNAME/FORTIGATE_PASSWORD must be set" >&2
  exit 1
fi

CONFIG_PATH="/tmp/fortigate-mcp-config.json"

FORTIGATE_HOST="${FORTIGATE_HOST}" \
FORTIGATE_PORT="${FORTIGATE_PORT}" \
FORTIGATE_VDOM="${FORTIGATE_VDOM}" \
FORTIGATE_VERIFY_SSL="${FORTIGATE_VERIFY_SSL}" \
FORTIGATE_TIMEOUT="${FORTIGATE_TIMEOUT}" \
FORTIGATE_API_TOKEN="${FORTIGATE_API_TOKEN}" \
FORTIGATE_USERNAME="${FORTIGATE_USERNAME}" \
FORTIGATE_PASSWORD="${FORTIGATE_PASSWORD}" \
CONFIG_PATH="${CONFIG_PATH}" \
python3 - <<'PY'
import json
import os


def parse_bool(value: str, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}

host = os.environ["FORTIGATE_HOST"]
port = int(os.environ["FORTIGATE_PORT"])
vdom = os.environ["FORTIGATE_VDOM"]
verify_ssl = parse_bool(os.environ.get("FORTIGATE_VERIFY_SSL"), False)
timeout = int(os.environ.get("FORTIGATE_TIMEOUT", "30"))
api_token = os.environ.get("FORTIGATE_API_TOKEN", "")
username = os.environ.get("FORTIGATE_USERNAME", "")
password = os.environ.get("FORTIGATE_PASSWORD", "")
config_path = os.environ["CONFIG_PATH"]

device = {
    "host": host,
    "port": port,
    "vdom": vdom,
    "verify_ssl": verify_ssl,
    "timeout": timeout,
}

if api_token:
    device["api_token"] = api_token
else:
    device["username"] = username
    device["password"] = password

config = {
    "fortigate": {
        "devices": {
            "default": device,
        }
    },
    "logging": {
        "level": "INFO",
        "console": True,
        "file": None,
    },
}

with open(config_path, "w", encoding="utf-8") as handle:
    json.dump(config, handle)
PY

exec python -m src.fortigate_mcp.server_http \
  --host 0.0.0.0 \
  --port "${MCP_SERVER_PORT}" \
  --path "${MCP_HTTP_PATH}" \
  --config "${CONFIG_PATH}"
