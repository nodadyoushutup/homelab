#!/usr/bin/env bash
# Optional Grafana API credentials for terraform/swarm/grafana/config only.
# Source from pipelines/terraform/swarm/grafana/config.sh before swarm_pipeline.sh.
# Do NOT add to the global swarm_pipeline shared prefix: grafana.tfvars sets
# provider_config.grafana and would collide with other stacks' provider_config
# (e.g. nginx_proxy_manager) when var-files are merged by last-wins semantics.
set -euo pipefail

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_GRAFANA_PROVIDER_TFVARS="${SWARM_GRAFANA_PROVIDER_TFVARS:-${TFVARS_HOME_DIR}/terraform/providers/grafana.tfvars}"
export SWARM_GRAFANA_PROVIDER_TFVARS

if [[ -f "${SWARM_GRAFANA_PROVIDER_TFVARS}" ]]; then
  PLAN_ARGS_EXTRA+=(-var-file "${SWARM_GRAFANA_PROVIDER_TFVARS}")
  APPLY_ARGS_EXTRA+=(-var-file "${SWARM_GRAFANA_PROVIDER_TFVARS}")
  export PLAN_ARGS_EXTRA APPLY_ARGS_EXTRA
fi
