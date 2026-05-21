#!/usr/bin/env bash
# Resolve DEFAULT_TFVARS_FILE from homelab-config tag or repo Terraform layout.
#
# Tag (first line): # homelab-config: terraform/swarm/grafana/app
# Canonical fallback: <CONFIG_DIR>/terraform/swarm/grafana/app.tfvars

_homelab_resolve_default_tfvars_loaded=0
if [[ "${_homelab_resolve_default_tfvars_loaded}" != "1" ]]; then
  _homelab_resolve_default_tfvars_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=resolve_config_by_id.sh
  source "${_homelab_resolve_default_tfvars_dir}/resolve_config_by_id.sh"
  _homelab_resolve_default_tfvars_loaded=1
fi

homelab_resolve_default_tfvars_file() {
  local root_dir="${1:-}"
  local terraform_dir="${2:-}"
  local tfvars_home_dir="${3:-}"
  local default_basename="${4:-}"
  local existing="${5:-}"

  if [[ -n "${existing}" ]]; then
    printf '%s\n' "${existing}"
    return 0
  fi

  local config_id=""
  if config_id="$(homelab_config_id_from_terraform_dir "${root_dir}" "${terraform_dir}" 2>/dev/null)"; then
    homelab_resolve_config_path "${tfvars_home_dir}" "${config_id}"
    return 0
  fi

  if [[ -n "${default_basename}" ]]; then
    homelab_resolve_config_path "${tfvars_home_dir}" "${default_basename}"
    return 0
  fi

  return 1
}
