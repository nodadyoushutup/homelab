#!/usr/bin/env bash
# Resolve DEFAULT_TFVARS_FILE from repo Terraform layout (shared by swarm_pipeline.sh).
#
# Layout: <CONFIG_DIR>/terraform/.../<slice>.tfvars mirrors
#         <repo>/terraform/.../<slice>/ (slice = basename of TERRAFORM_DIR).
#
# Bash quirk: do not assign `${path#"${root}/"}` inside a `case` arm when `root`
# also appears in the case pattern — use a separate prefix variable (see tests).

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

  if [[ -n "${terraform_dir}" && -n "${root_dir}" ]]; then
    local root_prefix="${root_dir}/"
    if [[ "${terraform_dir}" == "${root_prefix}"* ]]; then
      local rel="${terraform_dir#"${root_prefix}"}"
      local slice parent_rel
      slice="$(basename "${terraform_dir}")"
      parent_rel="$(dirname "${rel}")"
      printf '%s\n' "${tfvars_home_dir}/${parent_rel}/${slice}.tfvars"
      return 0
    fi
  fi

  if [[ -n "${default_basename}" ]]; then
    printf '%s\n' "${tfvars_home_dir}/${default_basename}.tfvars"
    return 0
  fi

  return 1
}
