#!/usr/bin/env bash
# Remove retired Swarm MCPs: standalone filesystem/git/ast-grep stacks and mcp-code.
#
# Safe to re-run: services/volumes that are already gone are skipped or no-op.
#
# Swarm manager SSH (example):
#   ssh swarm-cp-0.local 'bash -s' < scripts/swarm/legacy_mcp_upstream_swarm_cleanup.sh
#
# mcp-code only: scripts/swarm/mcp_code_swarm_cleanup.sh

set -eu

SERVICES=(
  mcp-ast-grep
  mcp-filesystem
  mcp-filesystem-homelab
  mcp-git
  mcp-git-homelab
  mcp-code
)

VOLUMES=(
  mcp-ast-grep-mnt-eapp-code
  mcp-filesystem-mnt-eapp-code
  mcp-git-mnt-eapp-code
  mcp-code-mnt-eapp-code
)

for s in "${SERVICES[@]}"; do
  if docker service inspect "$s" >/dev/null 2>&1; then
    echo "Removing service: $s"
    docker service rm "$s"
  else
    echo "Service not present: $s"
  fi
done

echo "Waiting for task shutdown (NFS volume refs)…"
sleep 8

docker container prune -f >/dev/null || true

for v in "${VOLUMES[@]}"; do
  if docker volume inspect "$v" >/dev/null 2>&1; then
    if docker volume rm "$v"; then
      echo "Removed volume: $v"
    else
      echo "WARN: could not remove $v (still referenced — retry after prune or check other nodes)" >&2
    fi
  else
    echo "Volume not present: $v"
  fi
done

echo "Done. Remaining mcp-* services:"
docker service ls --format '{{.Name}}' | grep -E '^mcp-' | sort || true
