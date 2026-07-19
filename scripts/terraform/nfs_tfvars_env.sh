#!/usr/bin/env bash
# Export path to the shared NFS catalog tfvars (config-id: terraform/nfs).
# Managed by the homelab-config web app; consumer slices pass it as a shared
# -var-file alongside their own slice tfvars (each slice selects a share by name).
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
NFS_TFVARS="${NFS_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/nfs")}"
export NFS_TFVARS
