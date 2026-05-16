#!/usr/bin/env bash
# Trigger rag-engine backfill via POST /v1/backfill (default), or optionally run
# ``python -m ingest.backfill`` inside a container over SSH (legacy).
#
# Default loads <repo>/.secrets/.env for RAG_ENGINE_BASE_URL and RAG_ENGINE_API_KEY.
# Long runs: set RAG_BACKFILL_HTTP_TIMEOUT_SEC (seconds) for the client; raise nginx
# proxy read timeouts for the rag-engine route so the connection is not cut mid-run.
#
# By default this script also tails the rag-engine swarm service logs over SSH
# while the POST is in flight, so you can watch tqdm progress and per-file logs
# (chunking, embedding, chroma upserts). Pass --no-logs to disable, or
# --service-name / --logs-host overrides if your topology differs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE_CLIENT="${REPO_ROOT}/scripts/misc/rag_backfill_remote.py"

DEFAULT_HOST="nodadyoushutup@192.168.1.120"
DEFAULT_SSH_KEY="${RAG_BACKFILL_SSH_KEY:-${REPO_ROOT}/.config/.ssh/id_ed25519}"
DEFAULT_KNOWN_HOSTS="${RAG_BACKFILL_KNOWN_HOSTS:-${REPO_ROOT}/.config/.ssh/known_hosts}"
DEFAULT_CONTAINER_FILTER="name=rag-engine"
DEFAULT_SERVICE_NAME="rag-engine"

REMOTE_HOST="${RAG_BACKFILL_HOST:-${DEFAULT_HOST}}"
SSH_KEY="${RAG_BACKFILL_SSH_KEY:-${DEFAULT_SSH_KEY}}"
KNOWN_HOSTS="${RAG_BACKFILL_KNOWN_HOSTS:-${DEFAULT_KNOWN_HOSTS}}"
CONTAINER_FILTER="${RAG_BACKFILL_CONTAINER_FILTER:-${DEFAULT_CONTAINER_FILTER}}"
LOGS_HOST="${RAG_BACKFILL_LOGS_HOST:-${REMOTE_HOST}}"
SERVICE_NAME="${RAG_BACKFILL_SERVICE_NAME:-${DEFAULT_SERVICE_NAME}}"
STREAM_LOGS=1
LOG_PID=""
USE_SSH_EXEC=0
USE_SSH_LOCAL=0
PASS_ARGS=()

usage() {
  cat <<EOF
Usage: scripts/misc/rag_backfill.sh [options] [-- <backfill args>]

Default: POST \$RAG_ENGINE_BASE_URL/v1/backfill (see .secrets/.env). Same flags as
  python -m ingest.backfill  (e.g. --dry-run, --yes, --prune-orphans).

  scripts/misc/rag_backfill.sh --dry-run
  scripts/misc/rag_backfill.sh --yes --prune-orphans
  scripts/misc/rag_backfill.sh --yes --prune-orphans-only --prune-dry-run

Legacy (docker exec on Swarm host over SSH):

  scripts/misc/rag_backfill.sh --ssh-exec --yes --prune-orphans

Options
-------
  --ssh-exec                 Run backfill inside the rag-engine container (SSH + docker exec).
  --local                    Only with --ssh-exec: use this machine's Docker daemon.
  --host <user@host>         SSH target for --ssh-exec (default: ${DEFAULT_HOST}).
  --logs-host <user@host>    SSH target for live log tail (default: --host or ${DEFAULT_HOST}).
  --service-name <name>      Swarm service name to follow (default: ${DEFAULT_SERVICE_NAME}).
  --no-logs                  Do not stream rag-engine docker logs while POSTing /v1/backfill.
  --ssh-key, --known-hosts, --container-filter
                             SSH / docker ps filter (only with --ssh-exec).
  -h, --help

Path allowlists / excludes are defined on the rag-engine service (e.g. RAG_ALLOWED_PATH_PREFIXES
in .secrets/.env after redeploy). This script does not need the repo mounted locally for the
HTTP default.
EOF
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
fail()     { echo "[ERR] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

load_repo_env() {
  local envf="${REPO_ROOT}/.secrets/.env"
  if [[ -f "$envf" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$envf"
    set +a
  fi
}

parse_args() {
  local logs_host_explicit=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssh-exec)
        USE_SSH_EXEC=1; shift ;;
      --local)
        USE_SSH_LOCAL=1; shift ;;
      --host)
        [[ $# -ge 2 ]] || fail "--host requires a value"
        REMOTE_HOST="$2"
        if [[ "$logs_host_explicit" == "0" ]]; then LOGS_HOST="$2"; fi
        shift 2 ;;
      --logs-host)
        [[ $# -ge 2 ]] || fail "--logs-host requires a value"
        LOGS_HOST="$2"
        logs_host_explicit=1
        shift 2 ;;
      --service-name)
        [[ $# -ge 2 ]] || fail "--service-name requires a value"
        SERVICE_NAME="$2"; shift 2 ;;
      --no-logs)
        STREAM_LOGS=0; shift ;;
      --logs)
        STREAM_LOGS=1; shift ;;
      --ssh-key)
        [[ $# -ge 2 ]] || fail "--ssh-key requires a value"
        SSH_KEY="$2"; shift 2 ;;
      --known-hosts)
        [[ $# -ge 2 ]] || fail "--known-hosts requires a value"
        KNOWN_HOSTS="$2"; shift 2 ;;
      --container-filter)
        [[ $# -ge 2 ]] || fail "--container-filter requires a value"
        CONTAINER_FILTER="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do PASS_ARGS+=("$1"); shift; done
        ;;
      *)
        PASS_ARGS+=("$1"); shift ;;
    esac
  done
}

build_local_docker_cmd() {
  need_cmd docker
  DOCKER_RUNNER=(docker)
}

build_remote_docker_cmd() {
  need_cmd ssh
  [[ -r "$SSH_KEY" ]] || fail "SSH key not readable: $SSH_KEY"

  SSH_CMD=(ssh
    -o StrictHostKeyChecking=no
    -o "UserKnownHostsFile=$KNOWN_HOSTS"
    -i "$SSH_KEY"
  )
  if [[ -t 0 && -t 1 ]]; then
    SSH_CMD+=(-tt)
  fi
  SSH_CMD+=("$REMOTE_HOST")
  DOCKER_RUNNER=("${SSH_CMD[@]}" sudo docker)
}

resolve_container_id() {
  local id
  if [[ "$USE_SSH_LOCAL" == "1" ]]; then
    id="$(docker ps --filter "$CONTAINER_FILTER" --format '{{.ID}}' | head -n1 || true)"
  else
    id="$("${SSH_CMD[@]}" "sudo docker ps --filter '$CONTAINER_FILTER' --format '{{.ID}}' | head -n1" || true)"
    id="${id//$'\r'/}"
    id="${id//[[:space:]]/}"
  fi
  [[ -n "$id" ]] || fail "No running container matched filter '$CONTAINER_FILTER' on target."
  printf '%s\n' "$id"
}

run_backfill_exec() {
  local container_id="$1"; shift
  local exec_flags=(exec)
  if [[ -t 0 && -t 1 ]]; then
    exec_flags+=(-it)
  fi

  local cmd=("${DOCKER_RUNNER[@]}" "${exec_flags[@]}" "$container_id"
             python -m ingest.backfill "$@")

  log_info "Running: ${cmd[*]}"
  "${cmd[@]}"
}

INTERRUPT_COUNT=0
HTTP_CHILD_PID=""

start_log_tail() {
  if [[ "$STREAM_LOGS" != "1" ]]; then
    return 0
  fi
  if ! command -v ssh >/dev/null 2>&1; then
    log_info "ssh not found; not streaming docker logs (use --no-logs to silence)."
    return 0
  fi
  if [[ ! -r "$SSH_KEY" ]]; then
    log_info "SSH key '$SSH_KEY' not readable; not streaming docker logs."
    return 0
  fi

  local ssh_args=(
    -o StrictHostKeyChecking=no
    -o "UserKnownHostsFile=$KNOWN_HOSTS"
    -o ServerAliveInterval=30
    -o ServerAliveCountMax=4
    -i "$SSH_KEY"
    "$LOGS_HOST"
    "sudo docker service logs --raw --tail 0 -f '${SERVICE_NAME}'"
  )

  log_info "Streaming logs from ${LOGS_HOST}:${SERVICE_NAME} (--no-logs to disable)."

  # Run the ssh|sed pipeline in its own process group so stop_log_tail can
  # clean up both ssh and sed reliably even on Ctrl+C.
  local launcher=()
  if command -v setsid >/dev/null 2>&1; then
    launcher=(setsid -w bash -c)
  else
    launcher=(bash -c)
  fi

  "${launcher[@]}" 'exec ssh "$@" 2>&1 | sed -u "s/^/['"${SERVICE_NAME}"'] /"' \
    rag_log_tail "${ssh_args[@]}" &
  LOG_PID=$!
}

stop_log_tail() {
  if [[ -z "${LOG_PID}" ]]; then
    return 0
  fi
  # Kill the whole process group of the launcher (covers ssh + sed).
  kill -TERM -- "-${LOG_PID}" 2>/dev/null || true
  kill -TERM "${LOG_PID}" 2>/dev/null || true

  local i
  for i in 1 2 3 4 5; do
    if ! kill -0 "${LOG_PID}" 2>/dev/null; then
      break
    fi
    sleep 0.2
  done

  if kill -0 "${LOG_PID}" 2>/dev/null; then
    kill -KILL -- "-${LOG_PID}" 2>/dev/null || true
    kill -KILL "${LOG_PID}" 2>/dev/null || true
  fi
  wait "${LOG_PID}" 2>/dev/null || true
  LOG_PID=""
}

on_sigint_http() {
  INTERRUPT_COUNT=$((INTERRUPT_COUNT + 1))
  if [[ "${INTERRUPT_COUNT}" -ge 2 ]]; then
    echo >&2
    log_warn "Second Ctrl+C — forcing exit; rag-engine server keeps running."
    stop_log_tail
    if [[ -n "${HTTP_CHILD_PID}" ]]; then
      kill -KILL "${HTTP_CHILD_PID}" 2>/dev/null || true
    fi
    exit 130
  fi
  echo >&2
  log_warn "Ctrl+C received. Detaching local viewer."
  log_warn "The rag-engine backfill continues running on the server."
  log_warn "Press Ctrl+C again to force-exit this client immediately."
  # Stop noisy log stream first so the user sees the friendly message.
  stop_log_tail
  # Forward SIGINT to the python client so urlopen unwinds even if the signal
  # didn't reach it directly (e.g. when this script is itself signalled with
  # `kill -INT` rather than via the terminal).
  if [[ -n "${HTTP_CHILD_PID}" ]]; then
    kill -INT "${HTTP_CHILD_PID}" 2>/dev/null || true
  fi
}

run_http() {
  need_cmd python3
  [[ -f "$REMOTE_CLIENT" ]] || fail "Missing $REMOTE_CLIENT"
  log_info "POST ${RAG_ENGINE_BASE_URL:-}/v1/backfill"

  start_log_tail

  INTERRUPT_COUNT=0
  trap 'stop_log_tail' EXIT TERM
  trap 'on_sigint_http' INT

  set +e
  python3 "$REMOTE_CLIENT" "${PASS_ARGS[@]}" &
  HTTP_CHILD_PID=$!
  # `wait` is interruptible by traps; on SIGINT the trap fires and forwards
  # the signal to the python child, which then exits and unblocks wait.
  local rc=0
  while :; do
    if wait "${HTTP_CHILD_PID}"; then
      rc=0
      break
    else
      rc=$?
      # 127/128+ exit codes indicate the wait was interrupted; loop and re-wait
      # so we always reap the child cleanly. Once the child has actually exited
      # `wait` returns its real exit code on the next call.
      if ! kill -0 "${HTTP_CHILD_PID}" 2>/dev/null; then
        break
      fi
    fi
  done
  HTTP_CHILD_PID=""
  set -e

  stop_log_tail
  trap - EXIT INT TERM
  return "$rc"
}

main() {
  parse_args "$@"

  if [[ "$USE_SSH_LOCAL" == "1" && "$USE_SSH_EXEC" != "1" ]]; then
    fail "--local is only valid with --ssh-exec"
  fi

  if [[ "$USE_SSH_EXEC" == "1" ]]; then
    if [[ "$USE_SSH_LOCAL" == "1" ]]; then
      build_local_docker_cmd
      log_info "Target: local Docker, filter '$CONTAINER_FILTER'"
    else
      build_remote_docker_cmd
      log_info "Target: ssh $REMOTE_HOST, filter '$CONTAINER_FILTER'"
    fi
    local container_id
    container_id="$(resolve_container_id)"
    log_info "rag-engine container id: $container_id"
    run_backfill_exec "$container_id" "${PASS_ARGS[@]}"
    return
  fi

  load_repo_env
  run_http
}

main "$@"

