"""Spec-driven render/parse/validate for the shared provider tfvars files.

Every provider section shares this module: given a :class:`ProviderSpec`, it
renders a ``.config/terraform/providers/<app>.tfvars`` document (config-id
header + a single ``<tfvars_var> = { ... }`` HCL object) and reads it back into
a normalized record. Optional string/int fields are omitted from the render when
empty so the Terraform ``optional(...)`` attributes keep their defaults.
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.provider_specs import ProviderField, ProviderSpec

logger = logging.getLogger(__name__)


class ProviderValidationError(ValueError):
    """Raised when a provider credentials payload fails validation."""


def _header(spec: ProviderSpec) -> str:
    return (
        f"# homelab-config: {spec.config_id}\n"
        f"# {spec.title} provider login credentials, managed by the homelab-config\n"
        "# web app (applications/homelab_config).\n"
        "# Generated file: edit credentials in the UI (or by hand) then write it back.\n"
        "#\n"
        f"# Consumed by the {spec.title} Terraform slice as a shared -var-file that\n"
        f"# feeds var.{spec.tfvars_var} into the provider configuration.\n"
        "# This file holds secrets and lives under .config (git-ignored) - never commit it.\n"
    )


def _coerce_int(value: object) -> object:
    """Coerce a value to ``int`` or ``""`` (empty/unset)."""
    if value is None:
        return ""
    text = str(value).strip().strip('"')
    if text == "":
        return ""
    try:
        return int(float(text)) if "." in text else int(text)
    except (TypeError, ValueError):
        return ""


def default_record(spec: ProviderSpec) -> dict:
    """Return the default (empty) record used for scaffolding."""
    record: dict = {}
    for field in spec.fields:
        if field.type == "bool":
            record[field.name] = bool(field.default)
        elif field.type == "int":
            record[field.name] = ""
        else:
            record[field.name] = ""
    return record


def normalize(spec: ProviderSpec, data: dict) -> dict:
    """Validate and normalize a raw payload into the canonical record shape."""
    record: dict = {}
    for field in spec.fields:
        raw = data.get(field.name)
        if field.type == "bool":
            record[field.name] = coerce_bool(raw, default=bool(field.default))
        elif field.type == "int":
            record[field.name] = _coerce_int(raw)
        else:
            if raw is None:
                raw = ""
            if not isinstance(raw, (str, int, float)):
                raise ProviderValidationError(f"{field.name} must be a string")
            record[field.name] = str(raw).strip()
    return record


def canonical(spec: ProviderSpec, record: dict) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(record.get(field.name, "") for field in spec.fields)


def _render_field(field: ProviderField, value: object) -> str | None:
    if field.type == "bool":
        return f"{field.name} = {str(bool(value)).lower()}"
    if field.type == "int":
        if value in (None, ""):
            return None if field.optional else f"{field.name} = 0"
        return f"{field.name} = {int(value)}"
    text = "" if value is None else str(value)
    if text == "" and field.optional:
        return None
    return f'{field.name} = "{hcl_escape(text)}"'


def render(spec: ProviderSpec, record: dict) -> str:
    """Render the provider tfvars document (config-id header + HCL object)."""
    normalized = normalize(spec, record)
    lines = [f"{spec.tfvars_var} = {{"]
    for field in spec.fields:
        rendered = _render_field(field, normalized[field.name])
        if rendered is not None:
            lines.append(f"  {rendered}")
    lines.append("}")
    body = "\n".join(lines) + "\n"
    return f"{_header(spec)}{body}"


def read(spec: ProviderSpec, path: Path) -> dict | None:
    """Parse the provider tfvars into a normalized record, or ``None``."""
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse %s credentials %s: %s", spec.key, path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw = data.get(spec.tfvars_var)
    if not isinstance(raw, dict):
        return None

    payload: dict = {}
    for field in spec.fields:
        value = raw.get(field.name)
        if field.type == "bool":
            payload[field.name] = value
        elif field.type == "int":
            payload[field.name] = value
        else:
            payload[field.name] = coerce_str(value)
    try:
        return normalize(spec, payload)
    except ProviderValidationError as exc:
        logger.warning("Invalid %s credentials in %s: %s", spec.key, path, exc)
        return None


def write(spec: ProviderSpec, record: dict, path: Path) -> Path:
    """Write the provider credentials to ``path`` atomically and return it."""
    atomic_write(path, render(spec, record))
    logger.info("Wrote %s credentials to %s", spec.key, path)
    return path


__all__ = [
    "ProviderValidationError",
    "canonical",
    "default_record",
    "normalize",
    "read",
    "render",
    "write",
]
