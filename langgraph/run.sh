#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANGGRAPH_DIR="${ROOT_DIR}/langgraph"
if [[ -x "${ROOT_DIR}/.venv/bin/python" ]]; then
  VENV_DIR="${ROOT_DIR}/.venv"
else
  VENV_DIR="${LANGGRAPH_DIR}/.venv"
fi
BIN_DIR="${VENV_DIR}/bin"
LANGGRAPH_BIN="${BIN_DIR}/langgraph"
PYTHON_BIN="${BIN_DIR}/python"
RUNTIME_DIR="${LANGGRAPH_DIR}/.runtime"
PID_DIR="${RUNTIME_DIR}/pids"
LOG_DIR="${RUNTIME_DIR}/logs"

SUPERVISOR_PORT="${SUPERVISOR_PORT:-2024}"
DEFAULT_PUBLIC_BASE_URL=""
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-${DEFAULT_PUBLIC_BASE_URL}}"
LANGGRAPH_TUNNEL="${LANGGRAPH_TUNNEL:-0}"
LANGGRAPH_NO_BROWSER="${LANGGRAPH_NO_BROWSER:-1}"
LANGGRAPH_RELOAD="${LANGGRAPH_RELOAD:-0}"
LANGGRAPH_BIND_HOST="${LANGGRAPH_BIND_HOST:-}"

mkdir -p "${PID_DIR}" "${LOG_DIR}"

require_venv() {
  if [[ ! -x "${PYTHON_BIN}" ]]; then
    echo "Missing ${PYTHON_BIN}. Create or repair either the repo-root .venv or langgraph/.venv first." >&2
    exit 1
  fi

  if [[ ! -x "${LANGGRAPH_BIN}" ]]; then
    echo "Missing ${LANGGRAPH_BIN}. Install requirements first:" >&2
    echo "  ${BIN_DIR}/pip install -r ${ROOT_DIR}/requirements.txt" >&2
    exit 1
  fi
}

pid_file_for() {
  local name="$1"
  echo "${PID_DIR}/${name}.pid"
}

log_file_for() {
  local name="$1"
  echo "${LOG_DIR}/${name}.log"
}

is_running() {
  local pid_file
  pid_file="$(pid_file_for "$1")"
  [[ -f "${pid_file}" ]] || return 1
  local pid
  pid="$(cat "${pid_file}")"
  kill -0 "${pid}" >/dev/null 2>&1
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-60}"
  local sleep_seconds="${3:-1}"
  local attempt=0

  while (( attempt < attempts )); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    attempt=$((attempt + 1))
    sleep "${sleep_seconds}"
  done

  echo "Timed out waiting for ${url}" >&2
  return 1
}

is_truthy() {
  case "${1,,}" in
    1|true|yes|on)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

display_base_url() {
  if [[ -n "${PUBLIC_BASE_URL}" ]]; then
    echo "${PUBLIC_BASE_URL}"
  else
    echo "http://127.0.0.1:${SUPERVISOR_PORT}"
  fi
}

resolve_bind_host() {
  if [[ -n "${LANGGRAPH_BIND_HOST}" ]]; then
    echo "${LANGGRAPH_BIND_HOST}"
    return
  fi

  if is_truthy "${LANGGRAPH_TUNNEL}"; then
    echo "127.0.0.1"
  elif [[ -n "${PUBLIC_BASE_URL}" ]]; then
    echo "0.0.0.0"
  else
    echo "127.0.0.1"
  fi
}

start_app() {
  local name="$1"
  local app_dir="$2"
  local port="$3"
  shift 3
  local pid_file log_file
  pid_file="$(pid_file_for "${name}")"
  log_file="$(log_file_for "${name}")"
  local bind_host
  bind_host="$(resolve_bind_host)"
  local -a dev_args
  dev_args=(dev --host "${bind_host}" --port "${port}")

  if is_truthy "${LANGGRAPH_TUNNEL}"; then
    dev_args+=(--tunnel)
  fi
  if is_truthy "${LANGGRAPH_NO_BROWSER}"; then
    dev_args+=(--no-browser)
  fi
  if ! is_truthy "${LANGGRAPH_RELOAD}"; then
    dev_args+=(--no-reload)
  fi

  if is_running "${name}"; then
    echo "${name} is already running on port ${port}"
    return 0
  fi

  (
    cd "${app_dir}"
    nohup env "$@" "${LANGGRAPH_BIN}" "${dev_args[@]}" >"${log_file}" 2>&1 </dev/null &
    echo $! >"${pid_file}"
  ) &

  if ! wait_for_http "http://127.0.0.1:${port}/docs"; then
    rm -f "${pid_file}"
    echo "Failed to start ${name}. See ${log_file}" >&2
    return 1
  fi

  echo "Started ${name} on http://${bind_host}:${port}"
}

stop_app() {
  local name="$1"
  local pid_file
  pid_file="$(pid_file_for "${name}")"
  if ! [[ -f "${pid_file}" ]]; then
    echo "${name} is not running"
    return 0
  fi

  local pid
  pid="$(cat "${pid_file}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
  echo "Stopped ${name}"
}

show_urls() {
  local base_url
  base_url="$(display_base_url)"
  cat <<EOF

Studio URLs
- Controller: https://smith.langchain.com/studio/?baseUrl=${base_url}
- Code Analysis: https://smith.langchain.com/studio/?baseUrl=${base_url}
- Jira: https://smith.langchain.com/studio/?baseUrl=${base_url}

Agent Chat UI
- Hosted UI: https://agentchat.vercel.app
- Connect with:
  - Controller graph id: controller_agent
  - Code Analysis graph id: code_analysis_agent
  - Jira graph id: jira_agent
  - Deployment URL:
    - ${base_url}

Logs
- Controller: $(log_file_for "controller-agent")
EOF

  if is_truthy "${LANGGRAPH_TUNNEL}"; then
    cat <<EOF

Tunnel Mode
- Brave/localhost workaround is enabled via \`langgraph dev --tunnel\`.
- Watch the supervisor log for the generated \`trycloudflare.com\` URL.
- Once it appears, use that HTTPS URL as the Studio \`baseUrl\`.
EOF
  elif [[ -n "${PUBLIC_BASE_URL}" ]]; then
    cat <<EOF

Public Base URL
- Using \`${PUBLIC_BASE_URL}\` for Studio and Agent Chat links.
- Nginx Proxy Manager should forward this hostname to \`http://192.168.1.36:${SUPERVISOR_PORT}\`.
EOF
  fi
}

status_apps() {
  if is_running "controller-agent"; then
    echo "controller-agent: running (pid $(cat "$(pid_file_for "controller-agent")"))"
  else
    echo "controller-agent: stopped"
  fi
}

up() {
  require_venv

  start_app \
    "controller-agent" \
    "${LANGGRAPH_DIR}/apps/controller-agent" \
    "${SUPERVISOR_PORT}"

  show_urls
}

down() {
  stop_app "controller-agent"
}

case "${1:-up}" in
  up)
    up
    ;;
  down)
    down
    ;;
  restart)
    down
    up
    ;;
  status)
    status_apps
    ;;
  *)
    echo "Usage: $0 [up|down|restart|status]" >&2
    exit 1
    ;;
esac
