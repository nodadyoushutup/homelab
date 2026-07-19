"""Grafana desired-state helpers and read/write for
``.config/terraform/components/swarm/grafana/config.tfvars``.

The file is the source of truth for the Grafana config Terraform slice
(``terraform/components/swarm/grafana/config``). It carries the ``datasources``
list consumed by that slice (dashboards are JSON files baked into the slice, not
operator config). Provider login is separate (config-id
``terraform/providers/grafana``) - it is NOT written here, so the legacy
``provider_config`` block is dropped on render (hard cut).

Each datasource: ``name``, ``uid``, ``type``, ``url``, ``is_default`` (bool),
and an optional ``json_data`` map. The slice requires that the ``prometheus``
uid points at the canonical VictoriaMetrics query URL.
"""

from __future__ import annotations

import logging
import re
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import GRAFANA_CONFIG_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/swarm/grafana/config"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Grafana data sources, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit data sources in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Consumed by the Grafana config Terraform slice\n"
    "# (terraform/components/swarm/grafana/config) as its slice -var-file.\n"
    "# Dashboards are JSON files baked into the slice, not operator config.\n"
    "# Provider login is separate (config-id terraform/providers/grafana).\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

# The prometheus-uid datasource must query VictoriaMetrics at this canonical URL
# (mirrors the validation in the slice's variables.tf).
PROMETHEUS_UID = "prometheus"
CANONICAL_VM_URL = "http://victoriametrics:8428"

_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?\d+\.\d+$")


class ConfigValidationError(ValueError):
    """Raised when a datasource payload fails validation."""


def _coerce_scalar(value: object) -> object:
    """Coerce a json_data value to bool/int/float/str, preserving obvious types."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    text = coerce_str(value).strip()
    low = text.lower()
    if low in ("true", "false"):
        return low == "true"
    if _INT_RE.match(text):
        return int(text)
    if _FLOAT_RE.match(text):
        return float(text)
    return text


def _normalize_json_data(raw: object) -> dict:
    if not isinstance(raw, dict):
        return {}
    out: dict = {}
    for key, value in raw.items():
        name = coerce_str(key).strip()
        if name:
            out[name] = _coerce_scalar(value)
    return out


def normalize_datasource(data: dict) -> dict:
    """Validate and normalize a raw datasource payload into canonical shape."""
    name = coerce_str(data.get("name") or "").strip()
    uid = coerce_str(data.get("uid") or "").strip()
    ds_type = coerce_str(data.get("type") or "").strip()
    url = coerce_str(data.get("url") or "").strip()
    if not name:
        raise ConfigValidationError("data source name is required")
    if not uid:
        raise ConfigValidationError("data source uid is required")
    if not ds_type:
        raise ConfigValidationError("data source type is required")
    if not url:
        raise ConfigValidationError("data source url is required")
    if uid == PROMETHEUS_UID and url != CANONICAL_VM_URL:
        raise ConfigValidationError(
            f"the '{PROMETHEUS_UID}' uid must use the canonical VictoriaMetrics "
            f"URL {CANONICAL_VM_URL}"
        )
    return {
        "name": name,
        "uid": uid,
        "type": ds_type,
        "url": url,
        "is_default": coerce_bool(data.get("is_default"), default=False),
        "json_data": _normalize_json_data(data.get("json_data")),
    }


def entry_key(entry: dict) -> str:
    """Return the string key (uid) that identifies a datasource."""
    return str(entry.get("uid", ""))


def order_datasources(entries: Iterable[dict]) -> list[dict]:
    """Return datasources sorted by name (stable, human-friendly ordering)."""
    return sorted(entries, key=lambda e: str(e.get("name", "")))


def canonical(datasources: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    ordered = sorted(datasources, key=lambda e: str(e.get("uid", "")))
    return tuple(
        (
            d["uid"],
            d["name"],
            d["type"],
            d["url"],
            d["is_default"],
            tuple(sorted((k, str(v)) for k, v in d.get("json_data", {}).items())),
        )
        for d in ordered
    )


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _render_scalar(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return _q(value)


def _render_json_data(json_data: dict) -> str:
    items = ", ".join(f"{k} = {_render_scalar(v)}" for k, v in json_data.items())
    return f"{{ {items} }}"


def _render_datasource(ds: dict) -> str:
    lines = ["  {"]
    lines.append(f"    name       = {_q(ds['name'])}")
    lines.append(f"    uid        = {_q(ds['uid'])}")
    lines.append(f"    type       = {_q(ds['type'])}")
    lines.append(f"    url        = {_q(ds['url'])}")
    lines.append(f"    is_default = {'true' if ds['is_default'] else 'false'}")
    if ds.get("json_data"):
        lines.append(f"    json_data  = {_render_json_data(ds['json_data'])}")
    lines.append("  },")
    return "\n".join(lines)


def render_config(datasources: Iterable[dict]) -> str:
    """Render the Grafana config tfvars document (including the config-id header)."""
    ordered = order_datasources(datasources)
    if not ordered:
        return f"{_HEADER}datasources = []\n"
    body = "datasources = [\n"
    body += "\n".join(_render_datasource(d) for d in ordered) + "\n"
    body += "]\n"
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def read_grafana_tfvars(path: Path = GRAFANA_CONFIG_TFVARS) -> list[dict] | None:
    """Parse the Grafana config tfvars into datasource dicts, or ``None``.

    Returns a list (possibly empty for ``datasources = []``), or ``None`` when
    the file is missing/unparsable or has no ``datasources`` key.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Grafana config %s: %s", path, exc)
        return None
    if not isinstance(data, dict) or "datasources" not in data:
        return None
    raw = data.get("datasources")
    if not isinstance(raw, list):
        return None
    out: list[dict] = []
    for entry in raw:
        if not isinstance(entry, dict):
            continue
        try:
            out.append(normalize_datasource(entry))
        except ConfigValidationError as exc:
            logger.warning("Skipping invalid Grafana datasource: %s", exc)
    return out


def write_grafana_tfvars(
    datasources: Iterable[dict], path: Path = GRAFANA_CONFIG_TFVARS
) -> Path:
    """Write the Grafana datasources to ``path`` atomically and return it."""
    atomic_write(path, render_config(datasources))
    logger.info("Wrote Grafana config to %s", path)
    return path


__all__ = [
    "CANONICAL_VM_URL",
    "PROMETHEUS_UID",
    "ConfigValidationError",
    "canonical",
    "entry_key",
    "normalize_datasource",
    "order_datasources",
    "read_grafana_tfvars",
    "render_config",
    "write_grafana_tfvars",
]
