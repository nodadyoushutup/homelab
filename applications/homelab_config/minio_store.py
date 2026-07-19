"""In-memory working copy of the MinIO catalog, backed by minio.tfvars on disk.

The on-disk file is the source of truth. This store holds an editable *working*
copy plus a *baseline* snapshot of what we last synced with disk, so we can
report:

- ``dirty``: the working copy has unsaved edits (differs from baseline).
- ``external_change``: the file on disk changed out of band (differs from
  baseline) - e.g. someone edited it by hand while the app was running.

Edits mutate the working copy only; nothing touches disk until :meth:`write` is
called. :meth:`reload` re-reads the file, discarding unsaved edits.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.minio_config import (
    InstanceValidationError,
    canonical,
    normalize_instance,
    order_instances,
    read_minio_tfvars,
    render_instances,
    write_minio_tfvars,
)
from homelab_config.paths import MINIO_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate instances)."""


class MinioStore:
    """Thread-safe working copy of the MinIO instances."""

    def __init__(self, path: Path = MINIO_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: list[dict] = []
        self._baseline: list[dict] = []
        self.reload()

    # -- reads -----------------------------------------------------------------

    def list_instances(self) -> list[dict]:
        """Return the working instances (alphabetical by name)."""
        with self._lock:
            return [dict(inst) for inst in order_instances(self._working)]

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_instances(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_minio_tfvars(self._path) or []
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._working),
            }

    # -- mutations (working copy only) ----------------------------------------

    def add(self, data: dict) -> dict:
        """Add a new instance to the working copy."""
        inst = normalize_instance(data)
        with self._lock:
            if self._find(inst["name"]) is not None:
                raise StoreError(f"instance '{inst['name']}' already exists")
            self._working.append(inst)
            return dict(inst)

    def update(self, name: str, data: dict) -> dict:
        """Update the instance named ``name`` in the working copy."""
        merged = {"name": name}
        merged.update(data)
        inst = normalize_instance(merged)
        with self._lock:
            current = self._find(name)
            if current is None:
                raise StoreError(f"instance '{name}' not found")
            if inst["name"] != name and self._find(inst["name"]) is not None:
                raise StoreError(f"instance '{inst['name']}' already exists")
            current.update(inst)
            return dict(current)

    def delete(self, name: str) -> None:
        """Delete the instance named ``name`` from the working copy."""
        with self._lock:
            inst = self._find(name)
            if inst is None:
                raise StoreError(f"instance '{name}' not found")
            self._working.remove(inst)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_minio_tfvars(self._working, self._path)
            self._baseline = [dict(inst) for inst in self._working]
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits.

        A missing or unparsable file is treated as an empty catalog (the boot
        scaffold writes an empty ``minio.tfvars`` so a fresh checkout starts
        clean rather than with fabricated default instances).
        """
        with self._lock:
            instances = read_minio_tfvars(self._path) or []
            self._working = [dict(inst) for inst in instances]
            self._baseline = [dict(inst) for inst in instances]

    # -- internals -------------------------------------------------------------

    def _find(self, name: str) -> dict | None:
        for inst in self._working:
            if inst["name"] == name:
                return inst
        return None


__all__ = ["MinioStore", "StoreError", "InstanceValidationError"]
