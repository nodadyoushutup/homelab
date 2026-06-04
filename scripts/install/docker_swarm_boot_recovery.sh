#!/usr/bin/env bash
# Boot-time entrypoint: delegates to overlay recovery (vxlan + Swarm error + NPM edge).
set -euo pipefail
exec /usr/local/sbin/docker_swarm_overlay_recovery.sh
