#!/usr/bin/env bash
# Optional: export path to shared Swarm Docker provider tfvars (SSH host + registry auth).
# Default: terraform/providers/docker_arm64.tfvars (Swarm control plane). gha-runner-amd64 merges
# terraform/providers/docker_amd64.tfvars via SWARM_DOCKER_AMD64_PROVIDER_TFVARS; gha-runner-arm64
# merges terraform/providers/docker_arm64_pool.tfvars via SWARM_DOCKER_ARM64_POOL_TFVARS.
# DNS: terraform/providers/dns.tfvars. NFS: terraform/providers/nfs.tfvars.
# Grafana API (grafana/config only): terraform/providers/grafana.tfvars via
# scripts/terraform/swarm_grafana_provider_tfvars_env.sh (not swarm_pipeline global prefix).
# swarm_pipeline.sh merges docker_arm64, optional amd64 or docker_arm64_pool tfvars when set by those pipelines, dns, then nfs before stack tfvars.
# Source from pipelines/terraform/swarm/*/app.sh and select database stages before
# scripts/terraform/swarm_pipeline.sh. Non-Docker stacks (Cloudflare, Jenkins config, etc.)
# must NOT source this file.
set -euo pipefail

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
SWARM_DOCKER_PROVIDER_TFVARS="${SWARM_DOCKER_PROVIDER_TFVARS:-${TFVARS_HOME_DIR}/terraform/providers/docker_arm64.tfvars}"
export SWARM_DOCKER_PROVIDER_TFVARS
