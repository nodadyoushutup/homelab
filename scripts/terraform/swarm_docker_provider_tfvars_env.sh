#!/usr/bin/env bash
# Export path to shared Swarm Docker provider tfvars (tag: terraform/components/swarm/swarm).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_DOCKER_PROVIDER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/components/swarm/swarm")}"
export SWARM_DOCKER_PROVIDER_TFVARS
