#!/usr/bin/env bash
# Optional: export path to shared Swarm Docker provider tfvars (SSH host + registry auth).
# Source from pipelines/terraform/swarm/*/app.sh and select database stages before
# scripts/terraform/swarm_pipeline.sh. Non-Docker stacks (Cloudflare, Jenkins config, etc.)
# must NOT source this file.
set -euo pipefail

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}"
SWARM_DOCKER_PROVIDER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-${TFVARS_HOME_DIR}/providers/docker.tfvars}"
export SWARM_DOCKER_PROVIDER_TFVARS
