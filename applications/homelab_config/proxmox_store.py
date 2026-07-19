"""In-memory working copy of the Proxmox credentials, backed by proxmox.tfvars.

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

from homelab_config.paths import PROXMOX_TFVARS
from homelab_config.proxmox_config import (
    CredentialsValidationError,
    canonical,
    default_credentials,
    normalize_credentials,
    read_proxmox_tfvars,
    render_credentials,
    write_proxmox_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors."""


class ProxmoxStore:
    """Thread-safe working copy of the Proxmox credentials record."""

    def __init__(self, path: Path = PROXMOX_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: dict = default_credentials()
        self._baseline: dict = default_credentials()
        self.reload()

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working credentials record."""
        with self._lock:
            return dict(self._working)

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_credentials(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_proxmox_tfvars(self._path) or default_credentials()
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
            }

    # -- mutations (working copy only) ----------------------------------------

    def update(self, data: dict) -> dict:
        """Replace the working credentials record."""
        record = normalize_credentials(data)
        with self._lock:
            self._working = record
            return dict(self._working)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_proxmox_tfvars(self._working, self._path)
            self._baseline = dict(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits.

        A missing or unparsable file is treated as the default (empty) record
        (the boot scaffold writes a default ``proxmox.tfvars`` so a fresh
        checkout starts clean rather than with fabricated credentials).
        """
        with self._lock:
            record = read_proxmox_tfvars(self._path) or default_credentials()
            self._working = dict(record)
            self._baseline = dict(record)


__all__ = ["ProxmoxStore", "StoreError", "CredentialsValidationError"]
