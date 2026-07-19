"""In-memory working copy of the Cloudflare DNS config, backed by config.tfvars.

The on-disk file is the source of truth. This store holds an editable *working*
copy (zone id + records) plus a *baseline* of what was last synced with disk so
it can report ``dirty`` (unsaved edits) and ``external_change`` (out-of-band file
edits). Edits mutate the working copy only; nothing touches disk until
:meth:`write`.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

from homelab_config.cloudflare_dns_config import (
    RecordValidationError,
    canonical,
    normalize_record,
    normalize_zone_id,
    order_records,
    read_cloudflare_tfvars,
    render_config,
    write_cloudflare_tfvars,
)
from homelab_config.paths import CLOUDFLARE_CONFIG_TFVARS

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate records)."""


class CloudflareDnsStore:
    """Thread-safe working copy of the Cloudflare zone id + DNS records."""

    def __init__(self, path: Path = CLOUDFLARE_CONFIG_TFVARS) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._zone_id: str = ""
        self._records: list[dict] = []
        self._baseline_zone: str = ""
        self._baseline_records: list[dict] = []
        self.reload()

    # -- reads -----------------------------------------------------------------

    def get(self) -> dict:
        """Return the working zone id and records (records alphabetical by key)."""
        with self._lock:
            return {
                "zone_id": self._zone_id,
                "records": [dict(r) for r in order_records(self._records)],
            }

    def render(self) -> str:
        """Return the rendered tfvars for the current working copy."""
        with self._lock:
            return render_config(self._zone_id, self._records)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_cloudflare_tfvars(self._path) or {"zone_id": "", "records": []}
            baseline = canonical(self._baseline_zone, self._baseline_records)
            return {
                "dirty": canonical(self._zone_id, self._records) != baseline,
                "external_change": canonical(disk["zone_id"], disk["records"])
                != baseline,
                "disk_present": self._path.is_file(),
                "count": len(self._records),
            }

    # -- mutations (working copy only) ----------------------------------------

    def set_zone_id(self, value: str) -> str:
        """Replace the working zone id."""
        with self._lock:
            self._zone_id = normalize_zone_id(value)
            return self._zone_id

    def add(self, data: dict) -> dict:
        """Add a new record to the working copy."""
        record = normalize_record(data)
        with self._lock:
            if self._find(record["key"]) is not None:
                raise StoreError(f"record '{record['key']}' already exists")
            self._records.append(record)
            return dict(record)

    def update(self, key: str, data: dict) -> dict:
        """Update the record with ``key`` in the working copy."""
        merged = dict(data)
        merged.setdefault("key", key)
        record = normalize_record(merged)
        with self._lock:
            current = self._find(key)
            if current is None:
                raise StoreError(f"record '{key}' not found")
            if record["key"] != key and self._find(record["key"]) is not None:
                raise StoreError(f"record '{record['key']}' already exists")
            current.update(record)
            return dict(current)

    def delete(self, key: str) -> None:
        """Delete the record with ``key`` from the working copy."""
        with self._lock:
            record = self._find(key)
            if record is None:
                raise StoreError(f"record '{key}' not found")
            self._records.remove(record)

    # -- disk sync -------------------------------------------------------------

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_cloudflare_tfvars(self._zone_id, self._records, self._path)
            self._baseline_zone = self._zone_id
            self._baseline_records = [dict(r) for r in self._records]
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            data = read_cloudflare_tfvars(self._path) or {"zone_id": "", "records": []}
            self._zone_id = data["zone_id"]
            self._records = [dict(r) for r in data["records"]]
            self._baseline_zone = self._zone_id
            self._baseline_records = [dict(r) for r in self._records]

    # -- internals -------------------------------------------------------------

    def _find(self, key: str) -> dict | None:
        for record in self._records:
            if record["key"] == key:
                return record
        return None


__all__ = ["CloudflareDnsStore", "StoreError", "RecordValidationError"]
