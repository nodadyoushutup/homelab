#!/bin/bash
set -euo pipefail

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }
trap 'die "failed at line $LINENO"' ERR

# --- Config / Overrides ---
INSTALL_DIR="/usr/local/bin"
BIN="terraform"
TF_VERSION="${TF_VERSION:-}"              # e.g. 1.9.5 ; empty = use APT if available, or latest on fallback

# --- Non-interactive apt/dpkg ---
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
APT_OPTS=(-y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")
PHASE_OPTS=(-o APT::Get::Always-Include-Phased-Updates=true)

# --- Preflight ---
command -v curl >/dev/null 2>&1 || die "curl is required (apt-get install -y curl)."
command -v sha256sum >/dev/null 2>&1 || die "sha256sum (coreutils) required."
command -v unzip >/dev/null 2>&1 || { log "Installing unzip prerequisite..."; sudo apt-get update -y -q; sudo apt-get install "${APT_OPTS[@]}" unzip >/dev/null; }

ARCH_DEB="$(dpkg --print-architecture || echo unknown)"   # amd64, arm64, armhf, ...
case "$ARCH_DEB" in
  amd64) REL_ARCH="amd64" ;;
  arm64) REL_ARCH="arm64" ;;
  armhf|armel) REL_ARCH="arm" ;;
  *) warn "Unsupported arch for direct releases: ${ARCH_DEB}. APT may still work."; REL_ARCH="" ;;
esac

OS_CODENAME="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}" || true)"

have_url() { curl -fsSL --retry 3 --max-time 10 -o /dev/null "$1"; }

choose_repo_codename() {
  local c
  for c in "${OS_CODENAME:-}" noble jammy focal; do
    [[ -n "$c" ]] || continue
    have_url "https://apt.releases.hashicorp.com/dists/${c}/Release" && { echo "$c"; return; }
  done
  echo ""   # signal "no apt repo for this codename"
}

latest_release_version() {
  # Get latest from releases index (jq if present; otherwise grep)
  if command -v jq >/dev/null 2>&1; then
    curl -fsSL --retry 3 https://releases.hashicorp.com/terraform/index.json \
      | jq -r '.versions | keys | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".")|map(tonumber)) | last'
  else
    curl -fsSL --retry 3 https://releases.hashicorp.com/terraform/index.json \
      | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -V | tail -n1
  fi
}

install_via_apt() {
  log "Attempting APT install for HashiCorp Terraform..."

  sudo apt-get update -y -q
  sudo apt-get install "${APT_OPTS[@]}" ca-certificates gnupg lsb-release apt-transport-https >/dev/null

  # keyring
  sudo install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/hashicorp.gpg ]]; then
    curl -fsSL --retry 3 https://apt.releases.hashicorp.com/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp.gpg
    sudo chmod a+r /etc/apt/keyrings/hashicorp.gpg
  fi

  local CODENAME; CODENAME="$(choose_repo_codename)"
  if [[ -z "$CODENAME" ]]; then
    warn "No suitable HashiCorp APT codename found; will fall back to direct download."
    return 1
  fi

  echo "deb [arch=${ARCH_DEB} signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null

  sudo apt-get update -y -q

  # If a specific version is requested, prefer direct release install instead of APT
  if [[ -n "${TF_VERSION}" ]]; then
    warn "TF_VERSION specified (${TF_VERSION}); skipping APT (will install from releases)."
    return 1
  fi

  sudo apt-get install "${APT_OPTS[@]}" "${PHASE_OPTS[@]}" terraform && return 0

  warn "APT install failed; will fall back to direct download."
  return 1
}

install_via_releases() {
  local ver="${TF_VERSION:-}"
  if [[ -z "$ver" ]]; then
    log "Discovering latest Terraform version from releases…"
    ver="$(latest_release_version)"
    [[ -n "$ver" ]] || die "Could not determine latest Terraform version."
  fi

  [[ -n "$REL_ARCH" ]] || die "Direct releases do not support detected arch '${ARCH_DEB}'."

  local base="https://releases.hashicorp.com/terraform/${ver}"
  local zip="terraform_${ver}_linux_${REL_ARCH}.zip"
  local url="${base}/${zip}"
  local sums="${base}/terraform_${ver}_SHA256SUMS"

  # Idempotency: skip if already that version
  if command -v "${BIN}" >/dev/null 2>&1; then
    set +e
    CURRENT="$(${BIN} version 2>/dev/null | head -n1 | sed -n 's/^Terraform v\([0-9.]\+\).*/\1/p')"
    set -e
    if [[ "${CURRENT}" == "${ver}" ]]; then
      log "Terraform ${ver} already installed at $(command -v ${BIN}); nothing to do."
      return 0
    else
      log "Installed Terraform: ${CURRENT:-unknown}, target: ${ver}"
    fi
  fi

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  log "Downloading ${url}…"
  curl -fL --retry 3 -o "${tmp}/${zip}" "${url}"

  log "Verifying SHA256…"
  curl -fL --retry 3 -o "${tmp}/SHA256SUMS" "${sums}"
  local expected
  expected="$(grep " ${zip}\$" "${tmp}/SHA256SUMS" | awk '{print $1}')" || true
  [[ -n "$expected" ]] || die "No checksum entry for ${zip}"
  echo "${expected}  ${tmp}/${zip}" | sha256sum -c - >/dev/null

  log "Extracting and installing to ${INSTALL_DIR}/${BIN}…"
  unzip -q -o "${tmp}/${zip}" -d "${tmp}"
  sudo install -m 0755 -o root -g root -T "${tmp}/${BIN}" "${INSTALL_DIR}/${BIN}"

  log "Installed $( "${INSTALL_DIR}/${BIN}" version | head -n1 )"
}

install_completions_best_effort() {
  if ! command -v "${BIN}" >/dev/null 2>&1; then
    return 0
  fi

  # Have Terraform drop its user-level config (best effort)
  "${BIN}" -install-autocomplete >/dev/null 2>&1 || true

  local terraform_path completion_cmd
  terraform_path="$(command -v "${BIN}")"
  printf -v completion_cmd 'complete -C %q terraform' "${terraform_path}"

  if [[ -d /etc/bash_completion.d ]]; then
    log "Installing bash completion to /etc/bash_completion.d/terraform"
    printf '%s\n' "${completion_cmd}" \
      | sudo tee /etc/bash_completion.d/terraform >/dev/null || true
  fi

  if [[ -d /usr/share/zsh/vendor-completions ]]; then
    log "Installing zsh completion shim to /usr/share/zsh/vendor-completions/_terraform"
    sudo tee /usr/share/zsh/vendor-completions/_terraform >/dev/null <<EOF || true
#compdef terraform
autoload -U +X bashcompinit && bashcompinit
${completion_cmd}
EOF
  fi
}

# --- Try APT first (unless a specific version is requested), else fall back ---
if install_via_apt; then
  log "Terraform installed via APT: $(${BIN} version | head -n1)"
else
  install_via_releases
fi

install_completions_best_effort

log "Done."