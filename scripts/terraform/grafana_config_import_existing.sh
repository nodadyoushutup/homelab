#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAGE_DIR="${ROOT_DIR}/terraform/swarm/grafana/config"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/config}}"
TFVARS_FILE="${TFVARS_FILE:-${TFVARS_HOME_DIR}/grafana/config.tfvars}"
BACKEND_FILE="${BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"
DRY_RUN="0"

usage() {
  cat <<USAGE
Usage: scripts/terraform/grafana_config_import_existing.sh [--tfvars <path>] [--backend <path>] [--dry-run]

Imports existing Grafana data sources, folders, and dashboards into the shared
grafana-config Terraform state using the stable UIDs already defined in code.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tfvars)
      [[ $# -ge 2 ]] || { echo "[ERR] --tfvars requires a value" >&2; exit 2; }
      TFVARS_FILE="$2"
      shift 2
      ;;
    --backend)
      [[ $# -ge 2 ]] || { echo "[ERR] --backend requires a value" >&2; exit 2; }
      BACKEND_FILE="$2"
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

for required_file in "${TFVARS_FILE}" "${BACKEND_FILE}" "${STAGE_DIR}/main.tf"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "[ERR] Required file not found: ${required_file}" >&2
    exit 1
  fi
done

tmp_manifest="$(mktemp)"
cleanup() {
  rm -f "${tmp_manifest}"
}
trap cleanup EXIT

python3 - "${STAGE_DIR}" > "${tmp_manifest}" <<'PY'
import json
import pathlib
import re
import sys

stage_dir = pathlib.Path(sys.argv[1])
main_tf = (stage_dir / "main.tf").read_text()

file_map = {}
for local_name, filename in re.findall(r'([A-Za-z0-9_]+)_file_path\s*=\s*"\$\{path\.module\}/dashboards/([^"]+)"', main_tf):
    file_map[local_name] = stage_dir / "dashboards" / filename

resource_blocks = re.findall(
    r'resource\s+"(grafana_data_source|grafana_folder|grafana_dashboard)"\s+"([^"]+)"\s+\{(.*?)\n\}',
    main_tf,
    re.S,
)

for resource_type, resource_name, body in resource_blocks:
    import_id = None
    if resource_type in {"grafana_data_source", "grafana_folder"}:
        match = re.search(r'uid\s*=\s*"([^"]+)"', body)
        if match:
            import_id = match.group(1)
    elif resource_type == "grafana_dashboard":
        match = re.search(r'config_json\s*=\s*local\.([A-Za-z0-9_]+)_content', body)
        if match:
            local_name = match.group(1)
            dashboard_path = file_map.get(local_name)
            if dashboard_path and dashboard_path.exists():
                import_id = json.loads(dashboard_path.read_text()).get("uid")

    if import_id:
        print(f"{resource_type}.{resource_name}\t{import_id}")
PY

if [[ ! -s "${tmp_manifest}" ]]; then
  echo "[ERR] No importable Grafana resources found in ${STAGE_DIR}/main.tf" >&2
  exit 1
fi

terraform -chdir="${STAGE_DIR}" init -input=false -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null

mapfile -t existing_state < <(terraform -chdir="${STAGE_DIR}" state list 2>/dev/null | sort || true)

while IFS=$'\t' read -r address import_id; do
  if printf '%s\n' "${existing_state[@]}" | grep -Fxq "${address}"; then
    echo "[SKIP] ${address} already exists in remote state"
    continue
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[PLAN] terraform -chdir=${STAGE_DIR} import -input=false -var-file ${TFVARS_FILE} ${address} ${import_id}"
    continue
  fi

  echo "[STEP] Importing ${address} from ${import_id}"
  terraform -chdir="${STAGE_DIR}" import -input=false -var-file "${TFVARS_FILE}" "${address}" "${import_id}"
done < "${tmp_manifest}"

if [[ "${DRY_RUN}" == "1" ]]; then
  exit 0
fi

echo "[STEP] Verifying refreshed remote state"
terraform -chdir="${STAGE_DIR}" plan -input=false -refresh-only -var-file "${TFVARS_FILE}" >/dev/null
echo "[DONE] Grafana config imports completed and refresh-only verification passed."
