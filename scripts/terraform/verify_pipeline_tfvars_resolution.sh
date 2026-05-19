#!/usr/bin/env bash
# Regression check: default TFVARS paths for all pipelines using swarm_pipeline.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/resolve_default_tfvars_file.sh"

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
  "${ROOT_DIR}/terraform/swarm/grafana/app" \
  "grafana" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/swarm/grafana/app.tfvars"

assert_tfvars_path "swarm database" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/swarm/prometheus/database" \
  "prometheus" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/swarm/prometheus/database.tfvars"

assert_tfvars_path "swarm config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/swarm/nginx_proxy_manager/config" \
  "nginx_proxy_manager" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/swarm/nginx_proxy_manager/config.tfvars"

assert_tfvars_path "cluster app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/cluster/talos/app" \
  "talos" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/cluster/talos/app.tfvars"

assert_tfvars_path "remote config" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/remote/cloudflare/config" \
  "cloudflare" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/remote/cloudflare/config.tfvars"

assert_tfvars_path "explicit override" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/swarm/qbittorrent-metrics-exporter/app" \
  "qbittorrent-metrics-exporter" \
  "${TFVARS_HOME_DIR}/terraform/swarm/qbittorrent-metrics-exporter/app.tfvars" \
  "${TFVARS_HOME_DIR}/terraform/swarm/qbittorrent-metrics-exporter/app.tfvars"

assert_tfvars_path "prometheus-pve-exporter app" \
  "${ROOT_DIR}" \
  "${ROOT_DIR}/terraform/swarm/prometheus-pve-exporter/app" \
  "prometheus-pve-exporter" \
  "" \
  "${TFVARS_HOME_DIR}/terraform/swarm/prometheus-pve-exporter/app.tfvars"

assert_tfvars_path "basename fallback" \
  "${ROOT_DIR}" \
  "/tmp/outside-repo/terraform/foo/app" \
  "foo" \
  "" \
  "${TFVARS_HOME_DIR}/foo.tfvars"

# Bash quirk guard: assignment inside case must not be reintroduced in swarm_pipeline.
assert_case_assignment_still_broken() {
  local ROOT_DIR="/mnt/eapp/code/homelab"
  local TERRAFORM_DIR="/mnt/eapp/code/homelab/terraform/swarm/grafana/app"
  local broken=""
  case "${TERRAFORM_DIR}" in
    "${ROOT_DIR}"/*) broken="${TERRAFORM_DIR#"${ROOT_DIR}/"}" ;;
  esac
  if [[ "${broken}" == "terraform/swarm/grafana/app" ]]; then
    echo "[WARN] bash case+strip quirk no longer reproduces; revisit resolve_default_tfvars_file.sh" >&2
  fi
}
assert_case_assignment_still_broken

# Every pipeline entrypoint that sources swarm_pipeline.sh.
while IFS= read -r pipeline_script; do
  pipeline_dir="$(dirname "${pipeline_script}")"
  pipeline_name="$(basename "${pipeline_script}")"
  label="${pipeline_dir#${ROOT_DIR}/}/${pipeline_name}"

  out="$(cd "${pipeline_dir}" && timeout 8 bash "./${pipeline_name}" -h 2>&1)" || true
  tfvars="$(printf '%s\n' "${out}" | sed -n 's/^  TFVARS  -> //p' | head -1)"

  if [[ -z "${tfvars}" ]]; then
  # vault stages print a custom message instead of usage TFVARS line
    if [[ "${pipeline_name}" == *.sh && "${out}" == *"expected tfvars:"* ]]; then
      continue
    fi
    echo "[FAIL] ${label}: no TFVARS line in -h output" >&2
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
done < <(grep -rl 'swarm_pipeline\.sh' "${ROOT_DIR}/pipelines/terraform" --include='*.sh' | sort)

if [[ "${failures}" -gt 0 ]]; then
  echo "[ERR] ${failures} failure(s) in ${checks} check(s)" >&2
  exit 1
fi

echo "[OK] pipeline tfvars resolution (${checks} checks)"
