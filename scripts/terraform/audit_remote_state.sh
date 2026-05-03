#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_root_env.sh"

BACKEND_FILE="${BACKEND_FILE:-${TFVARS_HOME_DIR:-${CONFIG_DIR:-/mnt/eapp/config}}/minio.backend.hcl}"
ONLY_PATTERN=""

resolve_stage_tfvars() {
  local stage_dir="$1"
  local rel_service
  local service_dir
  local stage_name
  local hyphen_service_dir
  local candidate
  local candidates=()

  rel_service="${stage_dir#${ROOT_DIR}/terraform/swarm/}"
  service_dir="${rel_service%/*}"
  stage_name="${rel_service##*/}"
  hyphen_service_dir="${service_dir//_/-}"

  candidates+=("${TFVARS_HOME_DIR}/${service_dir}/${stage_name}.tfvars")
  if [[ "${hyphen_service_dir}" != "${service_dir}" ]]; then
    candidates+=("${TFVARS_HOME_DIR}/${hyphen_service_dir}/${stage_name}.tfvars")
  fi
  candidates+=("${TFVARS_HOME_DIR}/${service_dir}.tfvars")
  if [[ "${hyphen_service_dir}" != "${service_dir}" ]]; then
    candidates+=("${TFVARS_HOME_DIR}/${hyphen_service_dir}.tfvars")
  fi

  case "${service_dir}/${stage_name}" in
    prometheus/database)
      candidates+=("${TFVARS_HOME_DIR}/victoriametrics/app.tfvars")
      ;;
  esac

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  done

  return 1
}

collection_has_instances() {
  local stage_dir="$1"
  local tf_data_dir="$2"
  local tfvars_file="$3"
  local collection_expr="$4"
  local rendered

  rendered="$(
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${stage_dir}" console -var-file "${tfvars_file}" <<EOF
try(length(${collection_expr}) > 0, (${collection_expr}) > 0)
EOF
  )"

  python3 -c 'import json, sys
value = sys.stdin.read().strip()
if not value:
    raise SystemExit(1)
print("1" if json.loads(value) else "0")' <<<"${rendered}"
}

usage() {
  cat <<USAGE
Usage: scripts/terraform/audit_remote_state.sh [--backend <path>] [--only <regex>]

Audits Terraform stage directories against their configured remote state by
comparing defined resource addresses to the current remote state list.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      [[ $# -ge 2 ]] || { echo "[ERR] --backend requires a value" >&2; exit 2; }
      BACKEND_FILE="$2"
      shift 2
      ;;
    --only)
      [[ $# -ge 2 ]] || { echo "[ERR] --only requires a value" >&2; exit 2; }
      ONLY_PATTERN="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERR] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "${BACKEND_FILE}" ]]; then
  echo "[ERR] Backend config not found: ${BACKEND_FILE}" >&2
  exit 1
fi

mapfile -t stage_dirs < <(find "${ROOT_DIR}/terraform" -mindepth 4 -maxdepth 4 -type f -name provider.tf -printf '%h\n' | sort)

if [[ ${#stage_dirs[@]} -eq 0 ]]; then
  echo "[ERR] No Terraform stage directories found." >&2
  exit 1
fi

printf '%-45s %-28s %8s %8s %8s %8s %s\n' "STAGE" "BACKEND_KEY" "DEFINED" "STATE" "MISS" "EXTRA" "STATUS"

for stage_dir in "${stage_dirs[@]}"; do
  rel_stage="${stage_dir#${ROOT_DIR}/}"

  if [[ -n "${ONLY_PATTERN}" ]] && ! [[ "${rel_stage}" =~ ${ONLY_PATTERN} ]]; then
    continue
  fi

  backend_key="$(sed -n 's/^[[:space:]]*key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${stage_dir}/provider.tf" | head -n 1)"
  if [[ -z "${backend_key}" ]]; then
    backend_key="(unknown)"
  fi

  tmp_tf_data="$(mktemp -d)"

  if ! TF_DATA_DIR="${tmp_tf_data}" terraform -chdir="${stage_dir}" init -input=false -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null 2>&1; then
    printf '%-45s %-28s %8s %8s %8s %8s %s\n' "${rel_stage}" "${backend_key}" "-" "-" "-" "-" "INIT_FAILED"
    rm -rf "${tmp_tf_data}"
    continue
  fi

  mapfile -t defined_resources < <(python3 - "${stage_dir}" <<'PY'
import pathlib
import re
import sys

stage_dir = pathlib.Path(sys.argv[1])

for tf_file in sorted(stage_dir.glob("*.tf")):
    lines = tf_file.read_text().splitlines()
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        match = re.match(r'\s*resource\s+"([^"]+)"\s+"([^"]+)"\s*\{', line)
        if not match:
            idx += 1
            continue

        resource_type = match.group(1)
        resource_name = match.group(2)
        depth = line.count("{") - line.count("}")
        idx += 1
        top_level_lines = []

        while idx < len(lines) and depth > 0:
            current = lines[idx]
            if depth == 1:
                top_level_lines.append(current)
            depth += current.count("{") - current.count("}")
            idx += 1

        collection_expr = ""
        for entry in top_level_lines:
            expr_match = re.match(r'^\s*(for_each|count)\s*=\s*(.+?)\s*$', entry)
            if expr_match:
                collection_expr = expr_match.group(2).strip()
                break

        mode = "collection" if collection_expr else "singleton"
        print(f"{resource_type}.{resource_name}\t{mode}\t{collection_expr}")
PY
)
  mapfile -t state_resources < <(TF_DATA_DIR="${tmp_tf_data}" terraform -chdir="${stage_dir}" state list 2>/dev/null | grep -v '^data\.' | sort || true)

  defined_exact=()
  defined_collections=()
  tfvars_file=""
  if [[ "${rel_stage}" == terraform/swarm/* ]]; then
    tfvars_file="$(resolve_stage_tfvars "${stage_dir}" || true)"
  fi

  for entry in "${defined_resources[@]}"; do
    IFS=$'\t' read -r address mode collection_expr <<<"${entry}"
    if [[ "${mode}" == "collection" ]]; then
      defined_collections+=("${address}"$'\t'"${collection_expr}")
    else
      defined_exact+=("${address}")
    fi
  done

  missing_resources=()
  for resource in "${defined_exact[@]}"; do
    if ! printf '%s\n' "${state_resources[@]}" | grep -Fxq "${resource}"; then
      missing_resources+=("${resource}")
    fi
  done
  for resource in "${defined_collections[@]}"; do
    address="${resource%%$'\t'*}"
    collection_expr="${resource#*$'\t'}"
    if ! printf '%s\n' "${state_resources[@]}" | grep -Eq "^${address}(\\[.+\\])?$"; then
      if [[ -n "${tfvars_file}" ]] && [[ "$(collection_has_instances "${stage_dir}" "${tmp_tf_data}" "${tfvars_file}" "${collection_expr}" || echo 1)" == "0" ]]; then
        continue
      fi
      missing_resources+=("${address}")
    fi
  done

  extra_resources=()
  for resource in "${state_resources[@]}"; do
    if printf '%s\n' "${defined_exact[@]}" | grep -Fxq "${resource}"; then
      continue
    fi

    matched_collection="0"
    for collection in "${defined_collections[@]}"; do
      address="${collection%%$'\t'*}"
      if [[ "${resource}" == "${address}" ]] || [[ "${resource}" == "${address}"[* ]]; then
        matched_collection="1"
        break
      fi
    done

    if [[ "${matched_collection}" == "0" ]]; then
      extra_resources+=("${resource}")
    fi
  done

  status="IN_SYNC"
  if [[ ${#defined_resources[@]} -eq 0 && ${#state_resources[@]} -eq 0 ]]; then
    status="EMPTY_CONFIG"
  elif [[ ${#state_resources[@]} -eq 0 ]]; then
    status="STATE_EMPTY"
  elif [[ ${#missing_resources[@]} -gt 0 && ${#extra_resources[@]} -gt 0 ]]; then
    status="PARTIAL"
  elif [[ ${#missing_resources[@]} -gt 0 ]]; then
    status="MISSING_STATE"
  elif [[ ${#extra_resources[@]} -gt 0 ]]; then
    status="ORPHANED_STATE"
  fi

  printf '%-45s %-28s %8d %8d %8d %8d %s\n' \
    "${rel_stage}" \
    "${backend_key}" \
    "$(( ${#defined_exact[@]} + ${#defined_collections[@]} ))" \
    "${#state_resources[@]}" \
    "${#missing_resources[@]}" \
    "${#extra_resources[@]}" \
    "${status}"

  if [[ ${#missing_resources[@]} -gt 0 ]]; then
    printf '  missing: %s\n' "$(printf '%s, ' "${missing_resources[@]}" | sed 's/, $//')"
  fi
  if [[ ${#extra_resources[@]} -gt 0 ]]; then
    printf '  extra: %s\n' "$(printf '%s, ' "${extra_resources[@]}" | sed 's/, $//')"
  fi

  rm -rf "${tmp_tf_data}"
done
