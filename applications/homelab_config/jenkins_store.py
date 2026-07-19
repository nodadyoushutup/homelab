"""In-memory working copies of the three Jenkins deploy slices (CICD section).

Each slice (controller, agent-amd64, agent-arm64) is an independent app.tfvars
on disk and the disk is the source of truth. This store keeps a working copy
plus a baseline per slice so it can report ``dirty`` / ``external_change`` /
``disk_present`` for each. Edits mutate the working copy only; :meth:`write`
persists a single slice and :meth:`reload` re-reads it.
"""

from __future__ import annotations

import copy
import logging
import threading
from pathlib import Path

from homelab_config.jenkins_config import (
    SLICE_KEYS,
    SLICES_BY_KEY,
    JenkinsValidationError,
    canonical,
    default_config,
    read_tfvars,
    render_config,
    write_tfvars,
)

logger = logging.getLogger(__name__)


class StoreError(Exception):
    """Raised for store-level errors."""


class JenkinsStore:
    """Thread-safe working copies of the Jenkins controller + agent slices."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._working: dict[str, dict] = {}
        self._baseline: dict[str, dict] = {}
        for key in SLICE_KEYS:
            self._working[key] = default_config(SLICES_BY_KEY[key].kind)
            self._baseline[key] = default_config(SLICES_BY_KEY[key].kind)
        self.reload_all()

    # -- reads -----------------------------------------------------------------

    def get(self, key: str) -> dict:
        self._check(key)
        with self._lock:
            return copy.deepcopy(self._working[key])

    def all(self) -> dict[str, dict]:
        with self._lock:
            return {key: copy.deepcopy(self._working[key]) for key in SLICE_KEYS}

    def render(self, key: str) -> str:
        self._check(key)
        with self._lock:
            return render_config(key, self._working[key])

    def status(self, key: str) -> dict:
        self._check(key)
        slice_ = SLICES_BY_KEY[key]
        with self._lock:
            disk = read_tfvars(key) or default_config(slice_.kind)
            baseline = canonical(key, self._baseline[key])
            return {
                "dirty": canonical(key, self._working[key]) != baseline,
                "external_change": canonical(key, disk) != baseline,
                "disk_present": slice_.path.is_file(),
            }

    def statuses(self) -> dict[str, dict]:
        return {key: self.status(key) for key in SLICE_KEYS}

    # -- mutations -------------------------------------------------------------

    def update(self, key: str, data: dict) -> dict:
        self._check(key)
        from homelab_config.jenkins_config import normalize_config

        record = normalize_config(key, data)
        with self._lock:
            self._working[key] = record
            return copy.deepcopy(record)

    # -- disk sync -------------------------------------------------------------

    def write(self, key: str) -> Path:
        self._check(key)
        with self._lock:
            path = write_tfvars(key, self._working[key])
            self._baseline[key] = copy.deepcopy(self._working[key])
            return path

    def reload(self, key: str) -> None:
        self._check(key)
        slice_ = SLICES_BY_KEY[key]
        with self._lock:
            record = read_tfvars(key) or default_config(slice_.kind)
            self._working[key] = copy.deepcopy(record)
            self._baseline[key] = copy.deepcopy(record)

    def reload_all(self) -> None:
        for key in SLICE_KEYS:
            self.reload(key)

    # -- helpers ---------------------------------------------------------------

    def _check(self, key: str) -> None:
        if key not in SLICES_BY_KEY:
            raise JenkinsValidationError(f"unknown Jenkins slice: {key!r}")


__all__ = ["JenkinsStore", "StoreError", "JenkinsValidationError"]
