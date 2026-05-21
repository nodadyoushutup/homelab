#!/usr/bin/env bash
# Refresh package indexes, upgrade installed packages, then start an Ubuntu release
# upgrade (e.g. 25.10 → 26.04 LTS) via do-release-upgrade.
#
# Typical flow (plan for two reboots):
#   1. Run this script through package upgrades (or stop with --packages-only).
#   2. Reboot if /var/run/reboot-required exists (often after kernel updates).
#   3. Run again without --packages-only, or use --release-only after reboot.
#   4. Reboot again when do-release-upgrade finishes.
#
# Usage:
#   scripts/misc/ubuntu_release_upgrade.sh              # interactive apt; then release UI
#   scripts/misc/ubuntu_release_upgrade.sh -y           # non-interactive apt steps
#   scripts/misc/ubuntu_release_upgrade.sh --packages-only -y
#   scripts/misc/ubuntu_release_upgrade.sh --release-only
#   scripts/misc/ubuntu_release_upgrade.sh --reboot     # reboot after apt if required
#
# Environment:
#   RELEASE_UPGRADE_FRONTEND   default: DistUpgradeViewKDE (set DistUpgradeViewGtk3 on GNOME)
#   RELEASE_UPGRADE_ALLOW_THIRD_PARTY=1  passes --allow-third-party to do-release-upgrade

set -euo pipefail

log() {
  printf '[ubuntu-release-upgrade] %s\n' "$*"
}

die() {
  log "error: $*"
  exit 1
}

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF

Options:
  -y, --yes           Run apt steps non-interactively (apt-get -y).
  --packages-only     apt update + full-upgrade only; do not start release upgrade.
  --release-only      Skip apt steps; only run do-release-upgrade (after reboot).
  --reboot            If reboot is required after package upgrades, reboot before
                      starting the release upgrade (sudo reboot).
  -h, --help          Show this help.
EOF
}

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  . /etc/os-release
else
  die "missing /etc/os-release — is this Ubuntu?"
fi

if [[ "${ID:-}" != ubuntu ]]; then
  die "this script targets Ubuntu (ID=${ID:-unknown})"
fi

APT_YES=0
PACKAGES_ONLY=0
RELEASE_ONLY=0
REBOOT_AFTER_APT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      APT_YES=1
      shift
      ;;
    --packages-only)
      PACKAGES_ONLY=1
      shift
      ;;
    --release-only)
      RELEASE_ONLY=1
      shift
      ;;
    --reboot)
      REBOOT_AFTER_APT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1 (try --help)"
      ;;
  esac
done

if [[ "$PACKAGES_ONLY" -eq 1 && "$RELEASE_ONLY" -eq 1 ]]; then
  die "use either --packages-only or --release-only, not both"
fi

SUDO=()
if [[ "$(id -u)" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    die "root or sudo required"
  fi
  SUDO=(sudo)
fi

APT_GET=("${SUDO[@]}" apt-get)
export DEBIAN_FRONTEND=noninteractive

apt_args() {
  if [[ "$APT_YES" -eq 1 ]]; then
    printf '%s\n' -y
  fi
}

pending_upgradable_count() {
  "${APT_GET[@]}" update -qq >/dev/null 2>&1 || true
  local n
  n="$("${APT_GET[@]}" -s upgrade 2>/dev/null | awk '/^[0-9]+ upgraded/{print $1; exit}')"
  printf '%s' "${n:-0}"
}

reboot_required() {
  [[ -f /var/run/reboot-required ]]
}

run_package_steps() {
  log "release: ${PRETTY_NAME:-unknown} (${VERSION_CODENAME:-?})"
  log "phase 1/2: apt update"
  "${APT_GET[@]}" update

  log "phase 2/2: apt full-upgrade"
  # shellcheck disable=SC2046
  "${APT_GET[@]}" full-upgrade $(apt_args)

  local pending
  pending="$(pending_upgradable_count)"
  if [[ "$pending" != "0" ]]; then
    die "${pending} package(s) still upgradable — resolve holds/conflicts, then re-run"
  fi
  log "package upgrades complete (no pending upgradable packages)"
}

run_release_upgrade() {
  if ! command -v do-release-upgrade >/dev/null 2>&1; then
    die "do-release-upgrade not found; install ubuntu-release-upgrader-core"
  fi

  if reboot_required; then
    die "reboot required before release upgrade (see /var/run/reboot-required). Reboot, then re-run with --release-only"
  fi

  local frontend args
  frontend="${RELEASE_UPGRADE_FRONTEND:-DistUpgradeViewKDE}"
  args=(-f "$frontend")

  if [[ -n "${RELEASE_UPGRADE_ALLOW_THIRD_PARTY:-}" ]]; then
    args+=(--allow-third-party)
  fi

  log "phase 3/3: starting do-release-upgrade (frontend=${frontend})"
  log "this step is interactive; allow plenty of time and do not interrupt"
  log "you will need another reboot when the upgrader finishes"

  if [[ "$(id -u)" -eq 0 ]]; then
    do-release-upgrade "${args[@]}"
  else
    # Re-execs via pkexec when using KDE/GTK frontends and uid != 0.
    do-release-upgrade "${args[@]}"
  fi
}

if [[ "$RELEASE_ONLY" -eq 0 ]]; then
  run_package_steps

  if reboot_required; then
    log "reboot required before release upgrade"
    if [[ -f /var/run/reboot-required.pkgs ]]; then
      log "packages:"
      sed 's/^/[ubuntu-release-upgrade]   /' /var/run/reboot-required.pkgs
    fi
    if [[ "$REBOOT_AFTER_APT" -eq 1 ]]; then
      log "rebooting now (--reboot)"
      "${SUDO[@]}" reboot
    else
      log "reboot, then run: $0 --release-only"
      exit 2
    fi
  fi
fi

if [[ "$PACKAGES_ONLY" -eq 1 ]]; then
  log "done (--packages-only)"
  exit 0
fi

run_release_upgrade
