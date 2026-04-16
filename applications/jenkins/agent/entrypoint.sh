#!/usr/bin/env sh
set -eu

log() {
  printf '[agent-entrypoint] %s\n' "$*"
}

fail() {
  printf '[agent-entrypoint] ERROR: %s\n' "$*" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl is required but not available in the image"

JENKINS_URL="${JENKINS_URL:-}"
[ -n "$JENKINS_URL" ] || fail "JENKINS_URL is not set"

AGENT_NAME="${JENKINS_AGENT_NAME:-}"
if [ -z "$AGENT_NAME" ]; then
  log "JENKINS_AGENT_NAME not set; skipping auto-registration and idling"
  while :; do sleep 3600; done
fi

trimmed_url="${JENKINS_URL%/}"
health_endpoint="${JENKINS_HEALTH_ENDPOINT:-${trimmed_url}/whoAmI/api/json?tree=authenticated}"
health_delay="${JENKINS_HEALTH_DELAY_SECONDS:-5}"
health_timeout="${JENKINS_HEALTH_TIMEOUT_SECONDS:-5}"
health_attempts="${JENKINS_HEALTH_MAX_ATTEMPTS:-60}"

fetch_health() {
  if [ "${JENKINS_HEALTH_INSECURE:-0}" = "1" ]; then
    curl --silent --show-error --fail --max-time "$health_timeout" --insecure "$health_endpoint"
  else
    curl --silent --show-error --fail --max-time "$health_timeout" "$health_endpoint"
  fi
}

log "Waiting for Jenkins at ${health_endpoint}"

i=1
while [ "$i" -le "$health_attempts" ]; do
  response="$(fetch_health 2>/dev/null || true)"
  if [ -n "$response" ] && printf '%s' "$response" | grep -q '"authenticated"[[:space:]]*:[[:space:]]*true'; then
    log "Jenkins is healthy"
    break
  fi
  log "Attempt ${i}/${health_attempts}: Jenkins not ready, sleeping ${health_delay}s"
  i=$((i + 1))
  sleep "$health_delay"
done

if [ "$i" -gt "$health_attempts" ]; then
  fail "Timed out waiting for Jenkins at ${health_endpoint}"
fi

# Mirrors export-agent-secret.groovy sanitisation so we look up the correct file
sanitised_name="$(printf '%s' "$AGENT_NAME" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
secrets_dir="${JENKINS_SECRETS_DIR:-${HOME:-/home/jenkins}/.jenkins}"
secret_file="${secrets_dir}/${sanitised_name}.secret"
alt_secret_file=""
[ "$sanitised_name" = "$AGENT_NAME" ] || alt_secret_file="${secrets_dir}/${AGENT_NAME}.secret"
secret_delay="${JENKINS_SECRET_DELAY_SECONDS:-2}"
secret_attempts="${JENKINS_SECRET_MAX_ATTEMPTS:-120}"
secret_path=""

log "Waiting for agent secret at ${secret_file}"

check_secret() {
  for candidate in "$secret_file" "$alt_secret_file"; do
    [ -n "$candidate" ] || continue
    [ -s "$candidate" ] || continue
    secret_path="$candidate"
    return 0
  done
  return 1
}

j=1
while [ "$j" -le "$secret_attempts" ]; do
  if check_secret; then
    break
  fi
  log "Attempt ${j}/${secret_attempts}: secret not yet available, sleeping ${secret_delay}s"
  j=$((j + 1))
  sleep "$secret_delay"
done

if [ -z "$secret_path" ]; then
  fail "Timed out waiting for agent secret file"
fi

log "Using secret file ${secret_path}"
secret_value="$(tr -d '\r\n' < "$secret_path")"
[ -n "$secret_value" ] || fail "Secret file '${secret_path}' is empty"

export JENKINS_SECRET="$secret_value"
log "Launching Jenkins agent"
exec jenkins-agent "$@"
