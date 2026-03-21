#!/usr/bin/env bash
set -euo pipefail

PACKER_USER="packer"
TARGET_USER="nodadyoushutup"

if id -u "${PACKER_USER}" >/dev/null 2>&1; then
  userdel -r "${PACKER_USER}" >/dev/null 2>&1 || true
  getent group "${PACKER_USER}" >/dev/null 2>&1 && groupdel "${PACKER_USER}" >/dev/null 2>&1 || true
fi

if id -u "${TARGET_USER}" >/dev/null 2>&1; then
  HOME_DIR="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
  SSH_DIR="${HOME_DIR}/.ssh"

  if [[ -f "${SSH_DIR}/authorized_keys" ]]; then
    rm -f "${SSH_DIR}/authorized_keys"
  fi

  if [[ -d "${SSH_DIR}" ]]; then
    rmdir --ignore-fail-on-non-empty "${SSH_DIR}" 2>/dev/null || true
  fi

  # Keep the account for image usage, but prevent password login.
  passwd -l "${TARGET_USER}" >/dev/null 2>&1 || true
fi

# Remove temporary provisioner artifacts.
rm -f /tmp/install-docker.sh /tmp/cleanup-image.sh

# Remove host-specific identity so clones regenerate on first boot.
cloud-init clean --logs --machine-id || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
