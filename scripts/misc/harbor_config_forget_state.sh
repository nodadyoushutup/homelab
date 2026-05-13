#!/usr/bin/env bash
# Drop Terraform state for Harbor *config* API objects without calling Harbor delete.
# Use when you emptied projects/robots in tfvars and do not care about Harbor data:
# Terraform would otherwise try to destroy non-empty projects and fail.
#
# Run from repo root after `terraform init` for harbor/config (same backend/tfvars
# as pipelines/terraform/swarm/harbor/config.sh). Example:
#
#   CONFIG_DIR=/mnt/eapp/config ./scripts/misc/harbor_config_forget_state.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${CONFIG_DIR:-/mnt/eapp/config}"
BACKEND="${BACKEND:-${CONFIG_DIR}/minio.backend.hcl}"
TFVARS="${TFVARS:-${CONFIG_DIR}/harbor/config.tfvars}"
TF_DIR="${ROOT_DIR}/terraform/swarm/harbor/config"

if [[ ! -f "${BACKEND}" || ! -f "${TFVARS}" ]]; then
  echo "[ERR] Need BACKEND=${BACKEND} and TFVARS=${TFVARS}" >&2
  exit 1
fi

cd "${TF_DIR}"
terraform init -input=false -backend-config="${BACKEND}" >/dev/null

addrs=()
while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  case "${line}" in
    harbor_*|null_resource.delete_default_library_project*)
      addrs+=("${line}")
      ;;
  esac
done < <(terraform state list 2>/dev/null || true)

if [[ "${#addrs[@]}" -eq 0 ]]; then
  echo "[ok] No harbor_* or library null_resource in state."
  exit 0
fi

echo "[info] Removing from Terraform state (Harbor is untouched):"
printf '  %s\n' "${addrs[@]}"
terraform state rm "${addrs[@]}"
