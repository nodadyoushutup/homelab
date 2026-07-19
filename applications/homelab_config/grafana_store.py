"""In-memory working copy of the Grafana datasources, backed by config.tfvars.

The on-disk file is the source of truth. This store holds an editable *working*
copy of the datasources list plus a *baseline* of what was last synced with disk
so it can report ``dirty`` (unsaved edits) and ``external_change`` (out-of-band
file edits). Edits mutate the working copy only; nothing touches disk until
:meth:`write`.
"""

from __future__ import annotations

import copy
import logging
import threading
from pathlib import Path

from homelab_config.grafana_config import (
    ConfigValidationError,
    canonical,
    entry_key,
    normalize_datasource,
    order_datasources,
    read_grafana_tfvars,
    render_config,
    write_grafana_tfvars,
)
from homelab_config.paths import GRAFANA_CONFIG_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate datasources)."""


class GrafanaConfigStore:
    """Thread-safe working copy of the Grafana datasources."""

    def __init__(self, path: Path = GRAFANA_CONFIG_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: list[dict] = []
        self._baseline: list[dict] = []
        self.reload()

    def list(self) -> list[dict]:
        """Return the working datasources ordered by name."""
        with self._lock:
            return [copy.deepcopy(e) for e in order_datasources(self._working)]

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_config(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_grafana_tfvars(self._path) or []
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._working),
            }

    def add(self, data: dict) -> dict:
        """Add a datasource (keyed by uid)."""
        entry = normalize_datasource(data)
        key = entry_key(entry)
        with self._lock:
            if self._find(key) is not None:
                raise StoreError(f"data source uid '{key}' already exists")
            self._working.append(entry)
            return copy.deepcopy(entry)

    def update(self, key: str, data: dict) -> dict:
        """Update the datasource identified by uid ``key``."""
        entry = normalize_datasource(data)
        new_key = entry_key(entry)
        with self._lock:
            current = self._find(key)
            if current is None:
                raise StoreError(f"data source uid '{key}' not found")
            if new_key != key and self._find(new_key) is not None:
                raise StoreError(f"data source uid '{new_key}' already exists")
            current.clear()
            current.update(entry)
            return copy.deepcopy(current)

    def delete(self, key: str) -> None:
        """Delete the datasource identified by uid ``key``."""
        with self._lock:
            entry = self._find(key)
            if entry is None:
                raise StoreError(f"data source uid '{key}' not found")
            self._working.remove(entry)

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_grafana_tfvars(self._working, self._path)
            self._baseline = copy.deepcopy(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            entries = read_grafana_tfvars(self._path) or []
            self._working = copy.deepcopy(entries)
            self._baseline = copy.deepcopy(entries)

    def _find(self, key: str) -> dict | None:
        for entry in self._working:
            if entry_key(entry) == str(key):
                return entry
        return None


__all__ = ["GrafanaConfigStore", "StoreError", "ConfigValidationError"]
