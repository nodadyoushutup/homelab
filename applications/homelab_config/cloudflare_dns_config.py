"""Cloudflare DNS desired-state helpers and read/write for
``.config/terraform/components/remote/cloudflare/config.tfvars``.

The file is the source of truth. It carries the two variables consumed by the
Cloudflare config Terraform slice (``terraform/components/remote/cloudflare/config``):

- ``zone_id``: the Cloudflare zone that owns the records.
- ``records``: a list of A records, each ``{key, name, content, ttl, proxied}``.
  ``key`` is the stable map key Terraform uses in ``for_each`` (rename-safe).

This app does not talk to Cloudflare; it only records the desired zone/records
and renders them to HCL. Provider login is separate (config-id
``terraform/providers/cloudflare``) - it is NOT written here.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import CLOUDFLARE_CONFIG_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/remote/cloudflare/config"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Cloudflare zone + DNS records, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit records in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the Cloudflare config Terraform slice\n"
    "# (terraform/components/remote/cloudflare/config) as its slice -var-file.\n"
    "# Provider login is separate (config-id terraform/providers/cloudflare).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

_RECORD_FIELDS = ("key", "name", "content", "ttl", "proxied")


class RecordValidationError(ValueError):
    """Raised when a DNS record payload fails validation."""


def _valid_key(value: str) -> bool:
    return bool(value) and all(ch.isalnum() or ch in "_-" for ch in value)


def _coerce_int(value: object, *, default: int) -> int:
    if value is None or value == "":
        return default
    if isinstance(value, bool):
        raise ValueError("expected an integer, got a boolean")
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    text = coerce_str(value).strip()
    if text == "":
        return default
    return int(text)


def normalize_zone_id(value: object) -> str:
    """Coerce and lightly validate the zone id (never raises on empty)."""
    return coerce_str(value).strip()


def normalize_record(data: dict) -> dict:
    """Validate and normalize a raw record payload into canonical shape."""
    key = coerce_str(data.get("key") or "").strip()
    if not key:
        raise RecordValidationError("key is required")
    if not _valid_key(key):
        raise RecordValidationError(
            "key may only contain letters, digits, '-' and '_'"
        )

    name = coerce_str(data.get("name") or "").strip()
    if not name:
        raise RecordValidationError("name is required")

    content = coerce_str(data.get("content") or "").strip()
    if not content:
        raise RecordValidationError("content is required")

    try:
        ttl = _coerce_int(data.get("ttl"), default=1)
    except ValueError as exc:
        raise RecordValidationError("ttl must be an integer") from exc

    proxied = coerce_bool(data.get("proxied"), default=False)

    return {
        "key": key,
        "name": name,
        "content": content,
        "ttl": ttl,
        "proxied": proxied,
    }


def order_records(records: Iterable[dict]) -> list[dict]:
    """Return records sorted alphabetically by key."""
    return sorted(records, key=lambda record: record.get("key", ""))


def canonical(zone_id: str, records: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return (
        normalize_zone_id(zone_id),
        tuple(
            tuple(record.get(field, "") for field in _RECORD_FIELDS)
            for record in order_records(records)
        ),
    )


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _render_record_block(record: dict) -> str:
    return (
        "  {\n"
        f"    key     = {_q(record['key'])}\n"
        f"    name    = {_q(record['name'])}\n"
        f"    content = {_q(record['content'])}\n"
        f"    ttl     = {int(record['ttl'])}\n"
        f"    proxied = {'true' if record['proxied'] else 'false'}\n"
        "  },\n"
    )


def render_config(zone_id: str, records: Iterable[dict]) -> str:
    """Render the Cloudflare DNS tfvars document (including the config-id header)."""
    ordered = order_records(records)
    body = f'zone_id = "{hcl_escape(normalize_zone_id(zone_id))}"\n\n'
    body += "records = [\n"
    body += "".join(_render_record_block(record) for record in ordered)
    body += "]\n"
    return f"{_HEADER}{body}"


def _read_records(raw: object) -> list[dict]:
    records: list[dict] = []
    if not isinstance(raw, list):
        return records
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        payload = {
            "key": entry.get("key"),
            "name": entry.get("name"),
            "content": entry.get("content"),
            "ttl": entry.get("ttl"),
            "proxied": entry.get("proxied"),
        }
        try:
            records.append(normalize_record(payload))
        except RecordValidationError as exc:
            logger.warning("Skipping invalid Cloudflare record: %s", exc)
    return records


def read_cloudflare_tfvars(path: Path = CLOUDFLARE_CONFIG_TFVARS) -> dict | None:
    """Parse the Cloudflare config tfvars into ``{"zone_id": str, "records": [...]}``.

    Returns ``None`` when the file is missing/unparsable or declares neither a
    ``zone_id`` nor a ``records`` key.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Cloudflare config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    if "zone_id" not in data and "records" not in data:
        return None
    return {
        "zone_id": normalize_zone_id(data.get("zone_id")),
        "records": _read_records(data.get("records")),
    }


def write_cloudflare_tfvars(
    zone_id: str,
    records: Iterable[dict],
    path: Path = CLOUDFLARE_CONFIG_TFVARS,
) -> Path:
    """Write the Cloudflare DNS config to ``path`` atomically and return it."""
    atomic_write(path, render_config(zone_id, records))
    logger.info("Wrote Cloudflare DNS config to %s", path)
    return path


__all__ = [
    "RecordValidationError",
    "canonical",
    "normalize_record",
    "normalize_zone_id",
    "order_records",
    "read_cloudflare_tfvars",
    "render_config",
    "write_cloudflare_tfvars",
]
