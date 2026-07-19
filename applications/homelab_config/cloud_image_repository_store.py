"""In-memory working copy of the Cloud Image Repository config, backed by
app.tfvars on disk.

The on-disk file is the source of truth. This store holds an editable *working*
copy plus a *baseline* snapshot of what we last synced with disk, so we can
report ``dirty`` (unsaved edits) and ``external_change`` (the file changed out
of band). Edits mutate the working copy only; nothing touches disk until
:meth:`write` is called. :meth:`reload` re-reads the file, discarding edits.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.cloud_image_repository_config import (
    CloudImageRepositoryValidationError,
    canonical,
    default_config,
    normalize_config,
    read_cloud_image_repository_tfvars,
    render_config,
    write_cloud_image_repository_tfvars,
)
from homelab_config.paths import CLOUD_IMAGE_REPOSITORY_APP_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors."""


class CloudImageRepositoryStore:
    """Thread-safe working copy of the Cloud Image Repository config."""

    def __init__(self, path: Path = CLOUD_IMAGE_REPOSITORY_APP_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: dict = default_config()
        self._baseline: dict = default_config()
        self.reload()

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working config record."""
        with self._lock:
            return _deepcopy(self._working)

    def render(self) -> str:
        """Return the rendered app.tfvars for the current working copy."""
        with self._lock:
            return render_config(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_cloud_image_repository_tfvars(self._path) or default_config()
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
            }

    # -- mutations (working copy only) ----------------------------------------

    def update(self, data: dict) -> dict:
        """Replace the working config record."""
        record = normalize_config(data)
        with self._lock:
            self._working = record
            return _deepcopy(self._working)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_cloud_image_repository_tfvars(self._working, self._path)
            self._baseline = _deepcopy(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            record = read_cloud_image_repository_tfvars(self._path) or default_config()
            self._working = _deepcopy(record)
            self._baseline = _deepcopy(record)


def _deepcopy(config: dict) -> dict:
    """Deep-ish copy of the nested Cloud Image Repository config structure."""
    placement = config.get("placement", {})
    return {
        "docker_machine": config.get("docker_machine", ""),
        "dns_nameservers": list(config.get("dns_nameservers", [])),
        "placement": {
            "constraints": list(placement.get("constraints", [])),
            "platforms": [
                {"os": p.get("os", ""), "architecture": p.get("architecture", "")}
                for p in placement.get("platforms", [])
            ],
        },
        "nfs_share": config.get("nfs_share", ""),
        "nfs_subpath": config.get("nfs_subpath", ""),
    }


__all__ = [
    "CloudImageRepositoryStore",
    "StoreError",
    "CloudImageRepositoryValidationError",
]
