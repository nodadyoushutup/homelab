"""In-memory working copy of the Terraform state settings.

The on-disk ``state.tfvars`` is the source of truth. This store holds an
editable *working* copy plus a *baseline* snapshot of what we last synced with
disk, so we can report ``dirty`` (unsaved edits) and ``external_change`` (the
file changed out of band).

The S3 backend file (``minio.backend.hcl``) is *derived*: it is (re)written from
the working settings plus the selected MinIO instance whenever the settings are
saved, or when the MinIO catalog changes (:meth:`refresh_backend`). To avoid
clobbering an operator's existing backend file, the derived file is only written
when the section is actually configured (backend ``s3`` and the selected MinIO
instance resolves in the catalog).
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.minio_config import order_instances, read_minio_tfvars
from homelab_config.paths import (
    MINIO_BACKEND_HCL,
    MINIO_TFVARS,
    TERRAFORM_STATE_TFVARS,
)
from homelab_config.terraform_config import (
    SettingsValidationError,
    canonical,
    default_settings,
    normalize_settings,
    read_state_tfvars,
    render_backend,
    render_settings,
    write_backend_hcl,
    write_state_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors."""


class TerraformStore:
    """Thread-safe working copy of the Terraform state settings."""

    def __init__(
        self,
        state_path: Path = TERRAFORM_STATE_TFVARS,
        backend_path: Path = MINIO_BACKEND_HCL,
        minio_path: Path = MINIO_TFVARS,
    ) -> None:
        self._state_path = state_path
        self._backend_path = backend_path
        self._minio_path = minio_path
        self._lock = threading.RLock()
        self._working: dict = default_settings()
        self._baseline: dict = default_settings()
        self.reload()

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working settings record."""
        with self._lock:
            return dict(self._working)

    def available_minios(self) -> list[str]:
        """Return the names of MinIO instances available to select."""
        instances = read_minio_tfvars(self._minio_path) or []
        return [inst["name"] for inst in order_instances(instances)]

    def _selected_instance(self) -> dict | None:
        """Resolve the selected MinIO instance from the catalog (or None)."""
        name = self._working.get("minio") or ""
        if not name:
            return None
        instances = read_minio_tfvars(self._minio_path) or []
        for inst in instances:
            if inst["name"] == name:
                return inst
        return None

    def render_state(self) -> str:
        """Return the rendered state.tfvars for the current working copy."""
        with self._lock:
            return render_settings(self._working)

    def render_backend(self) -> str:
        """Return the rendered minio.backend.hcl for the current working copy.

        This always renders what *would* be written (resolving the selected
        MinIO), so the UI can preview it even before it is saved.
        """
        with self._lock:
            return render_backend(self._working, self._selected_instance())

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_state_tfvars(self._state_path) or default_settings()
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._state_path.is_file(),
                "backend": self._working.get("backend", ""),
                "minio_resolved": self._selected_instance() is not None,
            }

    # -- mutations (working copy only) ----------------------------------------

    def update(self, data: dict) -> dict:
        """Replace the working settings record."""
        record = normalize_settings(data)
        with self._lock:
            self._working = record
            return dict(self._working)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the settings to disk (and the derived backend) and rebaseline."""
        with self._lock:
            path = write_state_tfvars(self._working, self._state_path)
            self._maybe_write_backend()
            self._baseline = dict(self._working)
            return path

    def refresh_backend(self) -> Path | None:
        """Re-render the derived backend from current settings + MinIO catalog.

        Used when the MinIO catalog changes out of band. Only rewrites when the
        section is configured for S3 with a resolvable MinIO, so it never
        clobbers an operator's backend file with an empty/stub one.
        """
        with self._lock:
            if self._working.get("backend") != "s3":
                return None
            instance = self._selected_instance()
            if instance is None:
                return None
            return write_backend_hcl(self._working, instance, self._backend_path)

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            record = read_state_tfvars(self._state_path) or default_settings()
            self._working = dict(record)
            self._baseline = dict(record)

    # -- internals -------------------------------------------------------------

    def _maybe_write_backend(self) -> None:
        """Write the derived backend file when it is safe/meaningful to do so.

        - Local backend: write the commented stub (operator chose local).
        - S3 with a resolvable MinIO: write the full S3 backend.
        - S3 without a resolvable MinIO: leave the file untouched so we never
          overwrite a good backend file with empty credentials.
        """
        backend = self._working.get("backend")
        if backend == "s3":
            instance = self._selected_instance()
            if instance is None:
                return
            write_backend_hcl(self._working, instance, self._backend_path)
        else:
            write_backend_hcl(self._working, None, self._backend_path)


__all__ = ["TerraformStore", "StoreError", "SettingsValidationError"]
