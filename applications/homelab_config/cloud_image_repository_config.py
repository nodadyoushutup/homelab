"""Cloud Image Repository config helpers and
``.config/terraform/components/swarm/cloud-image-repository/app.tfvars`` I/O.

The file is the source of truth and is the slice ``-var-file`` consumed by the
Cloud Image Repository Swarm app slice
(``terraform/components/swarm/cloud-image-repository/app``). It holds only this
slice's own inputs:

- ``docker_machine``: which shared Docker provider entry (config-id
  ``terraform/providers/docker``) this slice connects through.
- ``dns_nameservers``: DNS nameservers for the Swarm task ``dns_config``.
- ``placement``: optional Swarm placement constraints + platforms.
- ``nfs_share``: which shared NFS export (config-id ``terraform/nfs``) backs the
  served ``/data`` directory.
- ``nfs_subpath``: path under the selected share's export to mount.

The shared Docker provider catalog (``providers/docker.tfvars``) and NFS catalog
(``nfs.tfvars``) are passed as *separate* ``-var-file`` inputs by the pipeline;
they are NOT part of this file. It lives under ``.config`` (git-ignored).
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import CLOUD_IMAGE_REPOSITORY_APP_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/components/swarm/cloud-image-repository/app"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Cloud Image Repository Swarm app inputs, managed by the homelab-config\n"
    "# web app (applications/homelab_config).\n"
    "# Generated file: edit the Cloud Image Repository section in the UI (or by\n"
    "# hand) then write it back. Consumed by the Cloud Image Repository Terraform\n"
    "# slice as its -var-file; the shared Docker provider catalog\n"
    "# (providers/docker.tfvars) and NFS catalog (nfs.tfvars) are separate\n"
    "# -var-files.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)


class CloudImageRepositoryValidationError(ValueError):
    """Raised when a Cloud Image Repository config payload fails validation."""


def default_config() -> dict:
    """Return the default (empty) config used for scaffolding."""
    return {
        "docker_machine": "",
        "dns_nameservers": [],
        "placement": {"constraints": [], "platforms": []},
        "nfs_share": "",
        "nfs_subpath": "",
    }


def _clean_list(value: object) -> list[str]:
    """Coerce a value into a list of non-empty trimmed strings."""
    if value is None:
        return []
    if isinstance(value, str):
        items: list = [value]
    elif isinstance(value, (list, tuple)):
        items = list(value)
    else:
        items = [value]
    out: list[str] = []
    for item in items:
        # coerce_str strips the surrounding quotes python-hcl2 keeps on list
        # string elements; it is a no-op for plain JSON strings from the UI.
        text = coerce_str(item).strip()
        if text:
            out.append(text)
    return out


def _normalize_platforms(value: object) -> list[dict]:
    """Normalize a list of ``{os, architecture}`` platform objects.

    Entries where both fields are empty are dropped; otherwise both fields are
    kept (empty strings allowed, matching the Terraform ``string`` contract).
    """
    if not isinstance(value, (list, tuple)):
        return []
    platforms: list[dict] = []
    for entry in value:
        if not isinstance(entry, dict):
            continue
        os_name = coerce_str(entry.get("os")).strip()
        arch = coerce_str(entry.get("architecture")).strip()
        if not os_name and not arch:
            continue
        platforms.append({"os": os_name, "architecture": arch})
    return platforms


def normalize_config(data: dict) -> dict:
    """Validate and normalize a raw config payload into canonical shape."""
    if not isinstance(data, dict):
        raise CloudImageRepositoryValidationError("config must be an object")

    raw_placement = data.get("placement") or {}
    if not isinstance(raw_placement, dict):
        raise CloudImageRepositoryValidationError("placement must be an object")

    return {
        "docker_machine": str(data.get("docker_machine") or "").strip(),
        "dns_nameservers": _clean_list(data.get("dns_nameservers")),
        "placement": {
            "constraints": _clean_list(raw_placement.get("constraints")),
            "platforms": _normalize_platforms(raw_placement.get("platforms")),
        },
        "nfs_share": str(data.get("nfs_share") or "").strip(),
        "nfs_subpath": str(data.get("nfs_subpath") or "").strip(),
    }


def canonical(config: dict) -> tuple:
    """Return an order-preserving, hashable form for equality/drift checks."""
    placement = config.get("placement", {})
    return (
        config.get("docker_machine", ""),
        tuple(config.get("dns_nameservers", [])),
        tuple(placement.get("constraints", [])),
        tuple(
            (p.get("os", ""), p.get("architecture", ""))
            for p in placement.get("platforms", [])
        ),
        config.get("nfs_share", ""),
        config.get("nfs_subpath", ""),
    )


def _render_string_list(items: list[str]) -> str:
    if not items:
        return "[]"
    body = "[\n"
    body += "".join(f'  "{hcl_escape(i)}",\n' for i in items)
    body += "]"
    return body


def _render_placement(placement: dict) -> str:
    constraints = placement.get("constraints", [])
    platforms = placement.get("platforms", [])
    # placement is optional (Terraform default = null); emit null when unset so
    # the slice falls back to its default instead of an empty object.
    if not constraints and not platforms:
        return "placement = null\n"

    lines = ["placement = {\n"]
    if constraints:
        inner = ", ".join(f'"{hcl_escape(c)}"' for c in constraints)
        lines.append(f"  constraints = [{inner}]\n")
    else:
        lines.append("  constraints = []\n")

    if platforms:
        lines.append("  platforms = [\n")
        for plat in platforms:
            lines.append("    {\n")
            lines.append(f'      os           = "{hcl_escape(plat.get("os", ""))}"\n')
            lines.append(
                f'      architecture = "{hcl_escape(plat.get("architecture", ""))}"\n'
            )
            lines.append("    },\n")
        lines.append("  ]\n")
    else:
        lines.append("  platforms = []\n")
    lines.append("}\n")
    return "".join(lines)


def render_config(config: dict) -> str:
    """Render the Cloud Image Repository app.tfvars (including the config-id header)."""
    c = normalize_config(config)
    lines = [_HEADER]
    lines.append(f'docker_machine = "{hcl_escape(c["docker_machine"])}"\n\n')
    lines.append(f"dns_nameservers = {_render_string_list(c['dns_nameservers'])}\n\n")
    lines.append(_render_placement(c["placement"]))
    lines.append("\n")
    lines.append(f'nfs_share   = "{hcl_escape(c["nfs_share"])}"\n')
    lines.append(f'nfs_subpath = "{hcl_escape(c["nfs_subpath"])}"\n')
    return "".join(lines)


def read_cloud_image_repository_tfvars(
    path: Path = CLOUD_IMAGE_REPOSITORY_APP_TFVARS,
) -> dict | None:
    """Parse the Cloud Image Repository app.tfvars into a normalized config dict.

    Returns:
        A normalized config dict, or ``None`` when the file is missing or
        unparsable. Missing keys default to empty values.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Cloud Image Repository config %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None

    raw_placement = data.get("placement")
    if not isinstance(raw_placement, dict):
        raw_placement = {}

    payload = {
        "docker_machine": coerce_str(data.get("docker_machine")),
        "dns_nameservers": _clean_list(data.get("dns_nameservers")),
        "placement": {
            "constraints": _clean_list(raw_placement.get("constraints")),
            "platforms": _normalize_platforms(raw_placement.get("platforms")),
        },
        "nfs_share": coerce_str(data.get("nfs_share")),
        "nfs_subpath": coerce_str(data.get("nfs_subpath")),
    }
    try:
        return normalize_config(payload)
    except CloudImageRepositoryValidationError as exc:
        logger.warning("Invalid Cloud Image Repository config in %s: %s", path, exc)
        return None


def write_cloud_image_repository_tfvars(
    config: dict, path: Path = CLOUD_IMAGE_REPOSITORY_APP_TFVARS
) -> Path:
    """Write the Cloud Image Repository config to ``path`` atomically and return it."""
    atomic_write(path, render_config(config))
    logger.info("Wrote Cloud Image Repository config to %s", path)
    return path


__all__ = [
    "CloudImageRepositoryValidationError",
    "canonical",
    "default_config",
    "normalize_config",
    "read_cloud_image_repository_tfvars",
    "render_config",
    "write_cloud_image_repository_tfvars",
]
