"""In-memory working copy of a provider credentials file, spec-driven.

Mirrors :class:`homelab_config.proxmox_store.ProxmoxStore` but is generic over a
:class:`ProviderSpec`. The on-disk ``providers/<app>.tfvars`` is the source of
truth; the store holds an editable *working* copy plus a *baseline* of what was
last synced with disk so it can report ``dirty`` (unsaved edits) and
``external_change`` (out-of-band file edits). Edits only mutate the working
copy; nothing touches disk until :meth:`write`.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.provider_config_generic import (
    ProviderValidationError,
    canonical,
    default_record,
    normalize,
    read,
    render,
    write,
)
from homelab_config.provider_specs import ProviderSpec

logger = logging.getLogger(__name__)


class GenericProviderStore:
    """Thread-safe working copy of a single-object provider credentials record."""

    def __init__(self, spec: ProviderSpec, path: Path | None = None) -> None:
        self._spec = spec
        self._path = path or spec.tfvars_path
        self._lock = threading.RLock()
        self._working: dict = default_record(spec)
        self._baseline: dict = default_record(spec)
        self.reload()

    @property
    def spec(self) -> ProviderSpec:
        return self._spec

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working credentials record."""
        with self._lock:
            return dict(self._working)

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render(self._spec, self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read(self._spec, self._path) or default_record(self._spec)
            baseline = canonical(self._spec, self._baseline)
            return {
                "dirty": canonical(self._spec, self._working) != baseline,
                "external_change": canonical(self._spec, disk) != baseline,
                "disk_present": self._path.is_file(),
            }

    # -- mutations (working copy only) ----------------------------------------

    def update(self, data: dict) -> dict:
        """Replace the working credentials record."""
        record = normalize(self._spec, data)
        with self._lock:
            self._working = record
            return dict(self._working)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write(self._spec, self._working, self._path)
            self._baseline = dict(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            record = read(self._spec, self._path) or default_record(self._spec)
            self._working = dict(record)
            self._baseline = dict(record)


__all__ = ["GenericProviderStore", "ProviderValidationError"]
