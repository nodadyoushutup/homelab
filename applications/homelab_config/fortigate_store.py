"""In-memory working copy of the FortiGate config, backed by config.tfvars.

The on-disk file is the source of truth. This store holds an editable *working*
copy of the three collections (virtual IPs, firewall policies, DHCP
reservations) plus a *baseline* of what was last synced with disk so it can
report ``dirty`` (unsaved edits) and ``external_change`` (out-of-band file
edits). Edits mutate the working copy only; nothing touches disk until
:meth:`write`.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.fortigate_config import (
    COLLECTIONS,
    ConfigValidationError,
    canonical,
    default_config,
    entry_key,
    normalize,
    order_entries,
    read_fortigate_tfvars,
    render_config,
    write_fortigate_tfvars,
)
from homelab_config.paths import FORTIGATE_CONFIG_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate entries)."""


class FortigateConfigStore:
    """Thread-safe working copy of the FortiGate declarative config."""

    def __init__(self, path: Path = FORTIGATE_CONFIG_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: dict = default_config()
        self._baseline: dict = default_config()
        self.reload()

    @staticmethod
    def _check_collection(collection: str) -> None:
        if collection not in COLLECTIONS:
            raise StoreError(f"unknown collection '{collection}'")

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working config with each collection ordered by key."""
        with self._lock:
            return {
                collection: [dict(e) for e in order_entries(collection, self._working[collection])]
                for collection in COLLECTIONS
            }

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_config(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_fortigate_tfvars(self._path) or default_config()
            baseline = canonical(self._baseline)
            counts = {c: len(self._working[c]) for c in COLLECTIONS}
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "counts": counts,
            }

    # -- mutations (working copy only) ----------------------------------------

    def add(self, collection: str, data: dict) -> dict:
        """Add an entry to the named collection."""
        self._check_collection(collection)
        entry = normalize(collection, data)
        key = entry_key(collection, entry)
        with self._lock:
            if self._find(collection, key) is not None:
                raise StoreError(f"{collection} entry '{key}' already exists")
            self._working[collection].append(entry)
            return dict(entry)

    def update(self, collection: str, key: str, data: dict) -> dict:
        """Update the entry identified by ``key`` in the named collection."""
        self._check_collection(collection)
        entry = normalize(collection, data)
        new_key = entry_key(collection, entry)
        with self._lock:
            current = self._find(collection, key)
            if current is None:
                raise StoreError(f"{collection} entry '{key}' not found")
            if new_key != key and self._find(collection, new_key) is not None:
                raise StoreError(f"{collection} entry '{new_key}' already exists")
            current.clear()
            current.update(entry)
            return dict(current)

    def delete(self, collection: str, key: str) -> None:
        """Delete the entry identified by ``key`` from the named collection."""
        self._check_collection(collection)
        with self._lock:
            entry = self._find(collection, key)
            if entry is None:
                raise StoreError(f"{collection} entry '{key}' not found")
            self._working[collection].remove(entry)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_fortigate_tfvars(self._working, self._path)
            self._baseline = self._clone(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            config = read_fortigate_tfvars(self._path) or default_config()
            self._working = self._clone(config)
            self._baseline = self._clone(config)

    # -- internals -------------------------------------------------------------

    @staticmethod
    def _clone(config: dict) -> dict:
        return {c: [dict(e) for e in config.get(c, [])] for c in COLLECTIONS}

    def _find(self, collection: str, key: str) -> dict | None:
        for entry in self._working[collection]:
            if entry_key(collection, entry) == str(key):
                return entry
        return None


__all__ = ["FortigateConfigStore", "StoreError", "ConfigValidationError"]
