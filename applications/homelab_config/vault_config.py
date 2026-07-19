"""Vault KV desired-state helpers and read/write for
``.config/terraform/components/swarm/vault/config.tfvars``.

The file is the source of truth. It carries the inputs consumed by the Vault
config Terraform slice (``terraform/components/swarm/vault/config``):

- ``mount_path``: the KV v2 mount path (default ``secret``).
- ``secrets``: ``map(map(map(string)))`` - ``group -> name -> field -> value``.
  Rendered here as inline secret values (this whole ``.config`` tree is
  git-ignored and holds live secrets).
- ``secret_files``: same shape but field values are host filesystem paths. The
  UI manages inline ``secrets`` only, but any ``secret_files`` present on disk
  are round-tripped verbatim so hand-authored entries are never dropped.

This app does not talk to Vault; it only records the desired mount + secrets and
renders them to HCL. Provider login is separate (config-id
``terraform/providers/vault``) - it is NOT written here.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import VAULT_CONFIG_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/swarm/vault/config"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Vault KV v2 mount path + secrets, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit secrets in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the Vault config Terraform slice\n"
    "# (terraform/components/swarm/vault/config) as its slice -var-file.\n"
    "# Provider login is separate (config-id terraform/providers/vault).\n"
    "# This file holds live secret values and lives under .config (git-ignored)\n"
    "# - do not commit it.\n"
)

DEFAULT_MOUNT_PATH = "secret"
_KEY_RE = re.compile(r"^[a-z0-9_-]+$")


class SecretValidationError(ValueError):
    """Raised when a secret payload fails validation."""


def normalize_mount_path(value: object) -> str:
    """Coerce the KV mount path; falls back to the default when empty."""
    text = coerce_str(value).strip().strip("/")
    return text or DEFAULT_MOUNT_PATH


def _valid_component(value: str) -> bool:
    return bool(_KEY_RE.match(value))


def secret_key(group: str, name: str) -> str:
    """Stable id for a secret. group/name cannot contain '/', so this is unambiguous."""
    return f"{group}/{name}"


def _normalize_fields(raw: object) -> dict[str, str]:
    """Coerce a field map into ``{field: value}`` (dropping blank field names)."""
    fields: dict[str, str] = {}
    if isinstance(raw, dict):
        items: Iterable[tuple[object, object]] = raw.items()
    elif isinstance(raw, list):
        items = (
            (entry.get("field"), entry.get("value"))
            for entry in raw
            if isinstance(entry, dict)
        )
    else:
        return fields
    for key, value in items:
        field = coerce_str(key).strip()
        if not field:
            continue
        fields[field] = coerce_str(value)
    return fields


def normalize_secret(data: dict) -> dict:
    """Validate and normalize a raw secret payload into canonical shape."""
    group = coerce_str(data.get("group") or "").strip()
    if not group:
        raise SecretValidationError("group is required")
    if not _valid_component(group):
        raise SecretValidationError(
            "group may only contain lowercase letters, digits, '-' and '_'"
        )

    name = coerce_str(data.get("name") or "").strip()
    if not name:
        raise SecretValidationError("name is required")
    if not _valid_component(name):
        raise SecretValidationError(
            "name may only contain lowercase letters, digits, '-' and '_'"
        )

    fields = _normalize_fields(data.get("fields"))
    if not fields:
        raise SecretValidationError("at least one field is required")

    return {
        "key": secret_key(group, name),
        "group": group,
        "name": name,
        "fields": fields,
    }


def order_secrets(secrets: Iterable[dict]) -> list[dict]:
    """Return secrets sorted by group then name (stable, deterministic render)."""
    return sorted(
        secrets, key=lambda secret: (secret.get("group", ""), secret.get("name", ""))
    )


def _fields_canonical(fields: dict) -> tuple:
    return tuple(sorted((k, coerce_str(v)) for k, v in (fields or {}).items()))


def _files_canonical(secret_files: dict) -> tuple:
    result: list[tuple] = []
    for group in sorted(secret_files or {}):
        for name in sorted(secret_files[group] or {}):
            result.append((group, name, _fields_canonical(secret_files[group][name])))
    return tuple(result)


def canonical(
    mount_path: str, secrets: Iterable[dict], secret_files: dict | None = None
) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return (
        normalize_mount_path(mount_path),
        tuple(
            (secret.get("group", ""), secret.get("name", ""), _fields_canonical(secret.get("fields", {})))
            for secret in order_secrets(secrets)
        ),
        _files_canonical(secret_files or {}),
    )


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _render_nested_map(var_name: str, grouped: dict) -> str:
    """Render a ``map(map(map(string)))`` HCL block."""
    if not grouped:
        return f"{var_name} = {{}}\n"
    lines = [f"{var_name} = {{"]
    for group in sorted(grouped):
        names = grouped[group] or {}
        lines.append(f"  {_q(group)} = {{")
        for name in sorted(names):
            fields = names[name] or {}
            lines.append(f"    {_q(name)} = {{")
            for field in sorted(fields):
                lines.append(f"      {_q(field)} = {_q(fields[field])}")
            lines.append("    }")
        lines.append("  }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _secrets_to_grouped(secrets: Iterable[dict]) -> dict:
    grouped: dict[str, dict[str, dict[str, str]]] = {}
    for secret in secrets:
        group = secret.get("group", "")
        name = secret.get("name", "")
        if not group or not name:
            continue
        grouped.setdefault(group, {})[name] = dict(secret.get("fields", {}))
    return grouped


def render_config(
    mount_path: str, secrets: Iterable[dict], secret_files: dict | None = None
) -> str:
    """Render the Vault config tfvars document (including the config-id header)."""
    body = f'mount_path = "{hcl_escape(normalize_mount_path(mount_path))}"\n\n'
    body += _render_nested_map("secrets", _secrets_to_grouped(secrets))
    body += "\n"
    body += _render_nested_map("secret_files", secret_files or {})
    return f"{_HEADER}{body}"


def _read_grouped(raw: object) -> dict:
    grouped: dict[str, dict[str, dict[str, str]]] = {}
    if not isinstance(raw, dict):
        return grouped
    for group, names in raw.items():
        if not isinstance(names, dict):
            continue
        g = coerce_str(group).strip()
        if not g:
            continue
        for name, fields in names.items():
            n = coerce_str(name).strip()
            if not n:
                continue
            grouped.setdefault(g, {})[n] = _normalize_fields(fields)
    return grouped


def _grouped_to_secrets(grouped: dict) -> list[dict]:
    secrets: list[dict] = []
    for group, names in grouped.items():
        for name, fields in names.items():
            secrets.append(
                {
                    "key": secret_key(group, name),
                    "group": group,
                    "name": name,
                    "fields": dict(fields),
                }
            )
    return order_secrets(secrets)


def read_vault_tfvars(path: Path = VAULT_CONFIG_TFVARS) -> dict | None:
    """Parse the Vault config tfvars into ``{"mount_path", "secrets", "secret_files"}``.

    Returns ``None`` when the file is missing/unparsable or declares none of the
    ``mount_path`` / ``secrets`` / ``secret_files`` keys.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Vault config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    if not any(k in data for k in ("mount_path", "secrets", "secret_files")):
        return None
    return {
        "mount_path": normalize_mount_path(data.get("mount_path")),
        "secrets": _grouped_to_secrets(_read_grouped(data.get("secrets"))),
        "secret_files": _read_grouped(data.get("secret_files")),
    }


def write_vault_tfvars(
    mount_path: str,
    secrets: Iterable[dict],
    secret_files: dict | None = None,
    path: Path = VAULT_CONFIG_TFVARS,
) -> Path:
    """Write the Vault config to ``path`` atomically and return it."""
    atomic_write(path, render_config(mount_path, secrets, secret_files))
    logger.info("Wrote Vault config to %s", path)
    return path


__all__ = [
    "DEFAULT_MOUNT_PATH",
    "SecretValidationError",
    "canonical",
    "normalize_mount_path",
    "normalize_secret",
    "order_secrets",
    "read_vault_tfvars",
    "render_config",
    "secret_key",
    "write_vault_tfvars",
]
