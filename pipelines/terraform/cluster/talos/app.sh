#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
PIPELINE_SCRIPT_ROOT="${ROOT_DIR}/scripts/terraform"
source "${PIPELINE_SCRIPT_ROOT}/load_root_env.sh"

SERVICE_NAME="talos"
STAGE_NAME="Talos cluster"
ENTRYPOINT_RELATIVE="pipelines/terraform/cluster/talos/app.sh"
TERRAFORM_DIR="${ROOT_DIR}/terraform/cluster/talos/app"
TFVARS_HOME_DIR="${TFVARS_HOME_DIR:-${TFVARS_DIR:-/mnt/eapp/config}}"
DEFAULT_TFVARS_FILE="${DEFAULT_TFVARS_FILE:-${TFVARS_HOME_DIR}/talos/app.tfvars}"
DEFAULT_BACKEND_FILE="${DEFAULT_BACKEND_FILE:-${TFVARS_HOME_DIR}/minio.backend.hcl}"

PLAN_ARGS_EXTRA=()
APPLY_ARGS_EXTRA=()
declare -A REPLACE_TARGET_SEEN=()
declare -A NODE_TARGET_IP=()
declare -A READY_IPS=()
ALL_NODE_TARGETS=()
CONTROL_PLANE_TARGET=""
CONTROL_PLANE_IP=""
BOOTSTRAP_STATE_ADDRESS="talos_machine_bootstrap.cluster"
BOOTSTRAP_STATE_ID="machine_bootstrap"
KUBECONFIG_STATE_ADDRESS="talos_cluster_kubeconfig.cluster"

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

extract_talos_endpoint() {
  extract_tfvar_string "endpoint"
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

extract_kubeconfig_output_path() {
  local from_tfvars=""
  local cluster_name=""
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

  if "${EXEC_SCRIPT}" state show -no-color "${BOOTSTRAP_STATE_ADDRESS}" >/dev/null 2>&1; then
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

source "${PIPELINE_SCRIPT_ROOT}/swarm_pipeline.sh"
