#!/usr/bin/env bash
# Shared default paths for bespoke Swarm Terraform pipelines (chromadb, dozzle, …).
# Sets: DEFAULT_DOCKER_TFVARS, DEFAULT_DNS_TFVARS, DEFAULT_SLICE_TFVARS, DEFAULT_BACKEND
# Requires: CONFIG_DIR, TERRAFORM_DIR; optional ROOT_DIR for slice id derivation.

_bespoke_swarm_defaults_loaded=0

homelab_bespoke_swarm_set_defaults() {
  local config_dir="$1"
  local terraform_dir="$2"
  local root_dir="${3:-}"

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=resolve_config_by_id.sh
  source "${script_dir}/resolve_config_by_id.sh"

  DEFAULT_DOCKER_TFVARS="$(homelab_resolve_config_path "${config_dir}" "terraform/providers/docker_arm64")"
  DEFAULT_DNS_TFVARS="$(homelab_resolve_config_path "${config_dir}" "terraform/providers/dns")"
  DEFAULT_BACKEND="$(homelab_resolve_config_path "${config_dir}" "minio.backend")"
  DEFAULT_SLICE_TFVARS=""

  local app_id=""
  if [[ -n "${root_dir}" ]]; then
    app_id="$(homelab_config_id_from_terraform_dir "${root_dir}" "${terraform_dir}" 2>/dev/null || true)"
  fi
  if [[ -n "${app_id}" ]]; then
    DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${config_dir}" "${app_id}")"
  fi
}
