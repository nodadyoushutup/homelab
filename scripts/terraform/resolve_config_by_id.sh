#!/usr/bin/env bash
# Resolve paths under CONFIG_DIR / TFVARS_HOME_DIR by first-line homelab-config tag.
#
# Tag format (first line of file):
#   # homelab-config: <config-id>
#
# <config-id> mirrors repo layout, relative to CONFIG_DIR (no leading slash):
#   terraform/swarm/grafana/app
#   terraform/components/swarm/dns
#   kubernetes/langgraph/app
#   minio.backend
#   docker/langgraph

HOMELAB_CONFIG_TAG_PREFIX='# homelab-config:'
declare -gA HOMELAB_CONFIG_INDEX=()
HOMELAB_CONFIG_INDEX_DIR=""

homelab_config_index_build() {
  local config_dir="$1"

  if [[ "${HOMELAB_CONFIG_INDEX_DIR}" == "${config_dir}" && ${#HOMELAB_CONFIG_INDEX[@]} -gt 0 ]]; then
    return 0
  fi

  HOMELAB_CONFIG_INDEX=()
  HOMELAB_CONFIG_INDEX_DIR="${config_dir}"

  if [[ ! -d "${config_dir}" ]]; then
    return 0
  fi

  local f first_line config_id
  while IFS= read -r -d '' f; do
    [[ -f "${f}" ]] || continue
    IFS= read -r first_line <"${f}" || continue
    first_line="${first_line//$'\r'/}"
    if [[ "${first_line}" != "${HOMELAB_CONFIG_TAG_PREFIX}"* ]]; then
      continue
    fi
    config_id="${first_line#${HOMELAB_CONFIG_TAG_PREFIX} }"
    config_id="${config_id#"${config_id%%[![:space:]]*}"}"
    if [[ -z "${config_id}" ]]; then
      continue
    fi
    if [[ -n "${HOMELAB_CONFIG_INDEX[${config_id}]+x}" ]]; then
      echo "[ERR] Duplicate homelab-config id '${config_id}':" >&2
      echo "       ${HOMELAB_CONFIG_INDEX[${config_id}]}" >&2
      echo "       ${f}" >&2
      return 1
    fi
    HOMELAB_CONFIG_INDEX["${config_id}"]="$(realpath "${f}")"
  done < <(
    find "${config_dir}" -type f \( \
      -name '*.tfvars' -o \
      -name '*.auto.tfvars' -o \
      -name '*.hcl' -o \
      -name '*.env' \
    \) ! -name '*.example' -print0 2>/dev/null
  )
}

homelab_config_tag_line() {
  local config_id="$1"
  printf '%s %s\n' "${HOMELAB_CONFIG_TAG_PREFIX}" "${config_id}"
}

homelab_config_id_from_terraform_dir() {
  local root_dir="$1"
  local terraform_dir="$2"

  if [[ -z "${terraform_dir}" || -z "${root_dir}" ]]; then
    return 1
  fi

  local root_prefix="${root_dir}/"
  if [[ "${terraform_dir}" != "${root_prefix}"* ]]; then
    return 1
  fi

  printf '%s\n' "${terraform_dir#"${root_prefix}"}"
}

homelab_config_canonical_path() {
  local config_dir="$1"
  local config_id="$2"

  case "${config_id}" in
    minio.backend)
      printf '%s/minio.backend.hcl\n' "${config_dir}"
      ;;
    docker/*)
      printf '%s/%s.env\n' "${config_dir}" "${config_id}"
      ;;
    *)
      printf '%s/%s.tfvars\n' "${config_dir}" "${config_id}"
      ;;
  esac
}

homelab_find_config_by_id() {
  local config_dir="$1"
  local config_id="$2"

  if ! homelab_config_index_build "${config_dir}"; then
    return 1
  fi

  if [[ -n "${HOMELAB_CONFIG_INDEX[${config_id}]+x}" ]]; then
    printf '%s\n' "${HOMELAB_CONFIG_INDEX[${config_id}]}"
    return 0
  fi

  return 1
}

# Print resolved path: tagged file if present, else canonical layout path.
homelab_resolve_config_path() {
  local config_dir="$1"
  local config_id="$2"
  local found=""

  if found="$(homelab_find_config_by_id "${config_dir}" "${config_id}" 2>/dev/null)"; then
    printf '%s\n' "${found}"
    return 0
  fi

  homelab_config_canonical_path "${config_dir}" "${config_id}"
}
