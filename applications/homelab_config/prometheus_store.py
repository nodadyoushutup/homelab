"""In-memory working copy of the Prometheus scrape config, backed by prometheus.yaml.

The on-disk file is the source of truth. This store holds an editable *working*
copy (global settings, remote_write endpoints, and scrape jobs) plus a *baseline*
of what was last synced with disk so it can report ``dirty`` (unsaved edits) and
``external_change`` (out-of-band file edits). Edits mutate the working copy only;
nothing touches disk until :meth:`write`.
"""

from __future__ import annotations

import copy
import logging
import threading
from pathlib import Path

from homelab_config.prometheus_config import (
    ConfigValidationError,
    canonical,
    default_config,
    job_key,
    normalize_global,
    normalize_job,
    normalize_remote_write,
    read_prometheus_yaml,
    render_config,
    write_prometheus_yaml,
)
from homelab_config.paths import PROMETHEUS_YAML

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors (missing/duplicate jobs)."""


class PrometheusConfigStore:
    """Thread-safe working copy of the Prometheus scrape config."""

    def __init__(self, path: Path = PROMETHEUS_YAML) -> None:
        self._path = path
        self._lock = threading.RLock()
        self._working: dict = default_config()
        self._baseline: dict = default_config()
        self.reload()

    def get(self) -> dict:
        """Return a deep copy of the working config."""
        with self._lock:
            return copy.deepcopy(self._working)

    def render(self) -> str:
        """Return the rendered prometheus.yaml for the working copy."""
        with self._lock:
            return render_config(self._working)

    def status(self) -> dict:
        """Return drift/status flags for the UI."""
        with self._lock:
            disk = read_prometheus_yaml(self._path) or default_config()
            baseline = canonical(self._baseline)
            return {
                "dirty": canonical(self._working) != baseline,
                "external_change": canonical(disk) != baseline,
                "disk_present": self._path.is_file(),
                "job_count": len(self._working.get("scrape_configs", [])),
            }

    def set_global(self, data: dict) -> dict:
        record = normalize_global(data or {})
        with self._lock:
            self._working["global"] = record
            return copy.deepcopy(record)

    def set_remote_write(self, entries: object) -> list[dict]:
        records = normalize_remote_write(entries)
        with self._lock:
            self._working["remote_write"] = records
            return copy.deepcopy(records)

    def add_job(self, data: dict) -> dict:
        job = normalize_job(data)
        key = job_key(job)
        with self._lock:
            if self._find(key) is not None:
                raise StoreError(f"scrape job '{key}' already exists")
            self._working["scrape_configs"].append(job)
            return copy.deepcopy(job)

    def update_job(self, key: str, data: dict) -> dict:
        job = normalize_job(data)
        new_key = job_key(job)
        with self._lock:
            current = self._find(key)
            if current is None:
                raise StoreError(f"scrape job '{key}' not found")
            if new_key != key and self._find(new_key) is not None:
                raise StoreError(f"scrape job '{new_key}' already exists")
            current.clear()
            current.update(job)
            return copy.deepcopy(current)

    def delete_job(self, key: str) -> None:
        with self._lock:
            job = self._find(key)
            if job is None:
                raise StoreError(f"scrape job '{key}' not found")
            self._working["scrape_configs"].remove(job)

    def write(self) -> Path:
        """Persist the working copy to disk and update the baseline."""
        with self._lock:
            path = write_prometheus_yaml(self._working, self._path)
            self._baseline = copy.deepcopy(self._working)
            return path

    def reload(self) -> None:
        """Reload the working copy from disk, discarding unsaved edits."""
        with self._lock:
            config = read_prometheus_yaml(self._path) or default_config()
            self._working = copy.deepcopy(config)
            self._baseline = copy.deepcopy(config)

    def _find(self, key: str) -> dict | None:
        for job in self._working.get("scrape_configs", []):
            if job_key(job) == str(key):
                return job
        return None


__all__ = ["PrometheusConfigStore", "StoreError", "ConfigValidationError"]
