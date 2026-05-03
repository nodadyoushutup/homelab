#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/terraform/jenkins_stage_mount_check.sh [mount-path]

Fails when the shared Jenkins Terraform configuration mount is missing.
USAGE
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

mount_path="${1:-/mnt/eapp/config}"

if [[ ! -d "${mount_path}" ]]; then
  echo "[ERR] Shared Terraform config directory is missing: ${mount_path}" >&2
  echo "[ERR] Ensure the Jenkins agent bind-mounts the host path at ${mount_path}." >&2
  exit 1
fi

echo "[INFO] Shared Terraform config directory is present: ${mount_path}"
