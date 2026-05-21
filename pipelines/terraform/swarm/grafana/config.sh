#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="grafana"
STAGE_NAME="Grafana config"
# No NFS mounts; skip nfs.tfvars so the stack need not declare swarm_nfs_* variables.
SWARM_SKIP_NFS_PROVIDER_TFVARS=1
export SWARM_SKIP_NFS_PROVIDER_TFVARS
# No Swarm task dns_config; skip dns.tfvars so the stack need not declare dns_nameservers.
SWARM_SKIP_DNS_PROVIDER_TFVARS=1
export SWARM_SKIP_DNS_PROVIDER_TFVARS
ENTRYPOINT_RELATIVE="pipelines/terraform/swarm/grafana/config.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/swarm/grafana/config"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()

PIPELINE_ARGS=("$@")

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/swarm_grafana_provider_tfvars_env.sh"
source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
