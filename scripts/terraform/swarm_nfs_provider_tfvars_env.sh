#!/usr/bin/env bash
# Optional: export path to shared Swarm NFS tfvars (swarm_nfs_*).
# swarm_pipeline.sh requires this file to exist (see homelab terraform/providers/nfs.tfvars.example).
set -euo pipefail

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_NFS_PROVIDER_TFVARS="${SWARM_NFS_PROVIDER_TFVARS:-${TFVARS_HOME_DIR}/terraform/providers/nfs.tfvars}"
export SWARM_NFS_PROVIDER_TFVARS
