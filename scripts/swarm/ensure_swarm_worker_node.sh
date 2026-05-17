#!/usr/bin/env bash
# Verify a Swarm worker is reachable and labeled for placement (e.g. Prometheus on swarm-wk-3).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SSH_KEY="${SSH_KEY:-${ROOT_DIR}/.config/.ssh/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-${ROOT_DIR}/.config/.ssh/known_hosts}"
SSH_USER="${SSH_USER:-nodadyoushutup}"
NODE_ROLE="${NODE_ROLE:-swarm-wk-4}"
NODE_HOST="${NODE_HOST:-swarm-wk-4.local}"
MANAGER_HOST="${MANAGER_HOST:-swarm-cp-0.local}"
APPLY_LABEL="${APPLY_LABEL:-0}"

usage() {
  cat <<'EOF'
Usage: ensure_swarm_worker_node.sh [options]

Checks ping + SSH on the worker, then (via the Swarm manager) that the node is
Ready and has node.labels.role matching NODE_ROLE.

Options:
  --role <name>       Expected label role (default: swarm-wk-3)
  --host <hostname>   Worker SSH host (default: swarm-wk-3.local)
  --manager <host>    Swarm manager SSH host (default: swarm-cp-0.local)
  --apply-label       Run: docker node update --label-add role=<role> on match
  -h, --help          Show this help
EOF
}

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) NODE_ROLE="$2"; shift 2 ;;
    --host) NODE_HOST="$2"; shift 2 ;;
    --manager) MANAGER_HOST="$2"; shift 2 ;;
    --apply-label) APPLY_LABEL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

ssh_base() {
  local -a cmd=(ssh -o BatchMode=yes -o ConnectTimeout=10)
  [[ -f "${SSH_KEY}" ]] && cmd+=(-i "${SSH_KEY}")
  [[ -f "${KNOWN_HOSTS}" ]] && cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  printf '%s\n' "${cmd[@]}"
}

readarray -t SSH_BASE < <(ssh_base)
REMOTE_WORKER="${SSH_USER}@${NODE_HOST}"
REMOTE_MANAGER="${SSH_USER}@${MANAGER_HOST}"

log "ping ${NODE_HOST} ..."
ping -c 1 -W 2 "${NODE_HOST}" >/dev/null 2>&1 || fail "ping failed for ${NODE_HOST}"

log "ssh ${REMOTE_WORKER} (docker + swarm local state) ..."
"${SSH_BASE[@]}" "${REMOTE_WORKER}" bash -s <<'REMOTE' || fail "worker SSH failed"
set -euo pipefail
hostname -f || hostname
docker info --format 'Docker={{.ServerVersion}} SwarmLocal={{.Swarm.LocalNodeState}}' 2>/dev/null || fail "docker info failed"
REMOTE

log "manager ${REMOTE_MANAGER}: locate node for role=${NODE_ROLE} ..."
node_line="$(
  "${SSH_BASE[@]}" "${REMOTE_MANAGER}" bash -s -- "${NODE_HOST}" "${NODE_ROLE}" <<'REMOTE' || true
set -euo pipefail
host_pat="$1"
role="$2"
docker node ls --format '{{.ID}}\t{{.Hostname}}\t{{.Status}}\t{{.Availability}}' 2>/dev/null | while IFS=$'\t' read -r id hostname status avail; do
  if [[ "${hostname}" == *"${host_pat%%.local}"* ]] || [[ "${hostname}" == "${host_pat}" ]]; then
    node_role="$(docker node inspect "${id}" --format '{{index .Spec.Labels "role"}}' 2>/dev/null || true)"
    echo "${id}	${hostname}	${status}	${avail}	${node_role}"
  fi
done
REMOTE
)"

[[ -n "${node_line}" ]] || fail "no Swarm node found matching host ${NODE_HOST} (is it joined?)"

IFS=$'\t' read -r node_id node_hostname node_status node_avail node_role_label <<<"${node_line}"
log "node id=${node_id} hostname=${node_hostname} status=${node_status} availability=${node_avail}"
log "label role=${node_role_label:-<unset>}"

[[ "${node_status}" == "Ready" ]] || fail "node status is ${node_status}, expected Ready"

if [[ "${node_role_label}" != "${NODE_ROLE}" ]]; then
  if [[ "${APPLY_LABEL}" == "1" ]]; then
    log "applying label role=${NODE_ROLE} on ${node_id} ..."
    "${SSH_BASE[@]}" "${REMOTE_MANAGER}" docker node update --label-add "role=${NODE_ROLE}" "${node_id}"
    log "label applied"
  else
    fail "missing label role=${NODE_ROLE} (re-run with --apply-label)"
  fi
else
  log "label role=${NODE_ROLE} present"
fi

log "OK — ${NODE_HOST} is Ready on Swarm with role=${NODE_ROLE}"
