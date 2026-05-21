#!/usr/bin/env bash
# Optional Grafana API credentials for terraform/swarm/grafana/config only.
# Tag: terraform/providers/grafana
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=resolve_config_by_id.sh
source "${_script_dir}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_GRAFANA_PROVIDER_TFVARS="${SWARM_GRAFANA_PROVIDER_TFVARS:-$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/providers/grafana")}"
export SWARM_GRAFANA_PROVIDER_TFVARS

if [[ -f "${SWARM_GRAFANA_PROVIDER_TFVARS}" ]]; then
  PLAN_ARGS_EXTRA+=(-var-file "${SWARM_GRAFANA_PROVIDER_TFVARS}")
  APPLY_ARGS_EXTRA+=(-var-file "${SWARM_GRAFANA_PROVIDER_TFVARS}")
  export PLAN_ARGS_EXTRA APPLY_ARGS_EXTRA
fi
