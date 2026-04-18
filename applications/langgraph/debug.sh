#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${LANGGRAPH_APP_DIR:-${SCRIPT_DIR}/apps/controller-agent}"
CHAT_UI_DIR="${CHAT_UI_DEBUG_APP_DIR:-${SCRIPT_DIR}/../chat-ui}"
HOST="${LANGGRAPH_DEBUG_HOST:-0.0.0.0}"
PORT="${LANGGRAPH_DEBUG_PORT:-2124}"
NO_RELOAD="${LANGGRAPH_DEBUG_NO_RELOAD:-0}"
CHAT_UI_ENABLED="${CHAT_UI_DEBUG_ENABLED:-1}"
CHAT_UI_HOST="${CHAT_UI_DEBUG_HOST:-0.0.0.0}"
CHAT_UI_PORT="${CHAT_UI_DEBUG_PORT:-3000}"
CHAT_UI_PUBLIC_API_URL="${CHAT_UI_DEBUG_PUBLIC_API_URL:-/api}"
CHAT_UI_ASSISTANT_ID="${CHAT_UI_DEBUG_ASSISTANT_ID:-controller_agent}"
CHAT_UI_AUTH_SCHEME="${CHAT_UI_DEBUG_AUTH_SCHEME:-}"
CHAT_UI_LANGGRAPH_API_URL="${CHAT_UI_DEBUG_LANGGRAPH_API_URL:-http://127.0.0.1:${PORT}}"
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"
LOG_DIR="${RUNTIME_DIR}/logs"
PID_DIR="${RUNTIME_DIR}/pids"

if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  DEFAULT_CLEAR_PORTS="${PORT},${CHAT_UI_PORT}"
else
  DEFAULT_CLEAR_PORTS="${PORT}"
fi

CLEAR_PORTS_RAW="${LANGGRAPH_DEBUG_CLEAR_PORTS:-${DEFAULT_CLEAR_PORTS}}"

mkdir -p "${LOG_DIR}" "${PID_DIR}"

langgraph_pid=""
chat_ui_pid=""

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

cleanup() {
  local exit_code=$?

  trap - EXIT INT TERM

  if [[ -n "${chat_ui_pid}" ]] && kill -0 "${chat_ui_pid}" 2>/dev/null; then
    kill "${chat_ui_pid}" 2>/dev/null || true
  fi

  if [[ -n "${langgraph_pid}" ]] && kill -0 "${langgraph_pid}" 2>/dev/null; then
    kill "${langgraph_pid}" 2>/dev/null || true
  fi

  wait "${chat_ui_pid}" 2>/dev/null || true
  wait "${langgraph_pid}" 2>/dev/null || true

  rm -f "${PID_DIR}/langgraph-debug.pid" "${PID_DIR}/chat-ui-debug.pid"
  exit "${exit_code}"
}

tail_recent_logs() {
  local label="$1"
  local path="$2"

  if [[ -f "${path}" ]]; then
    echo
    echo "${label} log tail: ${path}"
    tail -n 20 "${path}" || true
  fi
}

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: app directory not found: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -f "${APP_DIR}/langgraph.json" ]]; then
  echo "error: ${APP_DIR}/langgraph.json is missing" >&2
  exit 1
fi

if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  if [[ ! -d "${CHAT_UI_DIR}" ]]; then
    echo "error: chat-ui directory not found: ${CHAT_UI_DIR}" >&2
    exit 1
  fi

  if [[ ! -f "${CHAT_UI_DIR}/package.json" ]]; then
    echo "error: ${CHAT_UI_DIR}/package.json is missing" >&2
    exit 1
  fi
fi

langgraph_cmd=()
chat_ui_cmd=()

if command -v langgraph >/dev/null 2>&1; then
  langgraph_candidate="$(command -v langgraph)"
  if "${langgraph_candidate}" --help >/dev/null 2>&1; then
    langgraph_cmd=("${langgraph_candidate}")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${SCRIPT_DIR}/.venv/bin/langgraph" ]]; then
  if "${SCRIPT_DIR}/.venv/bin/langgraph" --help >/dev/null 2>&1; then
    langgraph_cmd=("${SCRIPT_DIR}/.venv/bin/langgraph")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 && -x "${SCRIPT_DIR}/.venv/bin/python" ]]; then
  if "${SCRIPT_DIR}/.venv/bin/python" -m langgraph_cli --help >/dev/null 2>&1; then
    langgraph_cmd=("${SCRIPT_DIR}/.venv/bin/python" "-m" "langgraph_cli")
  fi
fi

if [[ "${#langgraph_cmd[@]}" -eq 0 ]]; then
  echo "error: langgraph CLI not found. Install dependencies first or provide a working applications/langgraph/.venv/bin/python." >&2
  exit 1
fi

if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  if [[ -x "${CHAT_UI_DIR}/node_modules/.bin/next" ]]; then
    chat_ui_cmd=("${CHAT_UI_DIR}/node_modules/.bin/next")
  elif command -v pnpm >/dev/null 2>&1; then
    chat_ui_cmd=("pnpm" "exec" "next")
  elif command -v corepack >/dev/null 2>&1; then
    chat_ui_cmd=("corepack" "pnpm" "exec" "next")
  fi

  if [[ "${#chat_ui_cmd[@]}" -eq 0 ]]; then
    echo "error: chat-ui dev command not found. Install dependencies in ${CHAT_UI_DIR} first." >&2
    exit 1
  fi
fi

PUBLIC_HOST="${LANGGRAPH_DEBUG_PUBLIC_HOST:-}"
if [[ -z "${PUBLIC_HOST}" ]]; then
  PUBLIC_HOST="$(
    ip route get 1.1.1.1 2>/dev/null |
      awk '/src/ { for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }'
  )"
fi

export LANGGRAPH_CLI_NO_ANALYTICS="${LANGGRAPH_CLI_NO_ANALYTICS:-1}"
export PYTHONPATH="${SCRIPT_DIR}/src${PYTHONPATH:+:${PYTHONPATH}}"

read -r -a CLEAR_PORTS <<< "${CLEAR_PORTS_RAW//,/ }"
LOCAL_HOST_DISPLAY="$([[ "${HOST}" == "0.0.0.0" ]] && echo "127.0.0.1" || echo "${HOST}")"
CHAT_UI_LOCAL_HOST_DISPLAY="$([[ "${CHAT_UI_HOST}" == "0.0.0.0" ]] && echo "127.0.0.1" || echo "${CHAT_UI_HOST}")"
LANGGRAPH_LOG="${LOG_DIR}/langgraph-debug.log"
CHAT_UI_LOG="${LOG_DIR}/chat-ui-debug.log"

echo "LangGraph debug server"
echo "  app: ${APP_DIR}"
echo "  local: http://${LOCAL_HOST_DISPLAY}:${PORT}"
if [[ -n "${PUBLIC_HOST}" ]]; then
  echo "  lan:  http://${PUBLIC_HOST}:${PORT}"
fi
echo "  reload: $([[ "${NO_RELOAD}" == "1" ]] && echo disabled || echo enabled)"

if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  echo "Chat UI debug server"
  echo "  app: ${CHAT_UI_DIR}"
  echo "  local: http://${CHAT_UI_LOCAL_HOST_DISPLAY}:${CHAT_UI_PORT}"
  if [[ -n "${PUBLIC_HOST}" ]]; then
    echo "  lan:  http://${PUBLIC_HOST}:${CHAT_UI_PORT}"
  fi
  echo "  assistant: ${CHAT_UI_ASSISTANT_ID}"
  echo "  proxy api: ${CHAT_UI_PUBLIC_API_URL}"
  echo "  langgraph upstream: ${CHAT_UI_LANGGRAPH_API_URL}"
fi

echo "  cleanup ports: ${CLEAR_PORTS[*]}"
echo "  logs:"
echo "    langgraph: ${LANGGRAPH_LOG}"
if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  echo "    chat-ui: ${CHAT_UI_LOG}"
fi
echo "  pids:"
echo "    langgraph: ${PID_DIR}/langgraph-debug.pid"
if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  echo "    chat-ui: ${PID_DIR}/chat-ui-debug.pid"
fi
echo "Press Ctrl-C to stop all local debug services."

for clear_port in "${CLEAR_PORTS[@]}"; do
  force_kill_port "${clear_port}"
done

trap cleanup EXIT INT TERM

langgraph_args=(
  "${langgraph_cmd[@]}"
  dev
  --host
  "${HOST}"
  --port
  "${PORT}"
  --no-browser
)

if [[ "${NO_RELOAD}" == "1" ]]; then
  langgraph_args+=(--no-reload)
fi

if [[ "$#" -gt 0 ]]; then
  langgraph_args+=("$@")
fi

: > "${LANGGRAPH_LOG}"
(
  cd "${APP_DIR}"
  exec "${langgraph_args[@]}"
) >>"${LANGGRAPH_LOG}" 2>&1 &
langgraph_pid=$!
printf '%s\n' "${langgraph_pid}" > "${PID_DIR}/langgraph-debug.pid"

if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  chat_ui_args=(
    "${chat_ui_cmd[@]}"
    dev
    --hostname
    "${CHAT_UI_HOST}"
    --port
    "${CHAT_UI_PORT}"
  )

  : > "${CHAT_UI_LOG}"
  (
    cd "${CHAT_UI_DIR}"
    export HOSTNAME="${CHAT_UI_HOST}"
    export PORT="${CHAT_UI_PORT}"
    export NEXT_PUBLIC_API_URL="${CHAT_UI_PUBLIC_API_URL}"
    export NEXT_PUBLIC_ASSISTANT_ID="${CHAT_UI_ASSISTANT_ID}"
    export NEXT_PUBLIC_AUTH_SCHEME="${CHAT_UI_AUTH_SCHEME}"
    export LANGGRAPH_API_URL="${CHAT_UI_LANGGRAPH_API_URL}"
    export NEXT_TELEMETRY_DISABLED=1
    exec "${chat_ui_args[@]}"
  ) >>"${CHAT_UI_LOG}" 2>&1 &
  chat_ui_pid=$!
  printf '%s\n' "${chat_ui_pid}" > "${PID_DIR}/chat-ui-debug.pid"
fi

supervised_pids=("${langgraph_pid}")
if [[ -n "${chat_ui_pid}" ]]; then
  supervised_pids+=("${chat_ui_pid}")
fi

set +e
if [[ "${#supervised_pids[@]}" -eq 1 ]]; then
  wait "${supervised_pids[0]}"
  exit_code=$?
else
  wait -n "${supervised_pids[@]}"
  exit_code=$?
fi
set -e

echo
echo "A local debug process exited with status ${exit_code}."
tail_recent_logs "LangGraph" "${LANGGRAPH_LOG}"
if [[ "${CHAT_UI_ENABLED}" == "1" ]]; then
  tail_recent_logs "Chat UI" "${CHAT_UI_LOG}"
fi

exit "${exit_code}"
