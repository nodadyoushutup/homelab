"""Terraform state settings + derived S3 backend config helpers.

Two files back the Terraform section:

- ``.config/terraform/state.tfvars`` (config-id ``terraform/state``) is the
  *source of truth*. It records the chosen state backend (``local`` or ``s3``),
  the selected MinIO instance name, the bucket, and the S3 skip flags. Pipelines
  read this via the shared ``scripts/terraform/terraform_backend_init.sh``
  helper: ``local`` self-inits an on-disk backend (no MinIO), and flipping
  between ``local`` and ``s3`` auto-migrates existing state in either direction.

- ``.config/terraform/minio.backend.hcl`` (config-id ``terraform/minio.backend``)
  is *derived*: when the backend is ``s3`` and a MinIO instance is selected, it
  is rendered from the state settings plus that instance's connection details
  (endpoint + credentials). Every slice pipeline consumes it via
  ``terraform init -backend-config``.

This module only knows how to render/parse the two files. Resolving the
selected MinIO instance from the catalog is the store's job.
"""

from __future__ import annotations

import logging
from pathlib import Path

import hcl2

from homelab_config.hcl_util import atomic_write, coerce_bool, coerce_str, hcl_escape
from homelab_config.paths import MINIO_BACKEND_HCL, TERRAFORM_STATE_TFVARS

logger = logging.getLogger(__name__)

_STATE_TAG = "# homelab-config: terraform/state"
_STATE_HEADER = (
    f"{_STATE_TAG}\n"
    "# Terraform state backend settings, managed by the homelab-config web app\n"
    "# (applications/homelab_config).\n"
    "# Source of truth for the Terraform section: it records whether state is\n"
    "# local or a remote MinIO S3 backend, which MinIO instance to use, and the\n"
    "# bucket. The S3 backend file (terraform/minio.backend) is DERIVED from this.\n"
    "# This file lives under .config (git-ignored) - do not commit it.\n"
)

_BACKEND_TAG = "# homelab-config: terraform/minio.backend"

VALID_BACKENDS = ("local", "s3")
_DEFAULT_BACKEND = "s3"

_STR_FIELDS = ("backend", "minio", "bucket", "region")
_BOOL_FIELDS = (
    "skip_credentials_validation",
    "skip_metadata_api_check",
    "skip_requesting_account_id",
    "use_path_style",
)
_FIELDS = _STR_FIELDS + _BOOL_FIELDS

# The S3 backend skip flags are always true for MinIO (it is not real AWS), so a
# fresh scaffold matches what every existing slice expects.
_BOOL_DEFAULTS = {field: True for field in _BOOL_FIELDS}

# MinIO's conventional default region when neither the settings nor the selected
# instance specify one.
_DEFAULT_REGION = "us-east-1"


class SettingsValidationError(ValueError):
    """Raised when a Terraform settings payload fails validation."""


def default_settings() -> dict:
    """Return the default settings record used for scaffolding."""
    record = {field: "" for field in _STR_FIELDS}
    record["backend"] = _DEFAULT_BACKEND
    record.update(_BOOL_DEFAULTS)
    return record


def normalize_settings(data: dict) -> dict:
    """Validate and normalize a raw settings payload into canonical shape.

    Raises:
        SettingsValidationError: When ``backend`` is not ``local``/``s3`` or a
            string field is not a string.
    """
    record: dict = {}
    for field in _STR_FIELDS:
        value = data.get(field, "")
        if value is None:
            value = ""
        if not isinstance(value, (str, int, float)):
            raise SettingsValidationError(f"{field} must be a string")
        record[field] = str(value).strip()

    backend = record["backend"] or _DEFAULT_BACKEND
    if backend not in VALID_BACKENDS:
        raise SettingsValidationError(
            f"backend must be one of {', '.join(VALID_BACKENDS)}"
        )
    record["backend"] = backend

    for field in _BOOL_FIELDS:
        record[field] = coerce_bool(
            data.get(field, _BOOL_DEFAULTS[field]), default=_BOOL_DEFAULTS[field]
        )
    return record


def canonical(record: dict) -> tuple:
    """Return an order-insensitive, hashable form for equality/drift checks."""
    return tuple(record.get(field, "") for field in _FIELDS)


def render_settings(record: dict) -> str:
    """Render the terraform/state.tfvars document (with config-id header)."""
    s = normalize_settings(record)
    body = (
        "terraform_state = {\n"
        f'  backend                     = "{hcl_escape(s["backend"])}"\n'
        f'  minio                       = "{hcl_escape(s["minio"])}"\n'
        f'  bucket                      = "{hcl_escape(s["bucket"])}"\n'
        f'  region                      = "{hcl_escape(s["region"])}"\n'
        f"  skip_credentials_validation = {str(s['skip_credentials_validation']).lower()}\n"
        f"  skip_metadata_api_check     = {str(s['skip_metadata_api_check']).lower()}\n"
        f"  skip_requesting_account_id  = {str(s['skip_requesting_account_id']).lower()}\n"
        f"  use_path_style              = {str(s['use_path_style']).lower()}\n"
        "}\n"
    )
    return f"{_STATE_HEADER}{body}"


def read_state_tfvars(path: Path = TERRAFORM_STATE_TFVARS) -> dict | None:
    """Parse state.tfvars into a normalized settings dict.

    Returns:
        A normalized settings dict, or ``None`` when the file is missing,
        unparsable, or has no ``terraform_state`` object.
    """
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = hcl2.load(handle)
    except Exception as exc:  # noqa: BLE001 - hcl2 raises assorted errors
        logger.warning("Could not parse Terraform state settings %s: %s", path, exc)
        return None
    if not isinstance(data, dict):
        return None
    raw = data.get("terraform_state")
    if not isinstance(raw, dict):
        return None

    payload = {
        "backend": coerce_str(raw.get("backend")),
        "minio": coerce_str(raw.get("minio")),
        "bucket": coerce_str(raw.get("bucket")),
        "region": coerce_str(raw.get("region")),
        "skip_credentials_validation": raw.get("skip_credentials_validation"),
        "skip_metadata_api_check": raw.get("skip_metadata_api_check"),
        "skip_requesting_account_id": raw.get("skip_requesting_account_id"),
        "use_path_style": raw.get("use_path_style"),
    }
    try:
        return normalize_settings(payload)
    except SettingsValidationError as exc:
        logger.warning("Invalid Terraform state settings in %s: %s", path, exc)
        return None


def _backend_local_stub() -> str:
    return (
        f"{_BACKEND_TAG}\n"
        "# Terraform state backend is set to LOCAL in homelab-config.\n"
        "# No remote S3 backend is configured; this file is intentionally empty.\n"
        "# In this mode each pipeline self-inits a local backend (state on disk in\n"
        "# the slice dir) via a generated *_override.tf - no MinIO required.\n"
        "# Switching to s3 auto-migrates existing state up to MinIO on the next run\n"
        "# (and s3 -> local migrates it back down); MinIO must be reachable then.\n"
    )


def render_backend(settings: dict, instance: dict | None) -> str:
    """Render the S3 backend config for ``terraform init -backend-config``.

    Args:
        settings: Normalized Terraform state settings.
        instance: The selected MinIO instance dict (endpoint/region/access_key/
            secret_key), or ``None`` when local or unresolved.

    Returns:
        The rendered ``minio.backend.hcl`` body. For a local backend (or when no
        MinIO instance resolves) a commented stub is returned instead of an S3
        block, so the config-id file stays present and obviously unconfigured.
    """
    s = normalize_settings(settings)
    if s["backend"] != "s3" or instance is None:
        return _backend_local_stub()

    region = s["region"] or instance.get("region") or _DEFAULT_REGION
    return (
        f"{_BACKEND_TAG}\n"
        "# Terraform S3 remote-state backend for MinIO, DERIVED by the\n"
        "# homelab-config web app from terraform/state + the selected MinIO\n"
        f"# instance ({instance.get('name', '')}). Do not edit by hand; edit the\n"
        "# Terraform section in the UI. This file holds secrets - never commit it.\n"
        f'bucket     = "{hcl_escape(s["bucket"])}"\n'
        f'region     = "{hcl_escape(region)}"\n'
        f'access_key = "{hcl_escape(instance.get("access_key", ""))}"\n'
        f'secret_key = "{hcl_escape(instance.get("secret_key", ""))}"\n'
        "\n"
        f'endpoints = {{ s3 = "{hcl_escape(instance.get("endpoint", ""))}" }}\n'
        "\n"
        f"skip_credentials_validation = {str(s['skip_credentials_validation']).lower()}\n"
        f"skip_metadata_api_check     = {str(s['skip_metadata_api_check']).lower()}\n"
        f"skip_requesting_account_id  = {str(s['skip_requesting_account_id']).lower()}\n"
        f"use_path_style              = {str(s['use_path_style']).lower()}\n"
    )


def write_state_tfvars(record: dict, path: Path = TERRAFORM_STATE_TFVARS) -> Path:
    """Write the Terraform state settings to ``path`` atomically and return it."""
    atomic_write(path, render_settings(record))
    logger.info("Wrote Terraform state settings to %s", path)
    return path


def write_backend_hcl(
    settings: dict, instance: dict | None, path: Path = MINIO_BACKEND_HCL
) -> Path:
    """Write the derived S3 backend config to ``path`` atomically and return it."""
    atomic_write(path, render_backend(settings, instance))
    logger.info("Wrote Terraform S3 backend config to %s", path)
    return path


__all__ = [
    "MINIO_BACKEND_HCL",
    "SettingsValidationError",
    "TERRAFORM_STATE_TFVARS",
    "VALID_BACKENDS",
    "canonical",
    "default_settings",
    "normalize_settings",
    "read_state_tfvars",
    "render_backend",
    "render_settings",
    "write_backend_hcl",
    "write_state_tfvars",
]
