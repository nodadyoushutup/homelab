#!/usr/bin/env bash
set -euo pipefail

bool_true() {
  local value
  value="${1:-}"
  value="${value,,}"
  [[ "${value}" == "1" || "${value}" == "true" || "${value}" == "yes" || "${value}" == "on" ]]
}

trim_trailing_slash() {
  local value="${1:-}"
  value="${value%/}"
  echo "${value}"
}

build_runner_token_endpoint() {
  local runner_url="$1"
  local action="$2"
  local api_base="$3"
  local path=""

  path="${runner_url#https://github.com/}"
  path="${path#http://github.com/}"
  path="$(trim_trailing_slash "${path}")"

  if [[ -z "${path}" || "${path}" == "${runner_url}" ]]; then
    return 1
  fi

  if [[ "${path}" == */* ]]; then
    echo "${api_base}/repos/${path}/actions/runners/${action}"
    return 0
  fi

  echo "${api_base}/orgs/${path}/actions/runners/${action}"
}

request_runner_token() {
  local runner_url="$1"
  local action="$2"
  local access_token="$3"
  local api_base="$4"
  local endpoint
  local response
  local token

  endpoint="$(build_runner_token_endpoint "${runner_url}" "${action}" "${api_base}")" || return 1

  response="$(curl -fsSL -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${access_token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${endpoint}")" || return 1

  token="$(jq -r '.token // empty' <<<"${response}")"
  [[ -n "${token}" ]] || return 1

  echo "${token}"
}

cd "${RUNNER_HOME:-/home/runner/actions-runner}"
touch /tmp/gha-runner-ready

if [[ -n "${HARBOR_BUILD_TMP_PARENT:-}" ]]; then
  mkdir -p "${HARBOR_BUILD_TMP_PARENT}"
fi

runner_url="${GH_RUNNER_URL:-}"
runner_token="${GH_RUNNER_TOKEN:-}"
runner_access_token="${GH_RUNNER_ACCESS_TOKEN:-}"
github_api_url="$(trim_trailing_slash "${GH_API_URL:-https://api.github.com}")"

if [[ -z "${runner_url}" || "${runner_url}" == "__SET_ME__" ]]; then
  echo "[INFO] GH_RUNNER_URL is not set to a usable value. Staying in standby mode."
  exec sleep infinity
fi

if [[ -n "${runner_access_token}" && "${runner_access_token}" != "__SET_ME__" ]]; then
  echo "[INFO] Requesting fresh GitHub Actions runner registration token from API."
  runner_token="$(request_runner_token "${runner_url}" "registration-token" "${runner_access_token}" "${github_api_url}" || true)"
fi

if [[ -z "${runner_token}" || "${runner_token}" == "__SET_ME__" ]]; then
  echo "[INFO] GH_RUNNER_TOKEN is not set and GH_RUNNER_ACCESS_TOKEN could not mint a registration token. Staying in standby mode."
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

# Restarts of an ephemeral runner reuse the container's writable layer, so a
# stale .runner from the prior registration is still on disk; config.sh then
# refuses to re-register ("Cannot configure the runner because it is already
# configured"). --replace only handles the GitHub-side conflict, not the local
# file. Try a graceful deregister first, then force-remove the leftover state.
if [[ -f .runner ]]; then
  echo "[INFO] Stale runner registration found on disk; cleaning up before re-config."
  remove_token=""
  if [[ -n "${runner_access_token}" && "${runner_access_token}" != "__SET_ME__" ]]; then
    remove_token="$(request_runner_token "${runner_url}" "remove-token" "${runner_access_token}" "${github_api_url}" || true)"
  fi
  if [[ -n "${remove_token}" ]]; then
    ./config.sh remove --unattended --token "${remove_token}" || true
  fi
  rm -f .runner .credentials .credentials_rsaparams .path .env
fi

./config.sh "${config_args[@]}"

cleanup() {
  local remove_token="${GH_RUNNER_REMOVE_TOKEN:-}"

  if [[ ! -f .runner ]]; then
    return 0
  fi

  if [[ -z "${remove_token}" && -n "${runner_access_token}" && "${runner_access_token}" != "__SET_ME__" ]]; then
    remove_token="$(request_runner_token "${runner_url}" "remove-token" "${runner_access_token}" "${github_api_url}" || true)"
  fi

  if [[ -n "${remove_token}" ]]; then
    ./config.sh remove --unattended --token "${remove_token}" || true
  fi
}

trap cleanup EXIT INT TERM

exec ./run.sh
