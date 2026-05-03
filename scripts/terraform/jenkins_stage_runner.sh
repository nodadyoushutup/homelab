#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/terraform/jenkins_stage_runner.sh <stage-script> [extra-args...]

Runs a Terraform stage script from Jenkins while tolerating unset optional build
parameters for TFVARS and backend overrides.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

stage_script="$1"
shift

if [[ ! -f "${stage_script}" ]]; then
  echo "[ERR] Terraform stage script not found: ${stage_script}" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shared_config_dir="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/config}}"

if [[ -z "${TFVARS_FILE:-}" || -z "${BACKEND_FILE:-}" ]]; then
  "${script_dir}/jenkins_stage_mount_check.sh" "${shared_config_dir}"
fi

args=("$@")

if [[ -n "${TFVARS_FILE:-}" ]]; then
  args+=(--tfvars "${TFVARS_FILE}")
fi

if [[ -n "${BACKEND_FILE:-}" ]]; then
  args+=(--backend "${BACKEND_FILE}")
fi

exec bash "${stage_script}" "${args[@]}"
