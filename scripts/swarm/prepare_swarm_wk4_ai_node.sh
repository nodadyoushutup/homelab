#!/usr/bin/env bash
# Join swarm-wk-4 to the cluster and label it for MCP / RAG placement.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANAGER_HOST="${MANAGER_HOST:-192.168.1.120}"
WORKER_HOST="${WORKER_HOST:-swarm-wk-4.local}"
WORKER_IP="${WORKER_IP:-192.168.1.25}"
NODE_ROLE="${NODE_ROLE:-swarm-wk-4}"
SSH_KEY="${SSH_KEY:-${ROOT_DIR}/.config/.ssh/id_ed25519}"
KNOWN_HOSTS="${KNOWN_HOSTS:-${ROOT_DIR}/.config/.ssh/known_hosts}"
SSH_USER="${SSH_USER:-nodadyoushutup}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

ssh_mgr() {
  local -a cmd=(ssh -o BatchMode=yes -o ConnectTimeout=15)
  [[ -f "${SSH_KEY}" ]] && cmd+=(-i "${SSH_KEY}")
  [[ -f "${KNOWN_HOSTS}" ]] && cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  "${cmd[@]}" "${SSH_USER}@${MANAGER_HOST}" "$@"
}

ssh_wkr() {
  local -a cmd=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
  [[ -f "${SSH_KEY}" ]] && cmd+=(-i "${SSH_KEY}")
  [[ -f "${KNOWN_HOSTS}" ]] && cmd+=(-o "UserKnownHostsFile=${KNOWN_HOSTS}")
  "${cmd[@]}" "${SSH_USER}@${WORKER_HOST}" "$@"
}

log "manager=${MANAGER_HOST} worker=${WORKER_HOST} (${WORKER_IP}) role=${NODE_ROLE}"

token="$(ssh_mgr docker swarm join-token worker -q)" || fail "could not read worker join token from manager"
log "join token acquired"

if ! ping -c 1 -W 2 "${WORKER_IP}" >/dev/null 2>&1; then
  fail "${WORKER_IP} (${WORKER_HOST}) is not reachable — power on the VM and ensure SSH works, then re-run"
fi

ssh_wkr bash -s -- "${MANAGER_HOST}" "${token}" <<'REMOTE' || fail "worker join failed"
set -euo pipefail
manager="$1"
token="$2"
if docker info 2>/dev/null | grep -q 'Swarm: active'; then
  echo "already in swarm: $(docker info -f '{{.Swarm.NodeID}}')"
else
  docker swarm join --token "${token}" "${manager}:2377"
fi
REMOTE

node_id="$(ssh_mgr docker node ls --format '{{.ID}}\t{{.Hostname}}' | awk -v h="${WORKER_HOST%%.local}" '$2 ~ h {print $1; exit}')"
[[ -n "${node_id}" ]] || node_id="$(ssh_mgr docker node ls -q | while read -r id; do
  addr="$(ssh_mgr docker node inspect "$id" --format '{{.Status.Addr}}')"
  [[ "${addr}" == "${WORKER_IP}" ]] && echo "$id" && break
done)"
[[ -n "${node_id}" ]] || fail "joined worker not visible on manager (check hostname/IP)"

ssh_mgr docker node update --label-add "role=${NODE_ROLE}" "${node_id}"
ssh_mgr docker node inspect "${node_id}" --format 'hostname={{.Description.Hostname}} addr={{.Status.Addr}} role={{index .Spec.Labels "role"}} availability={{.Spec.Availability}}'
log "OK — ${NODE_ROLE} labeled on node ${node_id}"
