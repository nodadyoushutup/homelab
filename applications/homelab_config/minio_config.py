"""MinIO instance catalog helpers and ``.config/terraform/minio.tfvars`` I/O.

The file is the source of truth. An "instance" is a plain dict describing an
*already-existing* MinIO server the homelab can reach. Keys:
``name``, ``endpoint``, ``region``, ``access_key``, ``secret_key``.

- ``name``: catalog key (e.g. ``terraform``, ``backups``); used as the
  ``minio_instances`` map key and to select an instance elsewhere (e.g. the
  Terraform state backend picks a MinIO by name).
- ``endpoint``: S3 API URL (e.g. ``https://swarm-cp-0.local:9000``).
- ``region``: S3 region (MinIO defaults to ``us-east-1``).
- ``access_key`` / ``secret_key``: S3 credentials for the instance.

The catalog renders to an HCL ``minio_instances`` map. This app does not deploy
or serve MinIO; it only records instances that already exist. The file holds
secrets and lives under ``.config`` (git-ignored) - never commit it.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_str, hcl_escape
from homelab_config.paths import MINIO_TFVARS

logger = logging.getLogger(__name__)

_CONFIG_TAG = "# homelab-config: terraform/minio"
_HEADER = (
    f"{_CONFIG_TAG}\n"
    "# Catalog of already-existing MinIO instances, managed by the homelab-config\n"
    "# web app (applications/homelab_config).\n"
    "# Generated file: edit instances in the UI (or by hand) then write it back.\n"
    "#\n"
    "# Records how to reach each MinIO (endpoint + S3 credentials). This app does\n"
    "# not deploy MinIO. The Terraform section can select one of these instances\n"
    "# for the remote S3 state backend.\n"
    "# This file holds secrets and lives under .config (git-ignored) - never commit it.\n"
)

_FIELDS = ("name", "endpoint", "region", "access_key", "secret_key")

# MinIO's conventional default region when none is specified.
_DEFAULT_REGION = "us-east-1"


class InstanceValidationError(ValueError):
    """Raised when a MinIO instance payload fails validation."""


def normalize_instance(data: dict) -> dict:
    """Validate and normalize a raw instance payload into the canonical shape.

    Args:
        data: Raw instance mapping (from the API or a parsed tfvars entry).

    Returns:
        A normalized instance dict with keys ``name``, ``endpoint``, ``region``,
        ``access_key``, ``secret_key``.

    Raises:
        InstanceValidationError: When required fields are missing or invalid.
    """
    name = str(data.get("name") or "").strip()
    if not name:
        raise InstanceValidationError("name is required")
    # The name becomes an HCL map key / selector, so keep it simple.
    if not all(ch.isalnum() or ch in "_-" for ch in name):
        raise InstanceValidationError(
            "name may only contain letters, digits, '-' and '_'"
        )

    endpoint = str(data.get("endpoint") or "").strip()
    if not endpoint:
        raise InstanceValidationError("endpoint is required")

    region = str(data.get("region") or "").strip() or _DEFAULT_REGION
    access_key = str(data.get("access_key") or "").strip()
    secret_key = str(data.get("secret_key") or "").strip()

    return {
        "name": name,
        "endpoint": endpoint,
        "region": region,
        "access_key": access_key,
        "secret_key": secret_key,
    }


def order_instances(instances: Iterable[dict]) -> list[dict]:
    """Return instances sorted alphabetically by name."""
    return sorted(instances, key=lambda inst: inst.get("name", ""))


def canonical(instances: Iterable[dict]) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(
        tuple(inst.get(field, "") for field in _FIELDS)
        for inst in order_instances(instances)
    )


def _render_instance_block(inst: dict) -> str:
    return (
        f'  {inst["name"]} = {{\n'
        f'    endpoint   = "{hcl_escape(inst["endpoint"])}"\n'
        f'    region     = "{hcl_escape(inst["region"])}"\n'
        f'    access_key = "{hcl_escape(inst["access_key"])}"\n'
        f'    secret_key = "{hcl_escape(inst["secret_key"])}"\n'
        f"  }}\n"
    )


def render_instances(instances: Iterable[dict]) -> str:
    """Render the MinIO catalog tfvars document (including the config-id header)."""
    ordered = order_instances(instances)
    body = "minio_instances = {\n"
    body += "".join(_render_instance_block(inst) for inst in ordered)
    body += "}\n"
    return f"{_HEADER}{body}"


def read_minio_tfvars(path: Path = MINIO_TFVARS) -> list[dict] | None:
    """Parse minio.tfvars into normalized instance dicts.

    Args:
        path: Source file; defaults to ``.config/terraform/minio.tfvars``.

    Returns:
        A list of normalized instance dicts (possibly empty when the file
        declares ``minio_instances = {}``), or ``None`` when the file is
        missing, unparsable, or has no ``minio_instances`` key. Malformed
        individual entries are skipped with a warning.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse MinIO catalog %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw = data.get("minio_instances")
    if not isinstance(raw, dict):
        return None

    instances: list[dict] = []
    for key, entry in raw.items():
        if not isinstance(entry, dict):
            continue
        payload = {field: coerce_str(value) for field, value in entry.items()}
        payload["name"] = coerce_str(key)
        try:
            instances.append(normalize_instance(payload))
        except InstanceValidationError as exc:
            logger.warning("Skipping invalid MinIO instance in %s: %s", path, exc)
            continue
    return instances


def write_minio_tfvars(instances: Iterable[dict], path: Path = MINIO_TFVARS) -> Path:
    """Write the MinIO catalog to ``path`` atomically and return it."""
    atomic_write(path, render_instances(instances))
    logger.info("Wrote MinIO catalog to %s", path)
    return path


__all__ = [
    "InstanceValidationError",
    "canonical",
    "normalize_instance",
    "order_instances",
    "read_minio_tfvars",
    "render_instances",
    "write_minio_tfvars",
]
