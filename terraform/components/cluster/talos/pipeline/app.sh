#!/usr/bin/env bash
# Bespoke Talos cluster deploy (intentional during the AGENTS.md audit campaign).
# Bespoke self-contained entrypoint (shared *_pipeline.sh wrappers removed).
# Single slice tfvars only (no shared provider var-files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"

CONFIG_DIR="${CONFIG_DIR:-${ROOT_DIR}/.config}"
export CONFIG_DIR

# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="talos"
STAGE_NAME="Talos cluster"
ENTRYPOINT_RELATIVE="terraform/components/cluster/talos/pipeline/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/components/cluster/talos/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${CONFIG_DIR:-${ROOT_DIR}/.config}}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()
declare -A REPLACE_TARGET_SEEN=()
declare -A NODE_TARGET_IP=()
declare -A READY_IPS=()
ALL_NODE_TARGETS=()
CONTROL_PLANE_TARGET=""
CONTROL_PLANE_IP=""
MACHINE_SECRETS_STATE_ADDRESS="talos_machine_secrets.cluster"
BOOTSTRAP_STATE_ADDRESS="talos_machine_bootstrap.cluster"
BOOTSTRAP_STATE_ID="machine_bootstrap"
KUBECONFIG_STATE_ADDRESS="talos_cluster_kubeconfig.cluster"
TALOS_SECRETS_EXPORT_SCRIPT="${ROOT_DIR}/scripts/terraform/export_talos_secrets_from_machineconfig.py"
MANAGED_TALOSCONFIG_OUTPUT_PATH="${MANAGED_TALOSCONFIG_OUTPUT_PATH:-${TFVARS_HOME_DIR}/terraform/components/cluster/talos/app/talosconfig}"
MANAGED_KUBECONFIG_OUTPUT_PATH="${MANAGED_KUBECONFIG_OUTPUT_PATH:-${TFVARS_HOME_DIR}/terraform/components/cluster/talos/app/kubeconfig}"
TALOS_SECRETS_IMPORT_PATH="${TALOS_SECRETS_IMPORT_PATH:-}"
GENERATED_TALOS_SECRETS_IMPORT_PATH=""
OVERRIDE_TALOSCONFIG_OUTPUT_PATH="__UNSET__"
OVERRIDE_KUBECONFIG_OUTPUT_PATH="__UNSET__"
EXEC_SCRIPT="${PIPELINE_SCRIPT_ROOT}/terraform_exec.sh"

NODE_SPECS=(
  "talos_machine_configuration_apply.k8s_cp_0|k8s_cp_0_node|control-plane"
  "talos_machine_configuration_apply.k8s_wk_0|k8s_wk_0_node|worker"
  "talos_machine_configuration_apply.k8s_wk_1|k8s_wk_1_node|worker"
  "talos_machine_configuration_apply.k8s_wk_2|k8s_wk_2_node|worker"
  "talos_machine_configuration_apply.k8s_wk_3|k8s_wk_3_node|worker"
  "talos_machine_configuration_apply.k8s_wk_4|k8s_wk_4_node|worker"
  "talos_machine_configuration_apply.k8s_wk_5|k8s_wk_5_node|worker"
  "talos_machine_configuration_apply.k8s_wk_6|k8s_wk_6_node|worker"
  "talos_machine_configuration_apply.k8s_wk_7|k8s_wk_7_node|worker"
  "talos_machine_configuration_apply.k8s_wk_8|k8s_wk_8_node|worker"
  "talos_machine_configuration_apply.k8s_wk_9|k8s_wk_9_node|worker"
  "talos_machine_configuration_apply.k8s_wk_10|k8s_wk_10_node|worker"
)

# Add the same replace target to plan/apply so preview matches execution.
append_replace_target() {
  local target="$1"
  if [[ -n "${REPLACE_TARGET_SEEN[$target]:-}" ]]; then
    return 0
  fi
  REPLACE_TARGET_SEEN["$target"]="1"
  PLAN_ARGS_EXTRA+=("-replace=${target}")
  APPLY_ARGS_EXTRA+=("-replace=${target}")
}

append_replace_targets() {
  local target
  for target in "$@"; do
    append_replace_target "${target}"
  done
}

append_var_override() {
  local expression="$1"
  PLAN_ARGS_EXTRA+=("-var" "${expression}")
  APPLY_ARGS_EXTRA+=("-var" "${expression}")
}

extract_talos_endpoint() {
  extract_tfvar_string "endpoint"
}

extract_talos_bootstrap_node() {
  extract_tfvar_string "bootstrap_node"
}

is_talos_api_reachable() {
  local endpoint="$1"
  [[ -n "${endpoint}" ]] && timeout 1 bash -c "</dev/tcp/${endpoint}/6443" >/dev/null 2>&1
}

extract_tfvar_string() {
  local key="$1"
  awk -v key="${key}" '
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      if (match($0, /"[^"]+"/)) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  ' "${TFVARS_PATH}" || true
}

extract_cluster_name() {
  extract_tfvar_string "cluster_name"
}

extract_talosconfig_output_path() {
  local from_tfvars=""

  if [[ "${OVERRIDE_TALOSCONFIG_OUTPUT_PATH}" != "__UNSET__" ]]; then
    echo "${OVERRIDE_TALOSCONFIG_OUTPUT_PATH}"
    return 0
  fi

  from_tfvars="$(extract_tfvar_string "talosconfig_output_path")"
  if [[ -n "${from_tfvars}" ]]; then
    echo "${from_tfvars}"
    return 0
  fi

  echo "${HOME}/.talos/config"
}

extract_configured_talosconfig_output_path() {
  local from_tfvars=""

  from_tfvars="$(extract_tfvar_string "talosconfig_output_path")"
  if [[ -n "${from_tfvars}" ]]; then
    echo "${from_tfvars}"
    return 0
  fi

  echo "${HOME}/.talos/config"
}

extract_kubeconfig_output_path() {
  local from_tfvars=""
  local cluster_name=""

  if [[ "${OVERRIDE_KUBECONFIG_OUTPUT_PATH}" != "__UNSET__" ]]; then
    echo "${OVERRIDE_KUBECONFIG_OUTPUT_PATH}"
    return 0
  fi

  from_tfvars="$(extract_tfvar_string "kubeconfig_output_path")"
  if [[ -n "${from_tfvars}" ]]; then
    echo "${from_tfvars}"
    return 0
  fi

  cluster_name="$(extract_cluster_name)"
  if [[ -n "${cluster_name}" ]]; then
    echo "${HOME}/.kube/${cluster_name}.config"
    return 0
  fi

  echo "${HOME}/.kube/config"
}

path_parent_is_writable_or_creatable() {
  local target_path="$1"
  local parent_dir=""

  [[ -n "${target_path}" ]] || return 1

  parent_dir="$(dirname "${target_path}")"
  while [[ ! -e "${parent_dir}" && "${parent_dir}" != "/" ]]; do
    parent_dir="$(dirname "${parent_dir}")"
  done

  [[ -d "${parent_dir}" && -w "${parent_dir}" ]]
}

redirect_local_file_outputs_if_unwritable() {
  local talosconfig_path=""
  local kubeconfig_path=""

  talosconfig_path="$(extract_talosconfig_output_path)"
  kubeconfig_path="$(extract_kubeconfig_output_path)"

  if [[ -n "${talosconfig_path}" ]] && ! path_parent_is_writable_or_creatable "${talosconfig_path}"; then
    if path_parent_is_writable_or_creatable "${MANAGED_TALOSCONFIG_OUTPUT_PATH}" && path_parent_is_writable_or_creatable "${MANAGED_KUBECONFIG_OUTPUT_PATH}"; then
      OVERRIDE_TALOSCONFIG_OUTPUT_PATH="${MANAGED_TALOSCONFIG_OUTPUT_PATH}"
      OVERRIDE_KUBECONFIG_OUTPUT_PATH="${MANAGED_KUBECONFIG_OUTPUT_PATH}"
    else
      OVERRIDE_TALOSCONFIG_OUTPUT_PATH=""
      OVERRIDE_KUBECONFIG_OUTPUT_PATH=""
    fi
  fi

  if [[ -n "${kubeconfig_path}" ]] && ! path_parent_is_writable_or_creatable "${kubeconfig_path}"; then
    if path_parent_is_writable_or_creatable "${MANAGED_TALOSCONFIG_OUTPUT_PATH}" && path_parent_is_writable_or_creatable "${MANAGED_KUBECONFIG_OUTPUT_PATH}"; then
      OVERRIDE_TALOSCONFIG_OUTPUT_PATH="${MANAGED_TALOSCONFIG_OUTPUT_PATH}"
      OVERRIDE_KUBECONFIG_OUTPUT_PATH="${MANAGED_KUBECONFIG_OUTPUT_PATH}"
    else
      OVERRIDE_TALOSCONFIG_OUTPUT_PATH=""
      OVERRIDE_KUBECONFIG_OUTPUT_PATH=""
    fi
  fi

  if [[ "${OVERRIDE_TALOSCONFIG_OUTPUT_PATH}" == "${MANAGED_TALOSCONFIG_OUTPUT_PATH}" && "${OVERRIDE_KUBECONFIG_OUTPUT_PATH}" == "${MANAGED_KUBECONFIG_OUTPUT_PATH}" ]]; then
    echo "[INFO] Redirecting Talos local file outputs to shared managed paths under ${TFVARS_HOME_DIR}/terraform/components/cluster/talos/app"
    append_var_override "talosconfig_output_path=${OVERRIDE_TALOSCONFIG_OUTPUT_PATH}"
    append_var_override "kubeconfig_output_path=${OVERRIDE_KUBECONFIG_OUTPUT_PATH}"
    return 0
  fi

  if [[ "${OVERRIDE_TALOSCONFIG_OUTPUT_PATH}" == "" && "${OVERRIDE_KUBECONFIG_OUTPUT_PATH}" == "" ]]; then
    echo "[INFO] Disabling Talos local file outputs on this runner (configured paths are not writable)"
    append_var_override "talosconfig_output_path="
    append_var_override "kubeconfig_output_path="
  fi
}

state_has_address() {
  local address="$1"
  "${EXEC_SCRIPT}" state show -no-color "${address}" >/dev/null 2>&1
}

state_ca_matches_talos_endpoint() {
  local endpoint="$1"
  local ca_b64=""
  local tmp_dir=""
  local ca_file=""

  if ! state_has_address "${MACHINE_SECRETS_STATE_ADDRESS}"; then
    return 1
  fi

  ca_b64="$("${EXEC_SCRIPT}" state show -no-color "${MACHINE_SECRETS_STATE_ADDRESS}" | awk -F'"' '/ca_certificate[[:space:]]*=/{print $2; exit}')"
  [[ -n "${ca_b64}" ]] || return 1

  tmp_dir="$(mktemp -d)"
  ca_file="${tmp_dir}/talos-ca.pem"
  if ! printf '%s' "${ca_b64}" | base64 -d > "${ca_file}" 2>/dev/null; then
    rm -rf "${tmp_dir}"
    return 1
  fi

  if timeout 5 openssl s_client -verify_return_error \
    -connect "${endpoint}:50000" \
    -servername "${endpoint}" \
    -CAfile "${ca_file}" \
    </dev/null >/dev/null 2>&1; then
    rm -rf "${tmp_dir}"
    return 0
  fi

  rm -rf "${tmp_dir}"
  return 1
}

ensure_talos_secrets_import_file() {
  local bootstrap_node=""
  local talosconfig_path=""
  local import_path=""
  local candidate=""
  local -a talosconfig_candidates=()

  if [[ -n "${TALOS_SECRETS_IMPORT_PATH}" && -f "${TALOS_SECRETS_IMPORT_PATH}" ]]; then
    return 0
  fi

  bootstrap_node="$(extract_talos_bootstrap_node)"
  talosconfig_candidates=(
    "$(extract_talosconfig_output_path)"
    "$(extract_configured_talosconfig_output_path)"
    "${MANAGED_TALOSCONFIG_OUTPUT_PATH}"
    "${HOME}/.talos/config"
  )
  for candidate in "${talosconfig_candidates[@]}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      talosconfig_path="${candidate}"
      break
    fi
  done

  if [[ ! -f "${TALOS_SECRETS_EXPORT_SCRIPT}" || -z "${bootstrap_node}" || -z "${talosconfig_path}" ]]; then
    return 1
  fi

  if [[ -n "${TALOS_SECRETS_IMPORT_PATH}" ]]; then
    import_path="${TALOS_SECRETS_IMPORT_PATH}"
  else
    import_path="$(mktemp -t talos-machine-secrets-XXXXXX.yaml)"
    GENERATED_TALOS_SECRETS_IMPORT_PATH="${import_path}"
  fi

  echo "[INFO] Exporting live Talos machine secrets to ${import_path}"
  if python3 "${TALOS_SECRETS_EXPORT_SCRIPT}" \
    --talosconfig "${talosconfig_path}" \
    --node "${bootstrap_node}" \
    --output "${import_path}" >/dev/null; then
    if [[ -z "${TALOS_SECRETS_IMPORT_PATH}" ]]; then
      TALOS_SECRETS_IMPORT_PATH="${import_path}"
    fi
    return 0
  fi

  return 1
}

cleanup_generated_talos_secrets_import_file() {
  if [[ -n "${GENERATED_TALOS_SECRETS_IMPORT_PATH}" && -f "${GENERATED_TALOS_SECRETS_IMPORT_PATH}" ]]; then
    rm -f "${GENERATED_TALOS_SECRETS_IMPORT_PATH}"
  fi
  GENERATED_TALOS_SECRETS_IMPORT_PATH=""
  if [[ -n "${TALOS_SECRETS_IMPORT_PATH}" && ! -f "${TALOS_SECRETS_IMPORT_PATH}" ]]; then
    TALOS_SECRETS_IMPORT_PATH=""
  fi
}

repair_machine_secrets_state() {
  local endpoint="$1"
  local import_path=""

  if state_ca_matches_talos_endpoint "${endpoint}"; then
    return 0
  fi

  if state_has_address "${MACHINE_SECRETS_STATE_ADDRESS}"; then
    echo "[WARN] ${MACHINE_SECRETS_STATE_ADDRESS} CA does not match the live Talos API; repairing it"
  else
    echo "[WARN] ${MACHINE_SECRETS_STATE_ADDRESS} missing from state while Talos API is reachable; importing it"
  fi

  if ! ensure_talos_secrets_import_file; then
    echo "[ERR] Unable to repair ${MACHINE_SECRETS_STATE_ADDRESS}; expected a readable Talos config for live export" >&2
    exit 1
  fi
  import_path="${TALOS_SECRETS_IMPORT_PATH}"

  if state_has_address "${MACHINE_SECRETS_STATE_ADDRESS}"; then
    "${EXEC_SCRIPT}" state rm "${MACHINE_SECRETS_STATE_ADDRESS}" >/dev/null
  fi

  if ! "${EXEC_SCRIPT}" import -input=false -var-file "${TFVARS_PATH}" "${MACHINE_SECRETS_STATE_ADDRESS}" "${import_path}"; then
    cleanup_generated_talos_secrets_import_file
    echo "[ERR] Failed to import ${MACHINE_SECRETS_STATE_ADDRESS} from ${import_path}" >&2
    exit 1
  fi

  if ! state_ca_matches_talos_endpoint "${endpoint}"; then
    cleanup_generated_talos_secrets_import_file
    echo "[ERR] Imported ${MACHINE_SECRETS_STATE_ADDRESS}, but its CA still does not match the live Talos API" >&2
    exit 1
  fi

  cleanup_generated_talos_secrets_import_file
  echo "[INFO] Repaired ${MACHINE_SECRETS_STATE_ADDRESS} from ${import_path}"
}

init_node_targets() {
  local key
  local spec
  local target
  local tfvar_key
  local role
  local ip

  ALL_NODE_TARGETS=()
  CONTROL_PLANE_TARGET=""
  CONTROL_PLANE_IP=""

  for key in "${!NODE_TARGET_IP[@]}"; do
    unset "NODE_TARGET_IP[$key]"
  done

  for spec in "${NODE_SPECS[@]}"; do
    IFS='|' read -r target tfvar_key role <<<"${spec}"
    ip="$(extract_tfvar_string "${tfvar_key}")"
    if [[ -z "${ip}" ]]; then
      continue
    fi

    ALL_NODE_TARGETS+=("${target}")
    NODE_TARGET_IP["${target}"]="${ip}"
    if [[ "${role}" == "control-plane" ]]; then
      CONTROL_PLANE_TARGET="${target}"
      CONTROL_PLANE_IP="${ip}"
    fi
  done
}

clear_ready_ips() {
  local key
  for key in "${!READY_IPS[@]}"; do
    unset "READY_IPS[$key]"
  done
}

collect_ready_ips() {
  local kubeconfig_path="$1"
  local nodes_status_raw=""
  local line
  local ip
  local ready

  clear_ready_ips

  nodes_status_raw="$(timeout 7 kubectl --kubeconfig "${kubeconfig_path}" get nodes \
    -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"|"}{range .status.conditions[?(@.type=="Ready")]}{.status}{end}{"\n"}{end}' \
    2>/dev/null || true)"

  if [[ -z "${nodes_status_raw}" ]]; then
    return 1
  fi

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    IFS='|' read -r ip ready <<<"${line}"
    if [[ -n "${ip}" && "${ready}" == "True" ]]; then
      READY_IPS["${ip}"]="1"
    fi
  done <<<"${nodes_status_raw}"

  return 0
}

# Bootstrap replacement policy:
# - auto (default): replace bootstrap only when Talos API endpoint:6443 is down.
# - always: always replace bootstrap.
# - never: never replace bootstrap.
pipeline_pre_terraform() {
  local mode="${FORCE_TALOS_BOOTSTRAP_REPLACE:-auto}"
  local endpoint=""
  local kubeconfig_path=""
  local api_reachable="0"
  local kubectl_signal="0"
  local replace_bootstrap="0"
  local target=""
  local ip=""
  local -a node_targets_to_replace=()

  init_node_targets
  redirect_local_file_outputs_if_unwritable
  endpoint="$(extract_talos_endpoint)"
  kubeconfig_path="$(extract_kubeconfig_output_path)"

  if is_talos_api_reachable "${endpoint}"; then
    api_reachable="1"
  fi

  if command -v kubectl >/dev/null 2>&1 && [[ -f "${kubeconfig_path}" ]]; then
    if collect_ready_ips "${kubeconfig_path}"; then
      kubectl_signal="1"
    fi
  fi

  if [[ "${kubectl_signal}" == "1" ]]; then
    for target in "${ALL_NODE_TARGETS[@]}"; do
      ip="${NODE_TARGET_IP[$target]}"
      if [[ -z "${READY_IPS[$ip]:-}" ]]; then
        node_targets_to_replace+=("${target}")
      fi
    done

    if [[ ${#node_targets_to_replace[@]} -eq 0 ]]; then
      echo "[INFO] Cluster health check: all configured nodes are Ready"
    else
      echo "[INFO] Cluster health check: reconciling ${#node_targets_to_replace[@]} unready/missing node(s)"
      append_replace_targets "${node_targets_to_replace[@]}"
      append_replace_target "${KUBECONFIG_STATE_ADDRESS}"
    fi
  else
    if [[ "${api_reachable}" == "1" ]]; then
      echo "[WARN] Kubernetes health check unavailable; reconciling all Talos nodes"
    else
      echo "[WARN] Talos API ${endpoint:-<unknown>}:6443 unreachable; reconciling all Talos nodes"
    fi
    append_replace_targets "${ALL_NODE_TARGETS[@]}"
    append_replace_target "${KUBECONFIG_STATE_ADDRESS}"
  fi

  case "${mode}" in
    always|true|1|yes)
      replace_bootstrap="1"
      ;;
    never|false|0|no)
      replace_bootstrap="0"
      ;;
    auto)
      if [[ "${kubectl_signal}" == "1" ]]; then
        if [[ -n "${CONTROL_PLANE_IP}" && -n "${READY_IPS[$CONTROL_PLANE_IP]:-}" ]]; then
          replace_bootstrap="0"
        else
          replace_bootstrap="1"
        fi
      elif [[ -z "${endpoint}" ]]; then
        echo "[WARN] Talos endpoint not found in tfvars; forcing bootstrap replace"
        replace_bootstrap="1"
      elif [[ "${api_reachable}" == "1" ]]; then
        replace_bootstrap="0"
      else
        replace_bootstrap="1"
      fi
      ;;
    *)
      echo "[WARN] Unknown FORCE_TALOS_BOOTSTRAP_REPLACE='${mode}', defaulting to auto"
      if [[ "${kubectl_signal}" == "1" ]]; then
        if [[ -z "${CONTROL_PLANE_IP}" || -z "${READY_IPS[$CONTROL_PLANE_IP]:-}" ]]; then
          replace_bootstrap="1"
        fi
      elif [[ -z "${endpoint}" || "${api_reachable}" != "1" ]]; then
        replace_bootstrap="1"
      fi
      ;;
  esac

  if [[ "${replace_bootstrap}" == "1" ]]; then
    echo "[INFO] Forcing replace: ${BOOTSTRAP_STATE_ADDRESS}"
    append_replace_target "${BOOTSTRAP_STATE_ADDRESS}"
  else
    echo "[INFO] Skipping forced bootstrap replace (API reachable)"
  fi
}

pipeline_post_init() {
  local endpoint=""

  endpoint="$(extract_talos_endpoint)"
  if [[ -z "${endpoint}" ]]; then
    echo "[WARN] Talos endpoint not found in tfvars; skipping bootstrap state repair"
    return 0
  fi

  if ! is_talos_api_reachable "${endpoint}"; then
    echo "[INFO] Talos API ${endpoint}:6443 is unreachable; skipping bootstrap import repair"
    return 0
  fi

  repair_machine_secrets_state "${endpoint}"

  if state_has_address "${BOOTSTRAP_STATE_ADDRESS}"; then
    return 0
  fi

  echo "[WARN] ${BOOTSTRAP_STATE_ADDRESS} missing from state while API is reachable; importing it"
  if "${EXEC_SCRIPT}" import -input=false -var-file "${TFVARS_PATH}" "${BOOTSTRAP_STATE_ADDRESS}" "${BOOTSTRAP_STATE_ID}"; then
    echo "[INFO] Imported ${BOOTSTRAP_STATE_ADDRESS} into state"
    return 0
  fi

  echo "[ERR] Failed to import ${BOOTSTRAP_STATE_ADDRESS}; manual recovery required" >&2
  exit 1
}

PIPELINE_ARGS=("$@")

# shellcheck source=../../../scripts/terraform/resolve_config_by_id.sh
source "${PIPELINE_SCRIPT_ROOT}/resolve_config_by_id.sh"
# shellcheck source=/dev/null
source "${PIPELINE_SCRIPT_ROOT}/terraform_backend_init.sh"

SLICE_CONFIG_ID="$(homelab_config_id_from_terraform_dir "${ROOT_DIR}" "${TERRAFORM_DIR}")"
DEFAULT_SLICE_TFVARS="$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "${SLICE_CONFIG_ID}")"
DEFAULT_BACKEND="$(homelab_resolve_config_path "${TFVARS_HOME_DIR}" "terraform/minio.backend")"

TFVARS_PATH="${TALOS_APP_TFVARS:-${DEFAULT_SLICE_TFVARS}}"
BACKEND_CONFIG_PATH="${TALOS_APP_BACKEND:-${DEFAULT_BACKEND}}"

TFVARS_ARG=""
BACKEND_ARG=""
ARGS=("${PIPELINE_ARGS[@]}")
while [[ ${#ARGS[@]} -gt 0 ]]; do
  case "${ARGS[0]}" in
    --tfvars)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --tfvars requires a path" >&2
        exit 2
      }
      TFVARS_ARG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    --backend)
      [[ ${#ARGS[@]} -ge 2 ]] || {
        echo "[ERR] --backend requires a path" >&2
        exit 2
      }
      BACKEND_ARG="${ARGS[1]}"
      ARGS=("${ARGS[@]:2}")
      ;;
    -h | --help)
      cat <<USAGE
Usage: ${ENTRYPOINT_RELATIVE} [--tfvars <path>] [--backend <path>] [tfvars_path] [backend_path]

Runs the ${STAGE_NAME} pipeline for ${SERVICE_NAME}.
USAGE
      exit 0
      ;;
    *)
      if [[ "${ARGS[0]}" == --* ]]; then
        echo "[ERR] Unknown option: ${ARGS[0]}" >&2
        exit 2
      fi
      if [[ -z "${TFVARS_ARG}" ]]; then
        TFVARS_ARG="${ARGS[0]}"
      elif [[ -z "${BACKEND_ARG}" ]]; then
        BACKEND_ARG="${ARGS[0]}"
      else
        echo "[ERR] Unexpected argument: ${ARGS[0]}" >&2
        exit 2
      fi
      ARGS=("${ARGS[@]:1}")
      ;;
  esac
done

[[ -n "${TFVARS_ARG}" ]] && TFVARS_PATH="${TFVARS_ARG}"
[[ -n "${BACKEND_ARG}" ]] && BACKEND_CONFIG_PATH="${BACKEND_ARG}"
[[ -n "${TFVARS_FILE:-}" ]] && TFVARS_PATH="${TFVARS_FILE}"
[[ -n "${BACKEND_FILE:-}" ]] && BACKEND_CONFIG_PATH="${BACKEND_FILE}"

if [[ -z "${TFVARS_PATH}" || ! -f "${TFVARS_PATH}" ]]; then
  echo "[ERR] Missing TFVARS file: ${TFVARS_PATH}" >&2
  exit 1
fi
if [[ "$(homelab_terraform_state_mode)" == "s3" \
  && ( -z "${BACKEND_CONFIG_PATH}" || ! -f "${BACKEND_CONFIG_PATH}" ) ]]; then
  echo "[ERR] Missing backend config file: ${BACKEND_CONFIG_PATH}" >&2
  exit 1
fi
if [[ ! -x "${EXEC_SCRIPT}" ]]; then
  echo "[ERR] Missing helper script: ${EXEC_SCRIPT}" >&2
  exit 1
fi

echo "TFVARS file: ${TFVARS_PATH}"
echo "Backend config: ${BACKEND_CONFIG_PATH}"

if declare -F pipeline_pre_terraform > /dev/null; then
  pipeline_pre_terraform
fi

cd "${TERRAFORM_DIR}"

echo "[STEP] terraform init (${STAGE_NAME})"
# Route through the shared mode-aware helper (local self-init / S3 + auto
# state migration). BACKEND_CONFIG is what the helper reads in S3 mode.
BACKEND_CONFIG="${BACKEND_CONFIG_PATH}"
if ! homelab_terraform_init "${TERRAFORM_DIR}"; then
  echo "[ERR] terraform init failed" >&2
  exit 1
fi

if declare -F pipeline_post_init > /dev/null; then
  pipeline_post_init
fi

PLAN_ARGS=(-input=false -var-file "${TFVARS_PATH}")
PLAN_ARGS+=("${PLAN_ARGS_EXTRA[@]}")

APPLY_ARGS=(-input=false -auto-approve -var-file "${TFVARS_PATH}")
APPLY_ARGS+=("${APPLY_ARGS_EXTRA[@]}")

echo "[STAGE] ${STAGE_NAME} plan"
if ! "${EXEC_SCRIPT}" plan "${PLAN_ARGS[@]}"; then
  echo "[ERR] terraform plan (${STAGE_NAME}) failed" >&2
  exit 1
fi

echo "[STAGE] ${STAGE_NAME} apply"
if ! "${EXEC_SCRIPT}" apply "${APPLY_ARGS[@]}"; then
  echo "[ERR] terraform apply (${STAGE_NAME}) failed" >&2
  exit 1
fi

echo "[DONE] ${STAGE_NAME} apply complete."
