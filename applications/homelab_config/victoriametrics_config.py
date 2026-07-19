"""VictoriaMetrics Swarm app-settings helpers and read/write for
``.config/terraform/components/swarm/victoriametrics/app.tfvars``.

The file is the source of truth for the VictoriaMetrics app Terraform slice
(``terraform/components/swarm/victoriametrics/app``). It carries the slice's own
inputs: which ``docker_machine`` to deploy on, the ``dns_nameservers`` for the
task, and optional ``placement`` (constraints + platforms). The shared Docker
provider catalog (config-id ``terraform/providers/docker``) is a separate
-var-file, so the legacy inlined ``swarm_docker_provider_config`` block is
dropped on render (hard cut to the new provider architecture).
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import VICTORIAMETRICS_APP_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_ID = "terraform/components/swarm/victoriametrics/app"
_HEADER = (
    f"# homelab-config: {_CONFIG_ID}\n"
    "# VictoriaMetrics Swarm app settings, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Generated file: edit settings in the UI (or by hand) then write it back.\n"
    "#\n"
    "# The Docker provider comes from the shared catalog (config-id\n"
    "# terraform/providers/docker); the pipeline passes docker.tfvars as an extra\n"
    "# -var-file. This slice just selects a machine and sets DNS + placement.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)


class ConfigValidationError(ValueError):
    """Raised when a VictoriaMetrics settings payload fails validation."""


def _coerce_str_list(value: object) -> list[str]:
    if value is None or value == "":
        return []
    if isinstance(value, str):
        parts = [coerce_str(p).strip() for p in value.replace("\n", ",").split(",")]
        return [p for p in parts if p]
    if isinstance(value, (list, tuple)):
        return [coerce_str(item).strip() for item in value if coerce_str(item).strip()]
    return [coerce_str(value).strip()]


def _normalize_placement(raw: object) -> dict | None:
    if not isinstance(raw, dict):
        return None
    constraints = _coerce_str_list(raw.get("constraints"))
    platforms: list[dict] = []
    raw_platforms = raw.get("platforms")
    if isinstance(raw_platforms, (list, tuple)):
        for entry in raw_platforms:
            if not isinstance(entry, dict):
                continue
            os_name = coerce_str(entry.get("os")).strip()
            arch = coerce_str(entry.get("architecture")).strip()
            if os_name or arch:
                platforms.append({"os": os_name, "architecture": arch})
    if not constraints and not platforms:
        return None
    return {"constraints": constraints, "platforms": platforms}


def normalize(data: dict) -> dict:
    """Validate and normalize the raw settings payload into canonical shape."""
    data = data or {}
    return {
        "docker_machine": coerce_str(data.get("docker_machine")).strip(),
        "dns_nameservers": _coerce_str_list(data.get("dns_nameservers")),
        "placement": _normalize_placement(data.get("placement")),
    }


def default_settings() -> dict:
    """Return empty VictoriaMetrics settings."""
    return {"docker_machine": "", "dns_nameservers": [], "placement": None}


def canonical(settings: dict) -> tuple:
    """Return a hashable form for equality/drift checks."""
    placement = settings.get("placement")
    placement_key: object = None
    if placement:
        placement_key = (
            tuple(placement.get("constraints", [])),
            tuple(
                (p.get("os", ""), p.get("architecture", ""))
                for p in placement.get("platforms", [])
            ),
        )
    return (
        settings.get("docker_machine", ""),
        tuple(settings.get("dns_nameservers", [])),
        placement_key,
    )


# --- rendering -------------------------------------------------------------


def _q(value: object) -> str:
    return f'"{hcl_escape(value)}"'


def _render_placement(placement: dict | None) -> str:
    if not placement:
        return "placement = null\n"
    lines = ["placement = {"]
    constraints = placement.get("constraints", [])
    if constraints:
        rendered = ", ".join(_q(c) for c in constraints)
        lines.append(f"  constraints = [{rendered}]")
    else:
        lines.append("  constraints = []")
    platforms = placement.get("platforms", [])
    if platforms:
        lines.append("  platforms = [")
        for platform in platforms:
            lines.append("    {")
            lines.append(f"      os           = {_q(platform.get('os', ''))}")
            lines.append(f"      architecture = {_q(platform.get('architecture', ''))}")
            lines.append("    },")
        lines.append("  ]")
    else:
        lines.append("  platforms = []")
    lines.append("}")
    return "\n".join(lines) + "\n"


def render_settings(settings: dict) -> str:
    """Render the VictoriaMetrics app tfvars document (with the config-id header)."""
    body = f"docker_machine = {_q(settings.get('docker_machine', ''))}\n\n"
    body += "dns_nameservers = [\n"
    for ns in settings.get("dns_nameservers", []):
        body += f"  {_q(ns)},\n"
    body += "]\n\n"
    body += _render_placement(settings.get("placement"))
    return f"{_HEADER}{body}"


# --- reading ---------------------------------------------------------------


def read_victoriametrics_tfvars(
    path: Path = VICTORIAMETRICS_APP_TFVARS,
) -> dict | None:
    """Parse the VictoriaMetrics app tfvars into settings, or ``None``.

    Legacy inlined provider config (``swarm_docker_provider_config``) is ignored.
    Returns ``None`` only when the file is missing/unparsable.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse VictoriaMetrics config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    return normalize(
        {
            "docker_machine": data.get("docker_machine"),
            "dns_nameservers": data.get("dns_nameservers"),
            "placement": data.get("placement"),
        }
    )


def write_victoriametrics_tfvars(
    settings: dict, path: Path = VICTORIAMETRICS_APP_TFVARS
) -> Path:
    """Write the VictoriaMetrics settings to ``path`` atomically and return it."""
    atomic_write(path, render_settings(settings))
    logger.info("Wrote VictoriaMetrics config to %s", path)
    return path


__all__ = [
    "ConfigValidationError",
    "canonical",
    "default_settings",
    "normalize",
    "read_victoriametrics_tfvars",
    "render_settings",
    "write_victoriametrics_tfvars",
]
