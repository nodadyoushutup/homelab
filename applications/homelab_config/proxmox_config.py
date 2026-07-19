"""Proxmox provider credentials helpers and
``.config/terraform/providers/proxmox.tfvars`` read/write.

The file is the source of truth. It holds a single ``proxmox`` object with the
login/connection settings the ``bpg/proxmox`` Terraform provider needs:

- ``endpoint``: Proxmox API URL (e.g. ``https://pve.example.com:8006``).
- ``username``: API user (e.g. ``root@pam``).
- ``password``: API password.
- ``insecure``: skip TLS verification when true.
- ``random_vm_ids``: let the provider assign random VM IDs when true.
- ``ssh_agent``: use the local SSH agent for provider SSH (renders ``ssh { agent }``).

The record renders to an HCL ``proxmox`` object so the Proxmox slice can consume
it via ``-var-file``. This app does not talk to Proxmox; it only records the
credentials. The file lives under ``.config`` (git-ignored) and holds secrets -
do not commit it.
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import PROXMOX_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/providers/proxmox"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Proxmox provider login credentials, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit credentials in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the Proxmox Terraform slice as a shared -var-file; the slice\n"
    "# feeds these values straight into the bpg/proxmox provider configuration.\n"
    "# This file holds secrets and lives under .config (git-ignored) - never commit it.\n"
)

_STR_FIELDS = ("endpoint", "username", "password")
_BOOL_FIELDS = ("insecure", "random_vm_ids", "ssh_agent")
_FIELDS = _STR_FIELDS + _BOOL_FIELDS

# Boolean defaults mirror the historical inline provider_config block so a fresh
# scaffold matches the previous slice defaults.
_BOOL_DEFAULTS = {"insecure": True, "random_vm_ids": True, "ssh_agent": True}


class CredentialsValidationError(ValueError):
    """Raised when a credentials payload fails validation."""


def default_credentials() -> dict:
    """Return the default (empty) credentials record used for scaffolding."""
    record = {field: "" for field in _STR_FIELDS}
    record.update(_BOOL_DEFAULTS)
    return record


def normalize_credentials(data: dict) -> dict:
    """Validate and normalize a raw credentials payload into canonical shape.

    Args:
        data: Raw mapping (from the API or a parsed tfvars object).

    Returns:
        A normalized dict with keys ``endpoint``, ``username``, ``password``,
        ``insecure``, ``random_vm_ids``, ``ssh_agent``.

    Raises:
        CredentialsValidationError: When a string field is not a string.
    """
    record: dict = {}
    for field in _STR_FIELDS:
        value = data.get(field, "")
        if value is None:
            value = ""
        if not isinstance(value, (str, int, float)):
            raise CredentialsValidationError(f"{field} must be a string")
        record[field] = str(value).strip()
    for field in _BOOL_FIELDS:
        record[field] = coerce_bool(
            data.get(field, _BOOL_DEFAULTS[field]), default=_BOOL_DEFAULTS[field]
        )
    return record


def canonical(record: dict) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(record.get(field, "") for field in _FIELDS)


def render_credentials(record: dict) -> str:
    """Render the Proxmox credentials tfvars document (with config-id header)."""
    normalized = normalize_credentials(record)
    body = (
        "proxmox = {\n"
        f'  endpoint      = "{hcl_escape(normalized["endpoint"])}"\n'
        f'  username      = "{hcl_escape(normalized["username"])}"\n'
        f'  password      = "{hcl_escape(normalized["password"])}"\n'
        f"  insecure      = {str(normalized['insecure']).lower()}\n"
        f"  random_vm_ids = {str(normalized['random_vm_ids']).lower()}\n"
        "  ssh = {\n"
        f"    agent = {str(normalized['ssh_agent']).lower()}\n"
        "  }\n"
        "}\n"
    )
    return f"{_HEADER}{body}"


def read_proxmox_tfvars(path: Path = PROXMOX_TFVARS) -> dict | None:
    """Parse proxmox.tfvars into a normalized credentials dict.

    Args:
        path: Source file; defaults to ``.config/terraform/providers/proxmox.tfvars``.

    Returns:
        A normalized credentials dict, or ``None`` when the file is missing,
        unparsable, or has no ``proxmox`` object.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Proxmox credentials %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw = data.get("proxmox")
    if not isinstance(raw, dict):
        return None

    ssh = raw.get("ssh")
    ssh_agent = ssh.get("agent") if isinstance(ssh, dict) else None

    payload = {
        "endpoint": coerce_str(raw.get("endpoint")),
        "username": coerce_str(raw.get("username")),
        "password": coerce_str(raw.get("password")),
        "insecure": raw.get("insecure"),
        "random_vm_ids": raw.get("random_vm_ids"),
        "ssh_agent": ssh_agent,
    }
    try:
        return normalize_credentials(payload)
    except CredentialsValidationError as exc:
        logger.warning("Invalid Proxmox credentials in %s: %s", path, exc)
        return None


def write_proxmox_tfvars(record: dict, path: Path = PROXMOX_TFVARS) -> Path:
    """Write the Proxmox credentials to ``path`` atomically and return it."""
    atomic_write(path, render_credentials(record))
    logger.info("Wrote Proxmox credentials to %s", path)
    return path


__all__ = [
    "CredentialsValidationError",
    "canonical",
    "default_credentials",
    "normalize_credentials",
    "read_proxmox_tfvars",
    "render_credentials",
    "write_proxmox_tfvars",
]
