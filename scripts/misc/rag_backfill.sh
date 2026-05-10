#!/usr/bin/env bash
# Trigger rag-engine backfill via POST /v1/backfill (default), or optionally run
# ``python -m rag_engine.backfill`` inside a container over SSH (legacy).
#
# Default loads <repo>/.secrets/.env for RAG_ENGINE_BASE_URL and RAG_ENGINE_API_KEY.
# Long runs: set RAG_BACKFILL_HTTP_TIMEOUT_SEC (seconds) for the client; raise nginx
# proxy read timeouts for the rag-engine route so the connection is not cut mid-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE_CLIENT="${REPO_ROOT}/scripts/misc/rag_backfill_remote.py"

DEFAULT_HOST="nodadyoushutup@192.168.1.120"
DEFAULT_SSH_KEY="/mnt/eapp/config/.ssh/id_ed25519"
DEFAULT_KNOWN_HOSTS="/mnt/eapp/config/.ssh/known_hosts"
DEFAULT_CONTAINER_FILTER="name=rag-engine"

REMOTE_HOST="${RAG_BACKFILL_HOST:-${DEFAULT_HOST}}"
SSH_KEY="${RAG_BACKFILL_SSH_KEY:-${DEFAULT_SSH_KEY}}"
KNOWN_HOSTS="${RAG_BACKFILL_KNOWN_HOSTS:-${DEFAULT_KNOWN_HOSTS}}"
CONTAINER_FILTER="${RAG_BACKFILL_CONTAINER_FILTER:-${DEFAULT_CONTAINER_FILTER}}"
USE_SSH_EXEC=0
USE_SSH_LOCAL=0
PASS_ARGS=()

usage() {
  cat <<EOF
Usage: scripts/misc/rag_backfill.sh [options] [-- <backfill args>]

Default: POST \$RAG_ENGINE_BASE_URL/v1/backfill (see .secrets/.env). Same flags as
  python -m rag_engine.backfill  (e.g. --dry-run, --yes, --prune-orphans).

  scripts/misc/rag_backfill.sh --dry-run
  scripts/misc/rag_backfill.sh --yes --prune-orphans
  scripts/misc/rag_backfill.sh --yes --prune-orphans-only --prune-dry-run

Legacy (docker exec on Swarm host over SSH):

  scripts/misc/rag_backfill.sh --ssh-exec --yes --prune-orphans

Options
-------
  --ssh-exec                 Run backfill inside the rag-engine container (SSH + docker exec).
  --local                    Only with --ssh-exec: use this machine's Docker daemon.
  --host <user@host>         SSH target (default: ${DEFAULT_HOST}).
  --ssh-key, --known-hosts, --container-filter
                             SSH / docker ps filter (only with --ssh-exec).
  -h, --help

Path allowlists / excludes are defined on the rag-engine service (e.g. RAG_ALLOWED_PATH_PREFIXES
in .secrets/.env after redeploy). This script does not need the repo mounted locally for the
HTTP default.
EOF
}

log_info() { echo "[INFO] $*"; }
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
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ssh-exec)
        USE_SSH_EXEC=1; shift ;;
      --local)
        USE_SSH_LOCAL=1; shift ;;
      --host)
        [[ $# -ge 2 ]] || fail "--host requires a value"
        REMOTE_HOST="$2"; shift 2 ;;
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
             python -m rag_engine.backfill "$@")

  log_info "Running: ${cmd[*]}"
  "${cmd[@]}"
}

run_http() {
  need_cmd python3
  [[ -f "$REMOTE_CLIENT" ]] || fail "Missing $REMOTE_CLIENT"
  log_info "POST ${RAG_ENGINE_BASE_URL:-}/v1/backfill"
  exec python3 "$REMOTE_CLIENT" "${PASS_ARGS[@]}"
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
