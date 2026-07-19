"""In-memory working copy of the Packer build defaults, backed by build.pkrvars.hcl.

The on-disk file is the source of truth. This store holds an editable *working*
copy of the settings object plus a *baseline* of what was last synced with disk
so it can report ``dirty`` (unsaved edits) and ``external_change`` (out-of-band
file edits). Edits mutate the working copy only; nothing touches disk until
:meth:`write`.
"""

from __future__ import annotations

import copy
import logging
import threading
from pathlib import Path

from homelab_config.packer_config import (
    ConfigValidationError,
    canonical,
    default_settings,
    normalize,
    read_packer_pkrvars,
    render_settings,
    write_packer_pkrvars,
)
from homelab_config.paths import PACKER_BUILD_PKRVARS

logger = logging.getLogger(__name__)


class PackerConfigStore:
    """Thread-safe working copy of the Packer build defaults."""

    def __init__(self, path: Path = PACKER_BUILD_PKRVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: dict = default_settings()
        self._baseline: dict = default_settings()
        self.reload()

    def get(self) -> dict:
        """Return a deep copy of the working settings."""
        with self._lock:
            return copy.deepcopy(self._working)

    def render(self) -> str:
        """Return the rendered var-file for the working copy."""
        with self._lock:
            return render_settings(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_packer_pkrvars(self._path) or default_settings()
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
            }

    def set(self, data: dict) -> dict:
        """Replace the working settings (auto-save)."""
        record = normalize(data or {})
        with self._lock:
            self._working = record
            return copy.deepcopy(record)

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_packer_pkrvars(self._working, self._path)
            self._baseline = copy.deepcopy(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            settings = read_packer_pkrvars(self._path) or default_settings()
            self._working = copy.deepcopy(settings)
            self._baseline = copy.deepcopy(settings)


__all__ = ["PackerConfigStore", "ConfigValidationError"]
