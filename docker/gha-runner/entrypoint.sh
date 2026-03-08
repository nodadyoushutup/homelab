#!/usr/bin/env bash
set -euo pipefail

bool_true() {
  local value
  value="${1:-}"
  value="${value,,}"
  [[ "${value}" == "1" || "${value}" == "true" || "${value}" == "yes" || "${value}" == "on" ]]
}

cd "${RUNNER_HOME:-/home/runner/actions-runner}"
touch /tmp/gha-runner-ready

runner_url="${GH_RUNNER_URL:-}"
runner_token="${GH_RUNNER_TOKEN:-}"

if [[ -z "${runner_url}" || -z "${runner_token}" || "${runner_url}" == "__SET_ME__" || "${runner_token}" == "__SET_ME__" ]]; then
  echo "[INFO] GH_RUNNER_URL and GH_RUNNER_TOKEN are not set to usable values. Staying in standby mode."
  exec sleep infinity
fi

runner_name="${GH_RUNNER_NAME:-$(hostname)}"
runner_workdir="${GH_RUNNER_WORKDIR:-_work}"
runner_labels="${GH_RUNNER_LABELS:-self-hosted,linux}"

config_args=(
  --unattended
  --replace
  --url "${runner_url}"
  --token "${runner_token}"
  --name "${runner_name}"
  --work "${runner_workdir}"
)

if [[ -n "${runner_labels}" ]]; then
  config_args+=(--labels "${runner_labels}")
fi

if bool_true "${GH_RUNNER_EPHEMERAL:-true}"; then
  config_args+=(--ephemeral)
fi

if bool_true "${GH_RUNNER_DISABLEUPDATE:-true}"; then
  config_args+=(--disableupdate)
fi

./config.sh "${config_args[@]}"

cleanup() {
  if [[ -n "${GH_RUNNER_REMOVE_TOKEN:-}" && -f .runner ]]; then
    ./config.sh remove --unattended --token "${GH_RUNNER_REMOVE_TOKEN}" || true
  fi
}

trap cleanup EXIT INT TERM

exec ./run.sh
