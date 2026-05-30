#!/usr/bin/env bash
# Export path to shared Swarm NFS tfvars (tag: terraform/components/swarm/nfs).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_NFS_PROVIDER_TFVARS="${SWARM_NFS_PROVIDER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/components/swarm/nfs")}"
export SWARM_NFS_PROVIDER_TFVARS
