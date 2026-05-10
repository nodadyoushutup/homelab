#!/usr/bin/env bash
# Run `python -m rag_engine.backfill` inside the deployed rag-engine container.
#
# Defaults target the Swarm rag-engine on swarm-cp-0 (SSH to 192.168.1.120) and
# pass any unrecognized flags straight through to the backfill module so you can
# use --dry-run / --max-files / --prune-orphans / --force / --yes / etc.
#
# Path prefixes the backfill walks come from RAG_ALLOWED_PATH_PREFIXES on the
# rag-engine container. To change them:
#   * Local source of truth: <repo>/.secrets/.env (RAG_ALLOWED_PATH_PREFIXES=...)
#   * Code default fallback: applications/rag-engine/src/rag_engine/pipeline.py
#     (`_allowed_prefixes()` -> "docs/,addons/cfs_addons/,applications/,AGENTS.md")
#   * Excluded directory names: RAG_EXCLUDE_PATH_SEGMENTS
#     (defaults in applications/rag-engine/src/rag_engine/path_rules.py)
#   * Excluded file suffixes:   RAG_EXCLUDE_FILE_SUFFIXES (same file)
#   * Max file size in bytes:   RAG_BACKFILL_MAX_FILE_BYTES (default 5 MiB)
# After editing .secrets/.env you must redeploy / restart the rag-engine service
# so the new env is picked up before re-running this script.

set -euo pipefail

DEFAULT_HOST="nodadyoushutup@192.168.1.120"
DEFAULT_SSH_KEY="/mnt/eapp/config/.ssh/id_ed25519"
DEFAULT_KNOWN_HOSTS="/mnt/eapp/config/.ssh/known_hosts"
DEFAULT_CONTAINER_FILTER="name=rag-engine"

REMOTE_HOST="${RAG_BACKFILL_HOST:-${DEFAULT_HOST}}"
SSH_KEY="${RAG_BACKFILL_SSH_KEY:-${DEFAULT_SSH_KEY}}"
KNOWN_HOSTS="${RAG_BACKFILL_KNOWN_HOSTS:-${DEFAULT_KNOWN_HOSTS}}"
CONTAINER_FILTER="${RAG_BACKFILL_CONTAINER_FILTER:-${DEFAULT_CONTAINER_FILTER}}"
USE_LOCAL=0
PASS_ARGS=()

usage() {
  cat <<'EOF'
Usage: scripts/misc/rag_backfill.sh [options] [-- <backfill args>]

Runs `python -m rag_engine.backfill` inside the rag-engine container. Any flags
not consumed below (or anything after a literal `--`) are forwarded verbatim to
the backfill CLI, so common invocations are:

  scripts/misc/rag_backfill.sh --dry-run
  scripts/misc/rag_backfill.sh --yes --prune-orphans
  scripts/misc/rag_backfill.sh --yes --prune-orphans-only --prune-dry-run
  scripts/misc/rag_backfill.sh --yes --force --max-files 50

Where to edit which directories the backfill walks
--------------------------------------------------
* Allowed prefixes (positive list) come from RAG_ALLOWED_PATH_PREFIXES on the
  rag-engine container. Set it in <repo>/.secrets/.env, e.g.:
      RAG_ALLOWED_PATH_PREFIXES=docs/,applications/,AGENTS.md
  Default when unset (see applications/rag-engine/src/rag_engine/pipeline.py
  `_allowed_prefixes()`):
      docs/,addons/cfs_addons/,applications/,AGENTS.md
* Excluded directory segments and file suffixes are defined in
  applications/rag-engine/src/rag_engine/path_rules.py and overridable via
  RAG_EXCLUDE_PATH_SEGMENTS / RAG_EXCLUDE_FILE_SUFFIXES.
* Max file size: RAG_BACKFILL_MAX_FILE_BYTES (default 5242880).
After changing .secrets/.env, redeploy the Swarm rag-engine service (or restart
the local Compose container) so the new env is loaded before backfilling.

Targeting options
-----------------
  --local                    Use the local Docker daemon (Compose) instead of
                             SSHing to the Swarm host.
  --host <user@host>         Override SSH target (default: ${RAG_BACKFILL_HOST:-nodadyoushutup@192.168.1.120}).
  --ssh-key <path>           SSH private key (default: $DEFAULT_SSH_KEY).
  --known-hosts <path>       SSH known_hosts file (default: $DEFAULT_KNOWN_HOSTS).
  --container-filter <expr>  `docker ps --filter` expression that picks the
                             rag-engine container (default: name=rag-engine).
  -h, --help                 Show this help and exit.
EOF
}

log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
fail()     { echo "[ERR] $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local)
        USE_LOCAL=1; shift ;;
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
  SUDO_PREFIX=()
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
  SUDO_PREFIX=(sudo)
}

resolve_container_id() {
  local id
  if [[ "$USE_LOCAL" == "1" ]]; then
    id="$(docker ps --filter "$CONTAINER_FILTER" --format '{{.ID}}' | head -n1 || true)"
  else
    id="$("${SSH_CMD[@]}" "sudo docker ps --filter '$CONTAINER_FILTER' --format '{{.ID}}' | head -n1" || true)"
    id="${id//$'\r'/}"
    id="${id//[[:space:]]/}"
  fi
  [[ -n "$id" ]] || fail "No running container matched filter '$CONTAINER_FILTER' on target."
  printf '%s\n' "$id"
}

run_backfill() {
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

main() {
  parse_args "$@"

  if [[ "$USE_LOCAL" == "1" ]]; then
    build_local_docker_cmd
    log_info "Target: local Docker daemon, container filter '$CONTAINER_FILTER'"
  else
    build_remote_docker_cmd
    log_info "Target: ssh $REMOTE_HOST, container filter '$CONTAINER_FILTER'"
  fi

  local container_id
  container_id="$(resolve_container_id)"
  log_info "rag-engine container id: $container_id"

  run_backfill "$container_id" "${PASS_ARGS[@]}"
}

main "$@"
