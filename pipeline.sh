#!/usr/bin/env bash

if [[ -z "${BASH_VERSION:-}" ]]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'pipeline.sh: %s\n' "$*" >&2
  exit 1
}

prompt_select() {
  local prompt="$1"
  shift
  local -a options=("$@")

  if [[ ${#options[@]} -eq 0 ]]; then
    die "no options available for: ${prompt}"
  fi

  if [[ ${#options[@]} -eq 1 ]]; then
    printf '%s (only option)\n' "${prompt}"
    printf '  1) %s\n' "${options[0]}"
    REPLY=1
  else
    printf '%s\n' "${prompt}"
    local i=1
    local opt
    for opt in "${options[@]}"; do
      printf '  %d) %s\n' "$i" "$opt"
      i=$((i + 1))
    done
    printf '  q) quit\n'
    while true; do
      printf 'Choice: '
      if ! IFS= read -r REPLY; then
        printf '\n'
        exit 130
      fi
      if [[ "${REPLY}" == "q" || "${REPLY}" == "Q" ]]; then
        exit 0
      fi
      if [[ "${REPLY}" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#options[@]} )); then
        break
      fi
      printf 'Enter a number from 1 to %d, or q to quit.\n' "${#options[@]}"
    done
  fi

  SELECTED="${options[$((REPLY - 1))]}"
}

discover_network_services() {
  local svc_dir
  local -a services=()
  for svc_dir in "${ROOT_DIR}"/terraform/components/network/*/pipeline; do
    [[ -d "${svc_dir}" ]] || continue
    services+=("$(basename "$(dirname "${svc_dir}")")")
  done
  if [[ ${#services[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

discover_network_slices() {
  local service="$1"
  local pipeline_dir="${ROOT_DIR}/terraform/components/network/${service}/pipeline"
  local script
  local -a slices=()

  [[ -d "${pipeline_dir}" ]] || return 1

  for script in "${pipeline_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    slices+=("$(basename "${script}" .sh)")
  done

  if [[ ${#slices[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${slices[@]}" | LC_ALL=C sort
}

discover_remote_services() {
  local svc_dir
  local -a services=()
  for svc_dir in "${ROOT_DIR}"/terraform/components/remote/*/pipeline; do
    [[ -d "${svc_dir}" ]] || continue
    services+=("$(basename "$(dirname "${svc_dir}")")")
  done
  if [[ ${#services[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

discover_remote_slices() {
  local service="$1"
  local pipeline_dir="${ROOT_DIR}/terraform/components/remote/${service}/pipeline"
  local script
  local -a slices=()

  [[ -d "${pipeline_dir}" ]] || return 1

  for script in "${pipeline_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    slices+=("$(basename "${script}" .sh)")
  done

  if [[ ${#slices[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${slices[@]}" | LC_ALL=C sort
}

discover_cluster_services() {
  local svc_dir
  local -a services=()
  for svc_dir in "${ROOT_DIR}"/terraform/components/cluster/*/pipeline; do
    [[ -d "${svc_dir}" ]] || continue
    services+=("$(basename "$(dirname "${svc_dir}")")")
  done
  if [[ ${#services[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

discover_cluster_slices() {
  local service="$1"
  local pipeline_dir="${ROOT_DIR}/terraform/components/cluster/${service}/pipeline"
  local script
  local -a slices=()

  [[ -d "${pipeline_dir}" ]] || return 1

  for script in "${pipeline_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    slices+=("$(basename "${script}" .sh)")
  done

  if [[ ${#slices[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${slices[@]}" | LC_ALL=C sort
}

discover_swarm_services() {
  local svc_dir
  local -a services=()
  for svc_dir in "${ROOT_DIR}"/terraform/components/swarm/*/pipeline; do
    [[ -d "${svc_dir}" ]] || continue
    services+=("$(basename "$(dirname "${svc_dir}")")")
  done
  if [[ ${#services[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${services[@]}" | LC_ALL=C sort -u
}

discover_swarm_slices() {
  local service="$1"
  local pipeline_dir="${ROOT_DIR}/terraform/components/swarm/${service}/pipeline"
  local script
  local -a slices=()

  [[ -d "${pipeline_dir}" ]] || return 1

  for script in "${pipeline_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    slices+=("$(basename "${script}" .sh)")
  done

  if [[ ${#slices[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${slices[@]}" | LC_ALL=C sort
}

discover_runner_pools() {
  local pool_dir
  local -a pools=()
  for pool_dir in "${ROOT_DIR}"/terraform/components/runners/*/pipeline; do
    [[ -d "${pool_dir}" ]] || continue
    pools+=("$(basename "$(dirname "${pool_dir}")")")
  done
  if [[ ${#pools[@]} -eq 0 ]]; then
    return 1
  fi
  printf '%s\n' "${pools[@]}" | LC_ALL=C sort
}

discover_runner_slices() {
  local pool="$1"
  local pool_dir="${ROOT_DIR}/terraform/components/runners/${pool}/pipeline"
  local script
  local -a slices=()

  [[ -d "${pool_dir}" ]] || return 1

  for script in "${pool_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    slices+=("$(basename "${script}" .sh)")
  done

  if [[ ${#slices[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${slices[@]}" | LC_ALL=C sort
}

discover_simple_pipelines() {
  local rel_dir="$1"
  local abs_dir="${ROOT_DIR}/${rel_dir}"
  local script
  local -a names=()

  [[ -d "${abs_dir}" ]] || return 1

  for script in "${abs_dir}"/*.sh; do
    [[ -f "${script}" ]] || continue
    names+=("$(basename "${script}" .sh)")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${names[@]}" | LC_ALL=C sort
}

run_network_pipeline() {
  local service="$1"
  local slice="$2"
  local script="${ROOT_DIR}/terraform/components/network/${service}/pipeline/${slice}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

run_remote_pipeline() {
  local service="$1"
  local slice="$2"
  local script="${ROOT_DIR}/terraform/components/remote/${service}/pipeline/${slice}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

run_cluster_pipeline() {
  local service="$1"
  local slice="$2"
  local script="${ROOT_DIR}/terraform/components/cluster/${service}/pipeline/${slice}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

run_swarm_pipeline() {
  local service="$1"
  local slice="$2"
  local script="${ROOT_DIR}/terraform/components/swarm/${service}/pipeline/${slice}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

run_runner_pipeline() {
  local pool="$1"
  local slice="$2"
  local script="${ROOT_DIR}/terraform/components/runners/${pool}/pipeline/${slice}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

run_simple_pipeline() {
  local rel_dir="$1"
  local name="$2"
  local script="${ROOT_DIR}/${rel_dir}/${name}.sh"
  [[ -x "${script}" || -f "${script}" ]] || die "missing pipeline script: ${script}"
  exec bash "${script}" "$@"
}

main() {
  local -a categories=()
  local category service slice name
  local -a services=() slices=() names=()

  if mapfile -t network_services < <(discover_network_services); then
    categories+=("Network stacks")
  fi
  if mapfile -t remote_services < <(discover_remote_services); then
    categories+=("Remote stacks")
  fi
  if mapfile -t cluster_services < <(discover_cluster_services); then
    categories+=("Cluster stacks")
  fi
  if mapfile -t services < <(discover_swarm_services); then
    categories+=("Swarm stacks")
  fi
  if mapfile -t pools < <(discover_runner_pools); then
    categories+=("Runner pools")
  fi
  if mapfile -t names < <(discover_simple_pipelines "scripts/docker"); then
    categories+=("Application image builds")
  fi
  if mapfile -t packer_names < <(discover_simple_pipelines "packer/pipeline"); then
    categories+=("Packer image builds")
  fi

  [[ ${#categories[@]} -gt 0 ]] || die "no pipeline entrypoints found under ${ROOT_DIR}"

  prompt_select "Select pipeline category:" "${categories[@]}"
  category="${SELECTED}"

  case "${category}" in
    "Network stacks")
      mapfile -t network_services < <(discover_network_services)
      prompt_select "Select network stack:" "${network_services[@]}"
      service="${SELECTED}"

      mapfile -t slices < <(discover_network_slices "${service}")
      prompt_select "Select slice for ${service}:" "${slices[@]}"
      slice="${SELECTED}"

      printf '\nRunning terraform/components/network/%s/pipeline/%s.sh\n\n' "${service}" "${slice}"
      run_network_pipeline "${service}" "${slice}" "$@"
      ;;
    "Remote stacks")
      mapfile -t remote_services < <(discover_remote_services)
      prompt_select "Select remote stack:" "${remote_services[@]}"
      service="${SELECTED}"

      mapfile -t slices < <(discover_remote_slices "${service}")
      prompt_select "Select slice for ${service}:" "${slices[@]}"
      slice="${SELECTED}"

      printf '\nRunning terraform/components/remote/%s/pipeline/%s.sh\n\n' "${service}" "${slice}"
      run_remote_pipeline "${service}" "${slice}" "$@"
      ;;
    "Cluster stacks")
      mapfile -t cluster_services < <(discover_cluster_services)
      prompt_select "Select cluster stack:" "${cluster_services[@]}"
      service="${SELECTED}"

      mapfile -t slices < <(discover_cluster_slices "${service}")
      prompt_select "Select slice for ${service}:" "${slices[@]}"
      slice="${SELECTED}"

      printf '\nRunning terraform/components/cluster/%s/pipeline/%s.sh\n\n' "${service}" "${slice}"
      run_cluster_pipeline "${service}" "${slice}" "$@"
      ;;
    "Swarm stacks")
      mapfile -t services < <(discover_swarm_services)
      prompt_select "Select Swarm stack:" "${services[@]}"
      service="${SELECTED}"

      mapfile -t slices < <(discover_swarm_slices "${service}")
      prompt_select "Select slice for ${service}:" "${slices[@]}"
      slice="${SELECTED}"

      printf '\nRunning terraform/components/swarm/%s/pipeline/%s.sh\n\n' "${service}" "${slice}"
      run_swarm_pipeline "${service}" "${slice}" "$@"
      ;;
    "Runner pools")
      mapfile -t pools < <(discover_runner_pools)
      prompt_select "Select runner pool:" "${pools[@]}"
      service="${SELECTED}"

      mapfile -t slices < <(discover_runner_slices "${service}")
      prompt_select "Select slice for ${service}:" "${slices[@]}"
      slice="${SELECTED}"

      printf '\nRunning terraform/components/runners/%s/pipeline/%s.sh\n\n' "${service}" "${slice}"
      run_runner_pipeline "${service}" "${slice}" "$@"
      ;;
    "Application image builds")
      mapfile -t names < <(discover_simple_pipelines "scripts/docker")
      prompt_select "Select application pipeline:" "${names[@]}"
      name="${SELECTED}"

      printf '\nRunning scripts/docker/%s.sh\n\n' "${name}"
      run_simple_pipeline "scripts/docker" "${name}" "$@"
      ;;
    "Packer image builds")
      mapfile -t names < <(discover_simple_pipelines "packer/pipeline")
      prompt_select "Select packer pipeline:" "${names[@]}"
      name="${SELECTED}"

      printf '\nRunning packer/pipeline/%s.sh\n\n' "${name}"
      run_simple_pipeline "packer/pipeline" "${name}" "$@"
      ;;
    *)
      die "unknown category: ${category}"
      ;;
  esac
}

main "$@"
