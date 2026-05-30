#!/usr/bin/env bash
# Regression check: default TFVARS paths for all pipelines using swarm_pipeline.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/resolve_default_tfvars_file.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/resolve_config_by_id.sh"

TFVARS_HOME_DIR="${ROOT_DIR}/.config"
failures=0
checks=0

assert_tfvars_path() {
  local label="$1"
  local root_dir="$2"
  local terraform_dir="$3"
  local service_name="$4"
  local existing="${5:-}"
  local expected="$6"

  checks=$((checks + 1))
  local got
  got="$(homelab_resolve_default_tfvars_file \
    "${root_dir}" \
    "${terraform_dir}" \
    "${TFVARS_HOME_DIR}" \
    "${service_name}" \
    "${existing}")"

  if [[ "${got}" != "${expected}" ]]; then
    echo "[FAIL] ${label}" >&2
    echo "       expected: ${expected}" >&2
    echo "       got:      ${got}" >&2
    failures=$((failures + 1))
    return 1
  fi
  return 0
}

# Known slice layouts (representative + edge cases).
assert_tfvars_path "swarm app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/grafana/app" \
  "grafana" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/grafana/app.tfvars"

assert_tfvars_path "swarm victoriametrics app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/victoriametrics/app" \
  "victoriametrics" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/victoriametrics/app.tfvars"

assert_tfvars_path "swarm nginx_proxy_manager database" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/database" \
  "nginx_proxy_manager" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/nginx_proxy_manager/database.tfvars"

assert_tfvars_path "swarm nginx_proxy_manager app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/app" \
  "nginx_proxy_manager" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/nginx_proxy_manager/app.tfvars"

assert_tfvars_path "swarm nginx_proxy_manager config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/nginx_proxy_manager/config" \
  "nginx_proxy_manager" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/nginx_proxy_manager/config.tfvars"

assert_tfvars_path "cluster proxmox app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/cluster/proxmox/app" \
  "proxmox" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/cluster/proxmox/app.tfvars"

assert_tfvars_path "cluster argocd config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/cluster/argocd/config" \
  "argocd" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/cluster/argocd/config.tfvars"

assert_tfvars_path "cluster talos app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/cluster/talos/app" \
  "talos" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/cluster/talos/app.tfvars"

assert_tfvars_path "network fortigate config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/network/fortigate/config" \
  "fortigate" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/network/fortigate/config.tfvars"

assert_tfvars_path "remote cloudflare config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/remote/cloudflare/config" \
  "cloudflare" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/remote/cloudflare/config.tfvars"

assert_tfvars_path "explicit override" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/qbittorrent-exporter/app" \
  "qbittorrent-exporter" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/qbittorrent-exporter/app.tfvars" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/qbittorrent-exporter/app.tfvars"

assert_tfvars_path "prometheus-pve-exporter app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/components/swarm/prometheus-pve-exporter/app" \
  "prometheus-pve-exporter" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/components/swarm/prometheus-pve-exporter/app.tfvars"

assert_tfvars_path "basename fallback" \
  "${ROOT_DIR}" \
  "/tmp/outside-repo/terraform/foo/app" \
  "foo" \
  "" \
  "${TFVARS_HOME_DIR}/foo.tfvars"

# Bash quirk guard: assignment inside case must not be reintroduced in swarm_pipeline.
assert_case_assignment_still_broken() {
  local ROOT_DIR="/mnt/eapp/code/homelab"
  local TERRAFORM_DIR="/mnt/eapp/code/homelab/terraform/components/swarm/grafana/app"
  local broken=""
  case "${TERRAFORM_DIR}" in
    "${ROOT_DIR}"/*) broken="${TERRAFORM_DIR#"${ROOT_DIR}/"}" ;;
  esac
  if [[ "${broken}" == "terraform/components/swarm/grafana/app" ]]; then
    echo "[WARN] bash case+strip quirk no longer reproduces; revisit resolve_default_tfvars_file.sh" >&2
  fi
}
assert_case_assignment_still_broken

# Tag index must resolve a representative slice when stamped under .config.
checks=$((checks + 1))
if ! tagged="$(homelab_find_config_by_id "${TFVARS_HOME_DIR}" "terraform/components/swarm/grafana/app" 2>/dev/null)"; then
  echo "[FAIL] homelab-config tag missing for terraform/components/swarm/grafana/app (run scripts/config/stamp_homelab_config_ids.py)" >&2
  failures=$((failures + 1))
elif [[ ! -f "${tagged}" ]]; then
  echo "[FAIL] tagged grafana app tfvars not found: ${tagged}" >&2
  failures=$((failures + 1))
fi

# Pipeline entrypoints that source swarm_pipeline.sh (not comment-only mentions).
while IFS= read -r pipeline_script; do
  pipeline_dir="$(dirname "${pipeline_script}")"
  pipeline_name="$(basename "${pipeline_script}")"
  label="${pipeline_dir#${ROOT_DIR}/}/${pipeline_name}"

  out="$(cd "${pipeline_dir}" && timeout 20 bash "./${pipeline_name}" -h 2>&1)" || true
  tfvars="$(printf '%s\n' "${out}" | sed -n 's/^  TFVARS  *-> *//p' | head -1)"

  if [[ -z "${tfvars}" ]]; then
    # vault app rejects args; bespoke pipelines print --tfvars defaults instead.
    if [[ "${out}" == *"expected tfvars:"* ]] \
      || [[ "${out}" == *"--tfvars <path>"* ]] \
      || [[ "${out}" == *"TFVARS  ->"* ]]; then
      continue
    fi
    echo "[FAIL] ${label}: no TFVARS/--tfvars line in -h output" >&2
    printf '%s\n' "${out}" | head -5 >&2
    failures=$((failures + 1))
    continue
  fi

  checks=$((checks + 1))
  if [[ "${tfvars}" == *"${ROOT_DIR}/.config//${ROOT_DIR}"* ]]; then
    echo "[FAIL] ${label}: doubled absolute path: ${tfvars}" >&2
    failures=$((failures + 1))
  elif [[ "${tfvars}" == *"//"* && "${tfvars}" != *"://"* ]]; then
    echo "[FAIL] ${label}: suspicious double slash: ${tfvars}" >&2
    failures=$((failures + 1))
  fi
done < <(grep -rlE 'source .*(swarm|cluster|remote|network)_pipeline\.sh' "${ROOT_DIR}/terraform/components/swarm" "${ROOT_DIR}/terraform/components/cluster" "${ROOT_DIR}/terraform/components/remote" "${ROOT_DIR}/terraform/components/network" "${ROOT_DIR}/terraform/components/runners" --include='*.sh' 2>/dev/null | sort)

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERR] ${failures} failure(s) in ${checks} check(s)" >&2
  exit 1
fi

echo "[OK] pipeline tfvars resolution (${checks} checks)"
