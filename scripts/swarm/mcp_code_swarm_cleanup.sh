#!/usr/bin/env bash
# Remove mcp-code Swarm service, task containers, and NFS bind volume.
#
# Run on a Swarm manager with Docker socket access, for example:
#   ssh swarm-cp-0.local 'bash -s' < scripts/swarm/mcp_code_swarm_cleanup.sh
#
# After the service is gone, prune dead task containers if the volume is still in use:
#   docker container prune -f
#   docker volume rm mcp-code-mnt-eapp-code
#
# Terraform: destroy terraform/swarm/mcp-code/app (or drop mcp-code.tfstate from your backend)
# before re-running this script if the stack might recreate the service.

set -eu

SERVICE=mcp-code
VOLUME=mcp-code-mnt-eapp-code

if docker service inspect "$SERVICE" >/dev/null 2>&1; then
  echo "Removing service: $SERVICE"
  docker service rm "$SERVICE"
else
  echo "Service not present: $SERVICE"
fi

echo "Waiting for task shutdown (NFS volume refs)…"
sleep 8

docker container prune -f >/dev/null || true

if docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  if docker volume rm "$VOLUME"; then
    echo "Removed volume: $VOLUME"
  else
    echo "WARN: could not remove $VOLUME (still referenced — retry after prune or check other nodes)" >&2
  fi
else
  echo "Volume not present: $VOLUME"
fi

echo "Done. Remaining mcp-* services:"
docker service ls --format '{{.Name}}' | grep -E '^mcp-' | sort || true
