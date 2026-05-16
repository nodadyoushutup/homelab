#!/usr/bin/env bash
# Safe cutover: homelab-addons ApplicationSet from Terraform to Git (argocd-management).
#
# Prerequisites:
#   - kubernetes/argocd-management/homelab-addons-appset.yaml is merged and synced
#   - argocd-management Application is Healthy (Git spec matches live ApplicationSet)
#
# This script removes the ApplicationSet from Terraform state WITHOUT destroying
# the cluster object, then applies Terraform (root Application only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform/cluster/argocd/config"

# Stale CONFIG_DIR=/mnt/eapp/config breaks minio.backend.hcl lookup; .config/.env should leave CONFIG_DIR empty.
unset CONFIG_DIR TFVARS_HOME_DIR PIPELINE_ROOT_ENV_LOADED
source "${ROOT_DIR}/scripts/terraform/load_root_env.sh"

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERR] Missing required command: ${cmd}" >&2
    exit 1
  fi
}

require_command terraform
require_command kubectl

export KUBECONFIG="${KUBECONFIG:-}"

echo "[STEP] Verify homelab-addons ApplicationSet exists in cluster"
if ! kubectl -n argocd get applicationset homelab-addons >/dev/null 2>&1; then
  echo "[ERR] ApplicationSet argocd/homelab-addons not found. Sync argocd-management first." >&2
  exit 1
fi

echo "[STEP] Verify platform Applications are present"
platform_apps=(
  metallb
  ingress-nginx
  democratic-csi-iscsi
  democratic-csi-nfs
  external-secrets
  node-exporter-k8s
  thelounge
  picsur
)
for app in "${platform_apps[@]}"; do
  if ! kubectl -n argocd get application "${app}" >/dev/null 2>&1; then
    echo "[WARN] Application argocd/${app} not found (may appear after argocd-management sync)"
  fi
done

cd "${TF_DIR}"

if terraform state list 2>/dev/null | grep -q 'argocd_application_set.homelab_addons'; then
  echo "[STEP] Removing homelab-addons from Terraform state (no destroy)"
  terraform state rm argocd_application_set.homelab_addons
else
  echo "[INFO] argocd_application_set.homelab_addons not in state (already removed or fresh backend)"
fi

if ! terraform state list 2>/dev/null | grep -q 'argocd_application.argocd_management'; then
  echo "[STEP] Importing existing argocd-management Application into state"
  terraform import \
    -var-file="${CONFIG_DIR}/terraform/cluster/argocd/config.tfvars" \
    argocd_application.argocd_management \
    argocd-management:argocd
fi

echo "[STEP] Terraform plan (expect no destroys for homelab-addons)"
terraform plan -detailed-exitcode || {
  ec=$?
  if [[ "${ec}" -eq 2 ]]; then
    echo "[WARN] Plan has changes; review before apply"
  else
    exit "${ec}"
  fi
}

echo ""
echo "[OK] State cutover complete. Run 'terraform apply' in ${TF_DIR} when plan looks safe."
echo "     Then refresh argocd-management in the Argo CD UI if needed."
