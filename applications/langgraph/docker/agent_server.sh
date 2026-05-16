#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${LANGGRAPH_APP_DIR:-${ROOT_DIR}/agent}"
HOST="${AGENT_SERVER_HOST:-${LANGGRAPH_DEBUG_HOST:-0.0.0.0}}"
PORT="${AGENT_SERVER_PORT:-${LANGGRAPH_DEBUG_PORT:-2124}}"
NO_RELOAD="${AGENT_SERVER_NO_RELOAD:-${LANGGRAPH_DEBUG_NO_RELOAD:-0}}"
N_JOBS_PER_WORKER="${AGENT_SERVER_N_JOBS_PER_WORKER:-${LANGGRAPH_DEBUG_N_JOBS_PER_WORKER:-8}}"
CLEAR_PORT="${AGENT_SERVER_CLEAR_PORT:-1}"
PUBLIC_HOST="${AGENT_SERVER_PUBLIC_HOST:-${LANGGRAPH_DEBUG_PUBLIC_HOST:-}}"

# Load homelab-wide secrets into the shell so ``langgraph`` sees the same keys as
# ``framework.configuration.merged_settings`` (default: <repo>/.config/.env,
# override with ``HOMELAB_CONFIG_ENV``).
HOMELAB_ROOT="$(cd "${ROOT_DIR}/../.." && pwd)"
SECRETS_ENV="${HOMELAB_CONFIG_ENV:-${HOMELAB_SECRETS_ENV:-${HOMELAB_ROOT}/.config/.env}}"
if [[ -f "${SECRETS_ENV}" ]]; then
  _py=""
  if [[ -x "${ROOT_DIR}/.venv/bin/python" ]]; then
    _py="${ROOT_DIR}/.venv/bin/python"
  elif command -v python3 >/dev/null 2>&1; then
    _py="$(command -v python3)"
  fi
  if [[ -n "${_py}" ]]; then
    eval "$("${_py}" - "${SECRETS_ENV}" <<'PY'
import shlex
import sys
from pathlib import Path

try:
    from dotenv import dotenv_values
except ImportError:
    sys.exit(0)

path = Path(sys.argv[1])
if not path.is_file():
    sys.exit(0)
for key, val in dotenv_values(path).items():
    if val is None:
        continue
    print(f"export {shlex.quote(str(key))}={shlex.quote(str(val))}")
PY
)"
  fi
  unset _py
fi

force_kill_port() {
  local target_port="$1"
  local pids=()

  if [[ -z "${target_port}" ]]; then
    return 0
  fi

  if command -v lsof >/dev/null 2>&1; then
    mapfile -t pids < <(lsof -tiTCP:"${target_port}" -sTCP:LISTEN 2>/dev/null || true)
  elif command -v fuser >/dev/null 2>&1; then
    mapfile -t pids < <(fuser -n tcp "${target_port}" 2>/dev/null | tr ' ' '\n' | awk 'NF' || true)
  fi

  if [[ "${#pids[@]}" -eq 0 ]]; then
    echo "  port ${target_port}: already free"
    return 0
  fi

  echo "  port ${target_port}: force-killing pid(s) ${pids[*]}"
  kill -9 "${pids[@]}" 2>/dev/null || true
  sleep 1

  if command -v lsof >/dev/null 2>&1 && lsof -tiTCP:"${target_port}" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "error: port ${target_port} is still in use after force-kill" >&2
    exit 1
  fi
}

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: agent directory not found: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -f "${APP_DIR}/langgraph.json" ]]; then
  echo "error: ${APP_DIR}/langgraph.json is missing" >&2
  exit 1
fi

langgraph_cmd=()

if command -v langgraph >/dev/null 2>&1; then
  langgraph_candidate="$(command -v langgraph)"
  if "${langgraph_candidate}" --help >/dev/null 2>&1; then
    langgraph_cmd=("${langgraph_candidate}")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${ROOT_DIR}/.venv/bin/langgraph" ]]; then
  if "${ROOT_DIR}/.venv/bin/langgraph" --help >/dev/null 2>&1; then
    langgraph_cmd=("${ROOT_DIR}/.venv/bin/langgraph")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${ROOT_DIR}/.venv/bin/python" ]]; then
  if "${ROOT_DIR}/.venv/bin/python" -m langgraph_cli --help >/dev/null 2>&1; then
    langgraph_cmd=("${ROOT_DIR}/.venv/bin/python" "-m" "langgraph_cli")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 ]]; then
  echo "error: langgraph CLI not found. Install dependencies first or provide a working ${ROOT_DIR}/.venv/bin/python." >&2
  exit 1
fi

if [[ -z "${PUBLIC_HOST}" ]]; then
  PUBLIC_HOST="$(
    ip route get 1.1.1.1 2>/dev/null |
      awk '/src/ { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  )"
fi

export LANGGRAPH_CLI_NO_ANALYTICS="${LANGGRAPH_CLI_NO_ANALYTICS:-1}"
export PYTHONPATH="${ROOT_DIR}${PYTHONPATH:+:${PYTHONPATH}}"

LOCAL_HOST_DISPLAY="$([[ "${HOST}" == "0.0.0.0" ]] && echo "127.0.0.1" || echo "${HOST}")"

echo "LangGraph agent server"
echo "  app: ${APP_DIR}"
echo "  local: http://${LOCAL_HOST_DISPLAY}:${PORT}"
if [[ -n "${PUBLIC_HOST}" ]]; then
  echo "  lan:  http://${PUBLIC_HOST}:${PORT}"
fi
echo "  reload: $([[ "${NO_RELOAD}" == "1" ]] && echo disabled || echo enabled)"
echo "  jobs per worker: ${N_JOBS_PER_WORKER}"

if [[ "${CLEAR_PORT}" == "1" ]]; then
  echo "  cleanup port: ${PORT}"
  force_kill_port "${PORT}"
fi

langgraph_args=(
  "${langgraph_cmd[@]}"
  dev
  --host
  "${HOST}"
  --port
  "${PORT}"
  --no-browser
  --n-jobs-per-worker
  "${N_JOBS_PER_WORKER}"
)

if [[ "${NO_RELOAD}" == "1" ]]; then
  langgraph_args+=(--no-reload)
fi

if [[ "$#" -gt 0 ]]; then
  langgraph_args+=("$@")
fi

cd "${APP_DIR}"
exec "${langgraph_args[@]}"
