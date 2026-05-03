#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
INCLUDE_MANAGERS=0
FORCE_REMOVE=1
USE_LOCAL_DOCKER=0
DOCKER_HOST_TARGET="${DOCKER_SWARM_CP:-}"

usage() {
  cat <<'EOF'
Usage: swarm_purge_down_nodes.sh [options]

Remove Docker Swarm nodes whose status is currently "Down".

By default this script:
- talks to the local Docker daemon when it is already a Swarm manager
- otherwise falls back to DOCKER_SWARM_CP or ssh://swarm-cp-0.local
- removes only worker nodes
- uses docker node rm --force

Options:
  --dry-run            Show matching nodes and removal commands without deleting.
  --include-managers   Also remove Down manager nodes.
  --no-force           Do not pass --force to docker node rm.
  --host <docker-host> Docker host to target. Plain hostnames are treated as ssh://.
  --local              Force use of the local Docker daemon.
  -h, --help           Show this help text.
EOF
}

log_info() {
  echo "[INFO] $*"
}

log_warn() {
  echo "[WARN] $*" >&2
}

fail() {
  echo "[ERR] $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

normalize_docker_host() {
  local host="$1"

  [[ -n "${host}" ]] || return 1

  if [[ "${host}" == *"://"* ]]; then
    printf '%s\n' "${host}"
    return 0
  fi

  printf 'ssh://%s\n' "${host}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --include-managers)
        INCLUDE_MANAGERS=1
        shift
        ;;
      --no-force)
        FORCE_REMOVE=0
        shift
        ;;
      --host)
        [[ $# -ge 2 ]] || fail "--host requires a value."
        DOCKER_HOST_TARGET="$2"
        shift 2
        ;;
      --local)
        USE_LOCAL_DOCKER=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

docker_cmd() {
  "${DOCKER_CMD[@]}" "$@"
}

local_swarm_manager_available() {
  local control_available

  if ! control_available="$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null || true)"; then
    return 1
  fi

  [[ "${control_available}" == "true" ]]
}

init_docker_cmd() {
  need_cmd docker

  if [[ "${USE_LOCAL_DOCKER}" == "1" ]]; then
    DOCKER_CMD=(docker)
    log_info "Using local Docker daemon."
    return 0
  fi

  if local_swarm_manager_available; then
    DOCKER_CMD=(docker)
    log_info "Using local Swarm manager."
    return 0
  fi

  local resolved_host
  resolved_host="$(normalize_docker_host "${DOCKER_HOST_TARGET:-swarm-cp-0.local}")"
  if [[ "${resolved_host}" == ssh://* ]]; then
    need_cmd ssh
  fi
  DOCKER_CMD=(docker --host "${resolved_host}")
  log_info "Using remote Docker host ${resolved_host}."
}

collect_candidates() {
  local line id hostname status availability manager_status

  mapfile -t NODE_LINES < <(docker_cmd node ls --format '{{.ID}}|{{.Hostname}}|{{.Status}}|{{.Availability}}|{{.ManagerStatus}}')

  CANDIDATE_IDS=()
  CANDIDATE_HOSTNAMES=()
  CANDIDATE_AVAILABILITY=()
  CANDIDATE_MANAGER_STATUS=()

  for line in "${NODE_LINES[@]}"; do
    IFS='|' read -r id hostname status availability manager_status <<<"${line}"

    [[ "${status}" == "Down" ]] || continue

    if [[ "${INCLUDE_MANAGERS}" != "1" && -n "${manager_status}" ]]; then
      continue
    fi

    CANDIDATE_IDS+=("${id}")
    CANDIDATE_HOSTNAMES+=("${hostname}")
    CANDIDATE_AVAILABILITY+=("${availability}")
    CANDIDATE_MANAGER_STATUS+=("${manager_status}")
  done
}

print_candidates() {
  local i manager_label

  if ((${#CANDIDATE_IDS[@]} == 0)); then
    log_info "No matching Down Swarm nodes found."
    return 0
  fi

  echo "Matching Down Swarm nodes:"
  for i in "${!CANDIDATE_IDS[@]}"; do
    manager_label="${CANDIDATE_MANAGER_STATUS[$i]}"
    if [[ -z "${manager_label}" ]]; then
      manager_label="worker"
    fi

    printf '  - %s (%s, availability=%s, role=%s)\n' \
      "${CANDIDATE_HOSTNAMES[$i]}" \
      "${CANDIDATE_IDS[$i]}" \
      "${CANDIDATE_AVAILABILITY[$i]}" \
      "${manager_label}"
  done
}

purge_candidates() {
  local i args output had_error=0

  for i in "${!CANDIDATE_IDS[@]}"; do
    args=(node rm)
    if [[ "${FORCE_REMOVE}" == "1" ]]; then
      args+=(--force)
    fi
    args+=("${CANDIDATE_IDS[$i]}")

    if [[ "${DRY_RUN}" == "1" ]]; then
      printf '[DRY-RUN] docker %s\n' "${args[*]}"
      continue
    fi

    if output="$(docker_cmd "${args[@]}" 2>&1)"; then
      log_info "Removed ${CANDIDATE_HOSTNAMES[$i]} (${CANDIDATE_IDS[$i]})."
      [[ -n "${output}" ]] && printf '        %s\n' "${output}"
    else
      had_error=1
      log_warn "Failed to remove ${CANDIDATE_HOSTNAMES[$i]} (${CANDIDATE_IDS[$i]}): ${output}"
    fi
  done

  return "${had_error}"
}

main() {
  parse_args "$@"
  init_docker_cmd
  collect_candidates
  print_candidates

  if ((${#CANDIDATE_IDS[@]} == 0)); then
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    return 0
  fi

  purge_candidates
}

main "$@"
