"""In-memory working copy of the NFS catalog, backed by nfs.tfvars on disk.

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

from homelab_config.nfs_config import (
    ShareValidationError,
    canonical,
    normalize_share,
    order_shares,
    read_nfs_tfvars,
    render_shares,
    write_nfs_tfvars,
)
from homelab_config.paths import NFS_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate shares)."""


class NfsStore:
    """Thread-safe working copy of the NFS shares."""

    def __init__(self, path: Path = NFS_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: list[dict] = []
        self._baseline: list[dict] = []
        self.reload()

    # -- reads -----------------------------------------------------------------

    def list_shares(self) -> list[dict]:
        """Return the working shares (alphabetical by name)."""
        with self._lock:
            return [dict(share) for share in order_shares(self._working)]

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_shares(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_nfs_tfvars(self._path) or []
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._working),
            }

    # -- mutations (working copy only) ----------------------------------------

    def add(self, data: dict) -> dict:
        """Add a new share to the working copy."""
        share = normalize_share(data)
        with self._lock:
            if self._find(share["name"]) is not None:
                raise StoreError(f"share '{share['name']}' already exists")
            self._working.append(share)
            return dict(share)

    def update(self, name: str, data: dict) -> dict:
        """Update the share named ``name`` in the working copy."""
        merged = {"name": name}
        merged.update(data)
        share = normalize_share(merged)
        with self._lock:
            current = self._find(name)
            if current is None:
                raise StoreError(f"share '{name}' not found")
            if share["name"] != name and self._find(share["name"]) is not None:
                raise StoreError(f"share '{share['name']}' already exists")
            current.update(share)
            return dict(current)

    def delete(self, name: str) -> None:
        """Delete the share named ``name`` from the working copy."""
        with self._lock:
            share = self._find(name)
            if share is None:
                raise StoreError(f"share '{name}' not found")
            self._working.remove(share)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_nfs_tfvars(self._working, self._path)
            self._baseline = [dict(share) for share in self._working]
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits.

        A missing or unparsable file is treated as an empty catalog (the boot
        scaffold writes an empty ``nfs.tfvars`` so a fresh checkout starts clean
        rather than with fabricated default shares).
        """
        with self._lock:
            shares = read_nfs_tfvars(self._path) or []
            self._working = [dict(share) for share in shares]
            self._baseline = [dict(share) for share in shares]

    # -- internals -------------------------------------------------------------

    def _find(self, name: str) -> dict | None:
        for share in self._working:
            if share["name"] == name:
                return share
        return None


__all__ = ["NfsStore", "StoreError", "ShareValidationError"]
