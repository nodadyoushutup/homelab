#!/usr/bin/env bash
# Export path to the shared Docker provider catalog tfvars
# (config-id: terraform/providers/docker). Managed by the homelab-config web app;
# every Swarm slice pipeline passes it as an extra -var-file alongside its own
# slice tfvars (each slice selects a machine via docker_machine and reuses the
# shared registry_auths).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
DOCKER_TFVARS="${DOCKER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/providers/docker")}"
export DOCKER_TFVARS
