#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/load_root_env.sh"

TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"
BACKEND_FILE="${BACKEND_FILE:-${TFVARS_HOME_DIR}/terraform/minio.backend.hcl}"
ONLY_PATTERN=""
DRY_RUN="0"
REMOTE_TERRAFORM_IMAGE="${REMOTE_TERRAFORM_IMAGE:-hashicorp/terraform:1.14.0}"
SHARED_TMP_DIR="${TFVARS_HOME_DIR}/.codex-backups/terraform-remote-imports"
SSH_KNOWN_HOSTS="${TFVARS_HOME_DIR}/.ssh/known_hosts"
SSH_PRIVATE_KEY="${TFVARS_HOME_DIR}/.ssh/ca/id_ed25519"

usage() {
  cat <<USAGE
Usage: scripts/terraform/repair_docker_remote_state.sh [--backend <path>] [--only <regex>] [--dry-run]

Imports missing managed resources for Docker-backed Terraform stages into the
shared remote state. Singleton networks, volumes, configs, and services are
reconciled automatically. Collection resources that use for_each/count are
reported for follow-up.
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
    --dry-run)
      DRY_RUN="1"
      shift
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

for required_path in "${BACKEND_FILE}" "${SSH_KNOWN_HOSTS}" "${SSH_PRIVATE_KEY}"; do
  if [[ ! -f "${required_path}" ]]; then
    echo "[ERR] Required file not found: ${required_path}" >&2
    exit 1
  fi
done

mkdir -p "${SHARED_TMP_DIR}"

ssh_base_args=(
  ssh
  -o
  StrictHostKeyChecking=no
  -o
  "UserKnownHostsFile=${SSH_KNOWN_HOSTS}"
  -i
  "${SSH_PRIVATE_KEY}"
)

resolve_stage_tfvars() {
  local stage_dir="$1"
  local rel_service
  local service_dir
  local stage_name
  local hyphen_service_dir
  local candidate
  local candidates=()

  rel_service="${stage_dir#${ROOT_DIR}/terraform/components/swarm/}"
  service_dir="${rel_service%/*}"
  stage_name="${rel_service##*/}"
  hyphen_service_dir="${service_dir//_/-}"

  candidates+=("${TFVARS_HOME_DIR}/terraform/components/swarm/${service_dir}/${stage_name}.tfvars")
  candidates+=("${TFVARS_HOME_DIR}/terraform/components/swarm/${service_dir}/${stage_name}/${stage_name}.tfvars")
  candidates+=("${TFVARS_HOME_DIR}/${service_dir}/${stage_name}.tfvars")
  if [[ "${hyphen_service_dir}" != "${service_dir}" ]]; then
    candidates+=("${TFVARS_HOME_DIR}/${hyphen_service_dir}/${stage_name}.tfvars")
  fi
  candidates+=("${TFVARS_HOME_DIR}/${service_dir}.tfvars")
  if [[ "${hyphen_service_dir}" != "${service_dir}" ]]; then
    candidates+=("${TFVARS_HOME_DIR}/${hyphen_service_dir}.tfvars")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}" ]]; then
      realpath "${candidate}"
      return 0
    fi
  done

  return 1
}

extract_ssh_target() {
  local tfvars_file="$1"

  python3 - "${tfvars_file}" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'host\s*=\s*"ssh://([^"]+)"', text)
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
}

write_remote_override_tfvars() {
  local tfvars_file="$1"
  local override_file="$2"

  python3 - "${tfvars_file}" "${override_file}" <<'PY'
import pathlib
import re
import sys

src_path = pathlib.Path(sys.argv[1])
dst_path = pathlib.Path(sys.argv[2])
text = src_path.read_text()

text, host_count = re.subn(
    r'host\s*=\s*"ssh://[^"]+"',
    'host = "unix:///var/run/docker.sock"',
    text,
    count=1,
)
text, opts_count = re.subn(
    r'ssh_opts\s*=\s*\[(?:[^\[\]]|\n)*?\]',
    'ssh_opts = []',
    text,
    count=1,
    flags=re.S,
)

if host_count != 1 or opts_count != 1:
    raise SystemExit("Unable to rewrite docker host/ssh_opts in tfvars")

dst_path.write_text(text)
print(dst_path)
PY
}

list_stage_resources() {
  local stage_dir="$1"

  python3 - "${stage_dir}" <<'PY'
import pathlib
import re
import sys

stage_dir = pathlib.Path(sys.argv[1])

for tf_file in sorted(stage_dir.glob("*.tf")):
    lines = tf_file.read_text().splitlines()
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        match = re.match(r'\s*resource\s+"(docker_[^"]+)"\s+"([^"]+)"\s*\{', line)
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

        top_level = "\n".join(top_level_lines)
        collection_expr = ""
        for entry in top_level_lines:
            expr_match = re.match(r'^\s*(for_each|count)\s*=\s*(.+?)\s*$', entry)
            if expr_match:
                collection_expr = expr_match.group(2).strip()
                break

        mode = "collection" if collection_expr else "singleton"
        name_expr = ""
        name_match = re.search(r'^\s*name\s*=\s*(.+?)\s*$', top_level, re.M)
        if name_match:
            name_expr = name_match.group(1).strip()

        print(f"{resource_type}.{resource_name}\t{resource_type}\t{mode}\t{name_expr}\t{collection_expr}")
PY
}

evaluate_name_expr() {
  local stage_dir="$1"
  local tf_data_dir="$2"
  local tfvars_file="$3"
  local name_expr="$4"
  local rendered

  rendered="$(
    TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${stage_dir}" console -var-file "${tfvars_file}" <<EOF
${name_expr}
EOF
  )"

  python3 -c 'import json, sys
value = sys.stdin.read().strip()
if not value:
    raise SystemExit(1)
print(json.loads(value))' <<<"${rendered}"
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

remote_lookup_id() {
  local ssh_target="$1"
  local object_type="$2"
  local object_name="$3"
  local escaped_name

  printf -v escaped_name '%q' "${object_name}"
  "${ssh_base_args[@]}" "${ssh_target}" "docker ${object_type} inspect ${escaped_name} --format '{{.ID}}'" 2>/dev/null
}

import_local_resource() {
  local stage_dir="$1"
  local tf_data_dir="$2"
  local tfvars_file="$3"
  local address="$4"
  local import_id="$5"

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[PLAN] terraform -chdir=${stage_dir} import -input=false -var-file ${tfvars_file} ${address} ${import_id}"
    return 0
  fi

  TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${stage_dir}" import -input=false -var-file "${tfvars_file}" "${address}" "${import_id}"
}

import_remote_services() {
  local stage_dir="$1"
  local rel_stage="$2"
  local ssh_target="$3"
  local manifest_file="$4"
  local tfvars_file="$5"

  [[ -s "${manifest_file}" ]] || return 0

  local stage_slug
  local override_file
  local archive_file

  stage_slug="$(echo "${rel_stage}" | tr '/[:space:]' '__')"
  override_file="${SHARED_TMP_DIR}/${stage_slug}.remote-import.tfvars"
  archive_file="${SHARED_TMP_DIR}/${stage_slug}.stage.tar"

  write_remote_override_tfvars "${tfvars_file}" "${override_file}" >/dev/null
  tar cf "${archive_file}" --exclude='.terraform' --exclude='.terraform.lock.hcl' -C "${stage_dir}" .

  if [[ "${DRY_RUN}" == "1" ]]; then
    while IFS=$'\t' read -r address import_id; do
      echo "[PLAN] remote import ${rel_stage}: ${address} <= ${import_id}"
    done < "${manifest_file}"
    rm -f "${override_file}" "${archive_file}" "${manifest_file}"
    return 0
  fi

  "${ssh_base_args[@]}" "${ssh_target}" bash -s -- "${archive_file}" "${manifest_file}" "${override_file}" "${BACKEND_FILE}" "${REMOTE_TERRAFORM_IMAGE}" <<'EOF'
set -euo pipefail

archive_file="$1"
manifest_file="$2"
override_file="$3"
backend_file="$4"
terraform_image="$5"

workdir="$(mktemp -d /tmp/terraform-remote-import-XXXXXX)"
uid="$(id -u)"
gid="$(id -g)"
docker_gid="$(stat -c '%g' /var/run/docker.sock)"

cleanup() {
  chmod -R u+w "${workdir}" >/dev/null 2>&1 || true
  rm -rf "${workdir}"
}
trap cleanup EXIT

tar xf "${archive_file}" -C "${workdir}"

run_tf() {
  docker run --rm \
    -u "${uid}:${gid}" \
    --group-add "${docker_gid}" \
    -v "${workdir}:${workdir}" \
    -v "${TFVARS_HOME_DIR}:${TFVARS_HOME_DIR}" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w "${workdir}" \
    "${terraform_image}" \
    "$@"
}

run_tf init -input=false -reconfigure -backend-config="${backend_file}" >/dev/null

while IFS=$'\t' read -r address import_id; do
  echo "[REMOTE] Importing ${address} from ${import_id}"
  run_tf import -input=false -var-file "${override_file}" "${address}" "${import_id}"
done < "${manifest_file}"
EOF

  rm -f "${override_file}" "${archive_file}" "${manifest_file}"
}

mapfile -t stage_dirs < <(
  find "${ROOT_DIR}/terraform/components/swarm" -mindepth 3 -maxdepth 3 -type f -name provider.tf -print \
    | while read -r provider_file; do
        if grep -q 'source[[:space:]]*=[[:space:]]*"kreuzwerker/docker"' "${provider_file}"; then
          dirname "${provider_file}"
        fi
      done \
    | sort
)

if [[ ${#stage_dirs[@]} -eq 0 ]]; then
  echo "[ERR] No Docker-backed Terraform stages found." >&2
  exit 1
fi

processed_count=0
repaired_count=0
warn_count=0

for stage_dir in "${stage_dirs[@]}"; do
  rel_stage="${stage_dir#${ROOT_DIR}/}"

  if [[ -n "${ONLY_PATTERN}" ]] && ! [[ "${rel_stage}" =~ ${ONLY_PATTERN} ]]; then
    continue
  fi

  ((processed_count += 1))

  tfvars_file=""
  if ! tfvars_file="$(resolve_stage_tfvars "${stage_dir}")"; then
    echo "[WARN] ${rel_stage}: unable to resolve tfvars file" >&2
    ((warn_count += 1))
    continue
  fi

  ssh_target=""
  if ! ssh_target="$(extract_ssh_target "${tfvars_file}")"; then
    echo "[WARN] ${rel_stage}: unable to resolve ssh docker host from ${tfvars_file}" >&2
    ((warn_count += 1))
    continue
  fi

  tf_data_dir="$(mktemp -d)"
  service_manifest="$(mktemp "${SHARED_TMP_DIR}/services-XXXXXX.tsv")"
  stage_had_repairs="0"
  stage_missing_collection=()

  cleanup_stage() {
    rm -rf "${tf_data_dir}"
    rm -f "${service_manifest}" 2>/dev/null || true
  }

  if ! TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${stage_dir}" init -input=false -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null 2>&1; then
    echo "[WARN] ${rel_stage}: terraform init failed" >&2
    ((warn_count += 1))
    cleanup_stage
    continue
  fi

  mapfile -t state_resources < <(TF_DATA_DIR="${tf_data_dir}" terraform -chdir="${stage_dir}" state list 2>/dev/null | grep -v '^data\.' | sort || true)
  mapfile -t resource_rows < <(list_stage_resources "${stage_dir}")

  if [[ ${#resource_rows[@]} -eq 0 ]]; then
    echo "[SKIP] ${rel_stage}: no managed docker resources found"
    cleanup_stage
    continue
  fi

  echo "[STAGE] ${rel_stage}"

  for row in "${resource_rows[@]}"; do
    IFS=$'\t' read -r address resource_type mode name_expr collection_expr <<<"${row}"

    if [[ "${mode}" == "collection" ]]; then
      if ! printf '%s\n' "${state_resources[@]}" | grep -Eq "^${address}(\\[.+\\])?$"; then
        if [[ "$(collection_has_instances "${stage_dir}" "${tf_data_dir}" "${tfvars_file}" "${collection_expr}" || echo 1)" == "1" ]]; then
          stage_missing_collection+=("${address}")
        fi
      fi
      continue
    fi

    if printf '%s\n' "${state_resources[@]}" | grep -Fxq "${address}"; then
      echo "  [SKIP] ${address} already in remote state"
      continue
    fi

    if [[ -z "${name_expr}" ]]; then
      echo "  [WARN] ${address}: unable to determine name expression" >&2
      ((warn_count += 1))
      continue
    fi

    desired_name=""
    if ! desired_name="$(evaluate_name_expr "${stage_dir}" "${tf_data_dir}" "${tfvars_file}" "${name_expr}")"; then
      echo "  [WARN] ${address}: unable to evaluate name expression ${name_expr}" >&2
      ((warn_count += 1))
      continue
    fi

    case "${resource_type}" in
      docker_network|docker_volume)
        echo "  [STEP] Importing ${address} from ${desired_name}"
        import_local_resource "${stage_dir}" "${tf_data_dir}" "${tfvars_file}" "${address}" "${desired_name}"
        stage_had_repairs="1"
        ;;
      docker_config)
        config_id="$(remote_lookup_id "${ssh_target}" config "${desired_name}" || true)"
        if [[ -z "${config_id}" ]]; then
          echo "  [WARN] ${address}: live config ${desired_name} not found; leaving for future apply" >&2
          ((warn_count += 1))
          continue
        fi
        echo "  [STEP] Importing ${address} from ${config_id}"
        import_local_resource "${stage_dir}" "${tf_data_dir}" "${tfvars_file}" "${address}" "${config_id}"
        stage_had_repairs="1"
        ;;
      docker_service)
        service_id="$(remote_lookup_id "${ssh_target}" service "${desired_name}" || true)"
        if [[ -z "${service_id}" ]]; then
          echo "  [WARN] ${address}: live service ${desired_name} not found" >&2
          ((warn_count += 1))
          continue
        fi
        echo -e "${address}\t${service_id}" >> "${service_manifest}"
        stage_had_repairs="1"
        ;;
      *)
        echo "  [WARN] ${address}: unsupported resource type ${resource_type}" >&2
        ((warn_count += 1))
        ;;
    esac
  done

  if [[ -s "${service_manifest}" ]]; then
    import_remote_services "${stage_dir}" "${rel_stage}" "${ssh_target}" "${service_manifest}" "${tfvars_file}"
  fi

  if [[ ${#stage_missing_collection[@]} -gt 0 ]]; then
    echo "  [WARN] collection resources need manual follow-up: $(printf '%s, ' "${stage_missing_collection[@]}" | sed 's/, $//')" >&2
    ((warn_count += 1))
  fi

  if [[ "${stage_had_repairs}" == "1" ]]; then
    ((repaired_count += 1))
  fi

  cleanup_stage
done

echo "[DONE] Processed ${processed_count} Docker-backed stages; repaired ${repaired_count}; warnings ${warn_count}."
